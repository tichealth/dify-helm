locals {
  name_prefix = var.project_name
}

resource "random_id" "suffix" {
  byte_length = 2
}

resource "azurerm_resource_group" "rg" {
  count    = var.resource_group_name == "" ? 1 : 0
  name     = "${local.name_prefix}-rg-${random_id.suffix.hex}"
  location = var.location
  tags     = var.tags
}

data "azurerm_resource_group" "existing_rg" {
  count = var.resource_group_name != "" ? 1 : 0
  name  = var.resource_group_name
}

locals {
  rg_name     = var.resource_group_name != "" ? data.azurerm_resource_group.existing_rg[0].name : azurerm_resource_group.rg[0].name
  rg_location = var.resource_group_name != "" ? data.azurerm_resource_group.existing_rg[0].location : azurerm_resource_group.rg[0].location
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${local.name_prefix}-aks-${random_id.suffix.hex}"
  location            = local.rg_location
  resource_group_name = local.rg_name
  dns_prefix          = "${local.name_prefix}-${random_id.suffix.hex}"

  default_node_pool {
    name       = "system"
    node_count = var.node_count
    vm_size    = var.vm_size
    
    # Required when changing vm_size or other immutable properties
    # Azure will create a temporary pool, migrate workloads, then delete the old pool
    # Name must be 1-12 chars, lowercase letters and numbers only
    temporary_name_for_rotation = "systemtemp"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# Optional Spot node pool for interruptible workloads
resource "azurerm_kubernetes_cluster_node_pool" "spot" {
  count                 = var.enable_spot_node_pool ? 1 : 0
  name                  = var.spot_node_pool_name
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.spot_vm_size
  node_count            = var.spot_node_count

  priority        = "Spot"
  eviction_policy = "Delete"
  spot_max_price  = var.spot_max_price

  orchestrator_version = null

  # Required when changing vm_size or other immutable properties
  # Azure will create a temporary pool, migrate workloads, then delete the old pool
  # Name must be 1-12 chars, lowercase letters and numbers only
  temporary_name_for_rotation = "spottemp"

  node_taints = [
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
  ]

  tags = merge(var.tags, { "pool" = var.spot_node_pool_name })
}

# Wait for AKS DNS/control plane to be ready before proceeding
# This prevents "no such host" errors when Terraform tries to connect to the API server
# Simplified version with basic DNS check
resource "null_resource" "aks_dns_ready" {
  provisioner "local-exec" {
    command = "bash -c 'API_FQDN=\"${azurerm_kubernetes_cluster.aks.fqdn}\"; echo \"Waiting for AKS API server DNS: $API_FQDN\"; for i in {1..60}; do echo \"Attempt $i/60: Checking DNS...\"; if getent hosts \"$API_FQDN\" > /dev/null 2>&1 || nslookup \"$API_FQDN\" > /dev/null 2>&1 || host \"$API_FQDN\" > /dev/null 2>&1; then echo \"✓ DNS resolved: $(getent hosts \"$API_FQDN\" 2>/dev/null || echo OK)\"; exit 0; fi; sleep 10; done; echo \"WARNING: DNS timeout after 600s. Continuing anyway...\"; exit 0'"
  }

  triggers = {
    aks_id   = azurerm_kubernetes_cluster.aks.id
    aks_fqdn = azurerm_kubernetes_cluster.aks.fqdn
    # Also trigger on node pool changes (new node pool might cause DNS refresh)
    node_pool = try(azurerm_kubernetes_cluster_node_pool.spot[0].id, "none")
  }

  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_kubernetes_cluster_node_pool.spot
  ]
}

# Optional: Add a time delay after DNS check to ensure control plane is fully ready
# This provides additional resilience beyond DNS resolution
resource "time_sleep" "aks_control_plane_ready" {
  depends_on = [null_resource.aks_dns_ready]

  create_duration = "30s" # Wait 30 seconds after DNS is ready
}

# NOTE: Kubernetes and Helm providers removed - using Helm directly via deploy.sh
# This avoids Terraform provider timing issues

# VNet for PostgreSQL private access (optional)
resource "azurerm_virtual_network" "postgres" {
  count               = var.use_azure_postgres && var.create_vnet_for_postgres ? 1 : 0
  name                = "${local.name_prefix}-vnet-${random_id.suffix.hex}"
  location            = local.rg_location
  resource_group_name = local.rg_name
  address_space       = var.vnet_address_space
  tags                = merge(var.tags, { component = "network" })
}

# Subnet delegated to PostgreSQL Flexible Server
resource "azurerm_subnet" "postgres" {
  count                = var.use_azure_postgres && var.create_vnet_for_postgres ? 1 : 0
  name                 = "${local.name_prefix}-postgres-subnet"
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.postgres[0].name
  address_prefixes     = var.postgres_subnet_address_prefixes

  delegation {
    name = "postgres-delegation"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }
}

# Management/Jumpbox subnet for VMs to access PostgreSQL
# This subnet can have public IPs and allows you to spin up VMs for database dumps, maintenance, etc.
resource "azurerm_subnet" "management" {
  count                = var.use_azure_postgres && var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? 1 : 0
  name                 = "${local.name_prefix}-management-subnet"
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.postgres[0].name
  address_prefixes     = var.management_subnet_address_prefixes
  # No delegation needed - this is a regular subnet for VMs
}

# Network Security Group for management subnet
resource "azurerm_network_security_group" "management" {
  count               = var.use_azure_postgres && var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? 1 : 0
  name                = "${local.name_prefix}-management-nsg"
  location            = local.rg_location
  resource_group_name = local.rg_name
  tags                = merge(var.tags, { component = "network", purpose = "management" })
}

# NSG Rule: Allow SSH from Internet to management subnet (for VM access)
resource "azurerm_network_security_rule" "management_ssh" {
  count                       = var.use_azure_postgres && var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? 1 : 0
  name                       = "AllowSSH"
  priority                   = 1000
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "22"
  source_address_prefix      = "Internet"
  destination_address_prefix = "*"
  resource_group_name        = local.rg_name
  network_security_group_name = azurerm_network_security_group.management[0].name
}

# NSG Rule: Allow RDP from Internet to management subnet (for Windows VMs, optional)
resource "azurerm_network_security_rule" "management_rdp" {
  count                       = var.use_azure_postgres && var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? 1 : 0
  name                       = "AllowRDP"
  priority                   = 1001
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "3389"
  source_address_prefix      = "Internet"
  destination_address_prefix = "*"
  resource_group_name        = local.rg_name
  network_security_group_name = azurerm_network_security_group.management[0].name
}

# NSG Rule: Allow outbound to PostgreSQL (port 5432) from management subnet
resource "azurerm_network_security_rule" "management_to_postgres" {
  count                       = var.use_azure_postgres && var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? 1 : 0
  name                       = "AllowPostgreSQL"
  priority                   = 1002
  direction                  = "Outbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "5432"
  source_address_prefix      = length(var.management_subnet_address_prefixes) > 0 ? var.management_subnet_address_prefixes[0] : "*"
  destination_address_prefix = length(var.postgres_subnet_address_prefixes) > 0 ? var.postgres_subnet_address_prefixes[0] : "*"
  resource_group_name        = local.rg_name
  network_security_group_name = azurerm_network_security_group.management[0].name
}

# Associate NSG with management subnet
resource "azurerm_subnet_network_security_group_association" "management" {
  count                     = var.use_azure_postgres && var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? 1 : 0
  subnet_id                 = azurerm_subnet.management[0].id
  network_security_group_id = azurerm_network_security_group.management[0].id
}

# Private DNS Zone for PostgreSQL
resource "azurerm_private_dns_zone" "postgres" {
  count               = var.use_azure_postgres && var.create_vnet_for_postgres ? 1 : 0
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = local.rg_name
  tags                = merge(var.tags, { component = "dns" })
}

# Link Private DNS Zone to PostgreSQL VNet
resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  count                 = var.use_azure_postgres && var.create_vnet_for_postgres ? 1 : 0
  name                  = "${local.name_prefix}-postgres-dns-link"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.postgres[0].name
  virtual_network_id    = azurerm_virtual_network.postgres[0].id
  registration_enabled  = false
  tags                  = var.tags
}

# Link Private DNS Zone to AKS VNet (so AKS pods can resolve private FQDN)
# Count uses vars only (not local.aks_vnet_id) so Terraform can evaluate it at plan time
resource "azurerm_private_dns_zone_virtual_network_link" "aks" {
  count                 = var.use_azure_postgres && var.create_vnet_for_postgres ? 1 : 0
  name                  = "${local.name_prefix}-aks-dns-link"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.postgres[0].name
  virtual_network_id    = local.aks_vnet_id
  registration_enabled  = false
  tags                  = var.tags

  depends_on = [data.azurerm_resources.aks_vnets]
}

# Get AKS node resource group to find the VNet for peering
data "azurerm_resource_group" "aks_node" {
  count = var.use_azure_postgres && var.create_vnet_for_postgres ? 1 : 0
  name  = azurerm_kubernetes_cluster.aks.node_resource_group
}

# Get all VNets in AKS node resource group (AKS creates a VNet here)
# Using azurerm_resources to find VNets by resource type
# Note: AKS VNet is created asynchronously, so we need to wait for AKS to be fully ready
data "azurerm_resources" "aks_vnets" {
  count               = var.use_azure_postgres && var.create_vnet_for_postgres ? 1 : 0
  resource_group_name = data.azurerm_resource_group.aks_node[0].name
  type                = "Microsoft.Network/virtualNetworks"

  # Ensure AKS is fully created before querying for VNet
  depends_on = [
    azurerm_kubernetes_cluster.aks,
    time_sleep.aks_control_plane_ready
  ]
}

locals {
  # Get the first VNet from AKS node resource group (AKS typically creates one VNet)
  # AKS VNet ID is available after AKS is created
  aks_vnet_id = var.create_vnet_for_postgres && length(data.azurerm_resources.aks_vnets) > 0 && length(data.azurerm_resources.aks_vnets[0].resources) > 0 ? data.azurerm_resources.aks_vnets[0].resources[0].id : null
  aks_vnet_name = local.aks_vnet_id != null ? split("/", local.aks_vnet_id)[8] : null
}

# VNet Peering: PostgreSQL VNet -> AKS VNet
# Count uses vars only so Terraform can evaluate it at plan time
resource "azurerm_virtual_network_peering" "postgres_to_aks" {
  count                     = var.use_azure_postgres && var.create_vnet_for_postgres ? 1 : 0
  name                      = "${local.name_prefix}-postgres-to-aks"
  resource_group_name       = local.rg_name
  virtual_network_name      = azurerm_virtual_network.postgres[0].name
  remote_virtual_network_id = local.aks_vnet_id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = false
  use_remote_gateways       = false

  depends_on = [data.azurerm_resources.aks_vnets]
}

# VNet Peering: AKS VNet -> PostgreSQL VNet (bidirectional)
# Count uses vars only so Terraform can evaluate it at plan time
resource "azurerm_virtual_network_peering" "aks_to_postgres" {
  count                     = var.use_azure_postgres && var.create_vnet_for_postgres ? 1 : 0
  name                      = "${local.name_prefix}-aks-to-postgres"
  resource_group_name       = data.azurerm_resource_group.aks_node[0].name
  virtual_network_name      = local.aks_vnet_name
  remote_virtual_network_id = azurerm_virtual_network.postgres[0].id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = false
  use_remote_gateways       = false

  depends_on = [data.azurerm_resources.aks_vnets]
}

# Azure Database for PostgreSQL Flexible (optional, when use_azure_postgres = true)
locals {
  pg_server_name = var.postgresql_server_name != "" ? var.postgresql_server_name : "${local.name_prefix}-pg-${random_id.suffix.hex}"
  # When VNet is created, force public access to false
  postgres_public_access = var.create_vnet_for_postgres ? false : var.postgres_public_access
}

resource "azurerm_postgresql_flexible_server" "pg" {
  count                         = var.use_azure_postgres ? 1 : 0
  name                          = local.pg_server_name
  resource_group_name           = local.rg_name
  location                      = local.rg_location
  version                       = var.postgres_version
  administrator_login           = var.postgresql_username
  administrator_password        = var.postgresql_password
  sku_name                      = var.postgres_sku_name
  storage_mb                    = var.postgres_storage_mb
  public_network_access_enabled = local.postgres_public_access

  # VNet integration (when VNet is created)
  delegated_subnet_id = var.create_vnet_for_postgres ? azurerm_subnet.postgres[0].id : null
  private_dns_zone_id = var.create_vnet_for_postgres ? azurerm_private_dns_zone.postgres[0].id : null

  tags = merge(var.tags, { component = "postgres" })

  # Ignore zone changes to prevent Terraform from trying to modify it
  # Zone can be null in state but "1" in Azure, which causes update errors
  lifecycle {
    ignore_changes = [zone]
  }

  depends_on = [
    azurerm_subnet.postgres,
    azurerm_private_dns_zone.postgres
  ]
}

# Wait for Azure to register the PG private endpoint A record (e.g. c8dd...) in the Private DNS Zone.
# We then create dify-pg-<suffix> pointing at the same IP so Dify/plugin-daemon can resolve it.
resource "time_sleep" "pg_private_dns_ready" {
  count = var.use_azure_postgres && var.create_vnet_for_postgres ? 1 : 0

  create_duration = "90s"

  depends_on = [azurerm_postgresql_flexible_server.pg]
}

# Create A record dify-pg-<suffix> -> PG private IP when missing. Azure auto-registers an internal
# name (e.g. c8dd397c96a1), not our server name; app uses dify-pg-<suffix>.privatelink.postgres.database.azure.com.
resource "null_resource" "create_pg_app_dns_record" {
  count = var.use_azure_postgres && var.create_vnet_for_postgres ? 1 : 0

  triggers = {
    pg_id   = azurerm_postgresql_flexible_server.pg[0].id
    zone_id = azurerm_private_dns_zone.postgres[0].id
    name    = local.pg_server_name
  }

  depends_on = [
    azurerm_private_dns_zone.postgres[0],
    time_sleep.pg_private_dns_ready[0]
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      RG='${replace(local.rg_name, "'", "'\"'\"'")}'
      ZONE='${replace(azurerm_private_dns_zone.postgres[0].name, "'", "'\"'\"'")}'
      PG_NAME='${replace(local.pg_server_name, "'", "'\"'\"'")}'
      if az network private-dns record-set a show -g "$RG" --zone-name "$ZONE" -n "$PG_NAME" &>/dev/null; then
        echo "A record $PG_NAME exists, skipping."
        exit 0
      fi
      IP=$(az network private-dns record-set a list -g "$RG" --zone-name "$ZONE" -o json --query '[0].aRecords[0].ipv4Address' -o tsv)
      if [ -z "$IP" ] || [ "$IP" = "null" ]; then
        echo "No A record in zone yet; retrying in 30s..." >&2
        sleep 30
        IP=$(az network private-dns record-set a list -g "$RG" --zone-name "$ZONE" -o json --query '[0].aRecords[0].ipv4Address' -o tsv)
      fi
      if [ -z "$IP" ] || [ "$IP" = "null" ]; then
        echo "ERROR: No A record in zone. Has Azure registered the PG private endpoint? Restart PG and re-apply." >&2
        exit 1
      fi
      # Verify: IP format and expected postgres subnet (10.1.1.0/24)
      if ! echo "$IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo "ERROR: Verify failed – invalid IP format: $IP" >&2
        exit 1
      fi
      if ! echo "$IP" | grep -qE '^10\.1\.1\.'; then
        echo "WARN: Verify – IP $IP not in postgres subnet 10.1.1.0/24; continuing anyway." >&2
      fi
      echo "Verify OK: Azure internal A record exists, IP=$IP. Creating $PG_NAME -> $IP ..."
      az network private-dns record-set a add-record -g "$RG" --zone-name "$ZONE" --record-set-name "$PG_NAME" --ipv4-address "$IP"
      echo "Created A record $PG_NAME -> $IP"
    EOT
    interpreter = ["bash", "-c"]
  }
}

resource "azurerm_postgresql_flexible_server_database" "db" {
  count     = var.use_azure_postgres ? 1 : 0
  name      = var.postgresql_database
  server_id = azurerm_postgresql_flexible_server.pg[0].id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Plugin daemon database
resource "azurerm_postgresql_flexible_server_database" "plugin_db" {
  count     = var.use_azure_postgres ? 1 : 0
  name      = var.plugin_database_name
  server_id = azurerm_postgresql_flexible_server.pg[0].id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "all" {
  count            = var.use_azure_postgres && var.postgres_public_access && var.postgres_open_firewall_all ? 1 : 0
  name             = "allow-all-ipv4"
  server_id        = azurerm_postgresql_flexible_server.pg[0].id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}

resource "azurerm_postgresql_flexible_server_configuration" "require_secure_transport" {
  count     = var.use_azure_postgres && (!var.postgres_require_secure_transport) ? 1 : 0
  name      = "require_secure_transport"
  server_id = azurerm_postgresql_flexible_server.pg[0].id
  value     = "off"
}

# Enable PostgreSQL extensions required by Dify
# Azure PostgreSQL requires extensions to be allow-listed via azure.extensions configuration
# Dify needs: vector (for embeddings), uuid-ossp (for UUID generation)
resource "azurerm_postgresql_flexible_server_configuration" "azure_extensions" {
  count     = var.use_azure_postgres ? 1 : 0
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.pg[0].id
  value     = "vector,uuid-ossp"
}

# Create extensions in the main Dify database
resource "null_resource" "create_extensions_dify" {
  count = var.use_azure_postgres ? 1 : 0

  depends_on = [
    azurerm_postgresql_flexible_server_configuration.azure_extensions,
    azurerm_postgresql_flexible_server_database.db
  ]

  triggers = {
    server_id   = azurerm_postgresql_flexible_server.pg[0].id
    database_id = azurerm_postgresql_flexible_server_database.db[0].id
  }

  provisioner "local-exec" {
    command = <<-EOT
      sleep 10
      PGPASSWORD='${replace(var.postgresql_password, "'", "\\'")}' psql \
        -h ${azurerm_postgresql_flexible_server.pg[0].fqdn} \
        -U ${var.postgresql_username} \
        -d ${var.postgresql_database} \
        -c "CREATE EXTENSION IF NOT EXISTS vector; CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";" \
        2>&1 || true
    EOT
  }
}

# Create extensions in the plugin daemon database
resource "null_resource" "create_extensions_plugin" {
  count = var.use_azure_postgres ? 1 : 0

  depends_on = [
    azurerm_postgresql_flexible_server_configuration.azure_extensions,
    azurerm_postgresql_flexible_server_database.plugin_db
  ]

  triggers = {
    server_id   = azurerm_postgresql_flexible_server.pg[0].id
    database_id = azurerm_postgresql_flexible_server_database.plugin_db[0].id
  }

  provisioner "local-exec" {
    command = <<-EOT
      sleep 10
      PGPASSWORD='${replace(var.postgresql_password, "'", "\\'")}' psql \
        -h ${azurerm_postgresql_flexible_server.pg[0].fqdn} \
        -U ${var.postgresql_username} \
        -d ${var.plugin_database_name} \
        -c "CREATE EXTENSION IF NOT EXISTS vector; CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";" \
        2>&1 || true
    EOT
  }
}

# ============================================================================
# END OF INFRASTRUCTURE RESOURCES
# Kubernetes applications are deployed via Helm (see deploy.sh and helm/dify/)
# All Kubernetes/Helm resources have been removed - they're managed by Helm directly
# ============================================================================

