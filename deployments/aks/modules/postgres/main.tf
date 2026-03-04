locals {
  pg_server_name         = var.postgresql_server_name != "" ? var.postgresql_server_name : "${var.name_prefix}-pg-${var.suffix_hex}"
  postgres_public_access = var.create_vnet_for_postgres ? false : var.postgres_public_access
}

# VNet for PostgreSQL private access (optional)
resource "azurerm_virtual_network" "postgres" {
  count               = var.use_azure_postgres && var.create_vnet_for_postgres ? 1 : 0
  name                = "${var.name_prefix}-vnet-${var.suffix_hex}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space
  tags                = merge(var.tags, { component = "network" })
}

resource "azurerm_subnet" "postgres" {
  count                = var.use_azure_postgres && var.create_vnet_for_postgres ? 1 : 0
  name                 = "${var.name_prefix}-postgres-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.postgres[0].name
  address_prefixes     = var.postgres_subnet_address_prefixes

  delegation {
    name = "postgres-delegation"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "management" {
  count                = var.use_azure_postgres && var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? 1 : 0
  name                 = "${var.name_prefix}-management-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.postgres[0].name
  address_prefixes     = var.management_subnet_address_prefixes
}

resource "azurerm_network_security_group" "management" {
  count               = var.use_azure_postgres && var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? 1 : 0
  name                = "${var.name_prefix}-management-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = merge(var.tags, { component = "network", purpose = "management" })
}

resource "azurerm_network_security_rule" "management_ssh" {
  count                       = var.use_azure_postgres && var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? 1 : 0
  name                        = "AllowSSH"
  priority                    = 1000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range     = "22"
  source_address_prefix      = "Internet"
  destination_address_prefix = "*"
  resource_group_name        = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.management[0].name
}

resource "azurerm_network_security_rule" "management_rdp" {
  count                       = var.use_azure_postgres && var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? 1 : 0
  name                        = "AllowRDP"
  priority                    = 1001
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range     = "3389"
  source_address_prefix      = "Internet"
  destination_address_prefix = "*"
  resource_group_name        = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.management[0].name
}

resource "azurerm_network_security_rule" "management_to_postgres" {
  count                       = var.use_azure_postgres && var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? 1 : 0
  name                        = "AllowPostgreSQL"
  priority                    = 1002
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range     = "5432"
  source_address_prefix      = length(var.management_subnet_address_prefixes) > 0 ? var.management_subnet_address_prefixes[0] : "*"
  destination_address_prefix = length(var.postgres_subnet_address_prefixes) > 0 ? var.postgres_subnet_address_prefixes[0] : "*"
  resource_group_name        = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.management[0].name
}

resource "azurerm_subnet_network_security_group_association" "management" {
  count                     = var.use_azure_postgres && var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? 1 : 0
  subnet_id                 = azurerm_subnet.management[0].id
  network_security_group_id = azurerm_network_security_group.management[0].id
}

resource "azurerm_private_dns_zone" "postgres" {
  count               = var.use_azure_postgres && var.create_vnet_for_postgres ? 1 : 0
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = merge(var.tags, { component = "dns" })
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  count                 = var.use_azure_postgres && var.create_vnet_for_postgres ? 1 : 0
  name                  = "${var.name_prefix}-postgres-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.postgres[0].name
  virtual_network_id    = azurerm_virtual_network.postgres[0].id
  registration_enabled  = false
  tags                  = var.tags
}

data "azurerm_resource_group" "aks_node" {
  count = var.use_azure_postgres && var.create_vnet_for_postgres && var.aks_node_resource_group != null ? 1 : 0
  name  = var.aks_node_resource_group
}

data "azurerm_resources" "aks_vnets" {
  count               = var.use_azure_postgres && var.create_vnet_for_postgres && var.aks_node_resource_group != null ? 1 : 0
  resource_group_name = data.azurerm_resource_group.aks_node[0].name
  type                = "Microsoft.Network/virtualNetworks"
}

locals {
  aks_vnet_id   = try(data.azurerm_resources.aks_vnets[0].resources[0].id, null)
  aks_vnet_name = local.aks_vnet_id != null ? split("/", local.aks_vnet_id)[8] : null
}

resource "azurerm_private_dns_zone_virtual_network_link" "aks" {
  count                 = var.use_azure_postgres && var.create_vnet_for_postgres && local.aks_vnet_id != null ? 1 : 0
  name                  = "${var.name_prefix}-aks-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.postgres[0].name
  virtual_network_id    = local.aks_vnet_id
  registration_enabled  = false
  tags                  = var.tags

  depends_on = [data.azurerm_resources.aks_vnets]
}

resource "azurerm_virtual_network_peering" "postgres_to_aks" {
  count                     = var.use_azure_postgres && var.create_vnet_for_postgres && local.aks_vnet_id != null ? 1 : 0
  name                      = "${var.name_prefix}-postgres-to-aks"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = azurerm_virtual_network.postgres[0].name
  remote_virtual_network_id = local.aks_vnet_id
  allow_forwarded_traffic  = true
  allow_gateway_transit    = false
  use_remote_gateways      = false

  depends_on = [data.azurerm_resources.aks_vnets]
}

resource "azurerm_virtual_network_peering" "aks_to_postgres" {
  count                     = var.use_azure_postgres && var.create_vnet_for_postgres && local.aks_vnet_id != null ? 1 : 0
  name                      = "${var.name_prefix}-aks-to-postgres"
  resource_group_name       = data.azurerm_resource_group.aks_node[0].name
  virtual_network_name      = local.aks_vnet_name
  remote_virtual_network_id = azurerm_virtual_network.postgres[0].id
  allow_forwarded_traffic  = true
  allow_gateway_transit    = false
  use_remote_gateways      = false

  depends_on = [data.azurerm_resources.aks_vnets]
}

resource "azurerm_postgresql_flexible_server" "pg" {
  count                         = var.use_azure_postgres ? 1 : 0
  name                          = local.pg_server_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = var.postgres_version
  administrator_login           = var.postgresql_username
  administrator_password        = var.postgresql_password
  sku_name                      = var.postgres_sku_name
  storage_mb                    = var.postgres_storage_mb
  storage_tier                  = var.postgres_storage_tier
  public_network_access_enabled = local.postgres_public_access

  delegated_subnet_id = var.create_vnet_for_postgres ? azurerm_subnet.postgres[0].id : null
  private_dns_zone_id = var.create_vnet_for_postgres ? azurerm_private_dns_zone.postgres[0].id : null

  tags = merge(var.tags, { component = "postgres" })

  lifecycle {
    ignore_changes = [zone]
  }

  depends_on = [
    azurerm_subnet.postgres,
    azurerm_private_dns_zone.postgres
  ]
}

resource "time_sleep" "pg_private_dns_ready" {
  count = var.use_azure_postgres && var.create_vnet_for_postgres ? 1 : 0

  create_duration = "90s"
  depends_on      = [azurerm_postgresql_flexible_server.pg]
}

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
      RG='${replace(var.resource_group_name, "'", "'\"'\"'")}'
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

resource "azurerm_postgresql_flexible_server_database" "plugin_db" {
  count     = var.use_azure_postgres ? 1 : 0
  name      = var.plugin_database_name
  server_id = azurerm_postgresql_flexible_server.pg[0].id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "all" {
  count            = var.use_azure_postgres && local.postgres_public_access && var.postgres_open_firewall_all ? 1 : 0
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

resource "azurerm_postgresql_flexible_server_configuration" "azure_extensions" {
  count     = var.use_azure_postgres ? 1 : 0
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.pg[0].id
  value     = "vector,uuid-ossp"
}

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
