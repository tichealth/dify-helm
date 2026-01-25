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

# Azure Database for PostgreSQL Flexible (optional, when use_azure_postgres = true)
locals {
  pg_server_name = var.postgresql_server_name != "" ? var.postgresql_server_name : "${local.name_prefix}-pg-${random_id.suffix.hex}"
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
  public_network_access_enabled = var.postgres_public_access

  tags = merge(var.tags, { component = "postgres" })

  # Ignore zone changes to prevent Terraform from trying to modify it
  # Zone can be null in state but "1" in Azure, which causes update errors
  lifecycle {
    ignore_changes = [zone]
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

# ============================================================================
# END OF INFRASTRUCTURE RESOURCES
# Kubernetes applications are deployed via Helm (see deploy.sh and helm/dify/)
# All Kubernetes/Helm resources have been removed - they're managed by Helm directly
# ============================================================================

