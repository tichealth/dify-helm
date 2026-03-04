# -----------------------------------------------------------------------------
# Root: shared identity and resource group; modules own AKS and PostgreSQL.
# Use "moved" blocks so existing state is migrated in-place (no destroy/recreate).
# -----------------------------------------------------------------------------

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
  rg_name     = coalesce(try(data.azurerm_resource_group.existing_rg[0].name, null), try(azurerm_resource_group.rg[0].name, null))
  rg_location = coalesce(try(data.azurerm_resource_group.existing_rg[0].location, null), try(azurerm_resource_group.rg[0].location, null))
}

# -----------------------------------------------------------------------------
# AKS module
# -----------------------------------------------------------------------------
module "aks" {
  source = "./modules/aks"

  name_prefix          = local.name_prefix
  suffix_hex           = random_id.suffix.hex
  resource_group_name  = local.rg_name
  location             = local.rg_location
  node_count           = var.node_count
  vm_size              = var.vm_size
  enable_spot_node_pool = var.enable_spot_node_pool
  spot_node_pool_name  = var.spot_node_pool_name
  spot_vm_size         = var.spot_vm_size
  spot_node_count      = var.spot_node_count
  spot_max_price       = var.spot_max_price
  tags                 = var.tags
}

# -----------------------------------------------------------------------------
# PostgreSQL module (optional VNet + Flexible Server; depends on AKS when peering)
# -----------------------------------------------------------------------------
module "postgres" {
  source = "./modules/postgres"

  name_prefix   = local.name_prefix
  suffix_hex    = random_id.suffix.hex
  resource_group_name = local.rg_name
  location      = local.rg_location
  tags          = var.tags

  use_azure_postgres    = var.use_azure_postgres
  create_vnet_for_postgres = var.create_vnet_for_postgres
  aks_node_resource_group = (var.use_azure_postgres && var.create_vnet_for_postgres) ? module.aks.node_resource_group : null

  vnet_address_space               = var.vnet_address_space
  postgres_subnet_address_prefixes  = var.postgres_subnet_address_prefixes
  management_subnet_address_prefixes = var.management_subnet_address_prefixes

  postgresql_server_name = var.postgresql_server_name
  postgres_version       = var.postgres_version
  postgresql_username    = var.postgresql_username
  postgresql_password    = var.postgresql_password
  postgresql_database    = var.postgresql_database
  plugin_database_name   = var.plugin_database_name
  postgres_sku_name      = var.postgres_sku_name
  postgres_storage_mb     = var.postgres_storage_mb
  postgres_storage_tier   = var.postgres_storage_tier
  postgres_public_access  = var.postgres_public_access
  postgres_require_secure_transport = var.postgres_require_secure_transport
  postgres_open_firewall_all = var.postgres_open_firewall_all
}

# -----------------------------------------------------------------------------
# State migration: existing resources moved into modules (no destroy/recreate)
# -----------------------------------------------------------------------------
moved {
  from = azurerm_kubernetes_cluster.aks
  to   = module.aks.azurerm_kubernetes_cluster.aks
}

moved {
  from = azurerm_kubernetes_cluster_node_pool.spot
  to   = module.aks.azurerm_kubernetes_cluster_node_pool.spot
}

moved {
  from = null_resource.aks_dns_ready
  to   = module.aks.null_resource.aks_dns_ready
}

moved {
  from = time_sleep.aks_control_plane_ready
  to   = module.aks.time_sleep.aks_control_plane_ready
}

moved {
  from = azurerm_virtual_network.postgres
  to   = module.postgres.azurerm_virtual_network.postgres
}

moved {
  from = azurerm_subnet.postgres
  to   = module.postgres.azurerm_subnet.postgres
}

moved {
  from = azurerm_subnet.management
  to   = module.postgres.azurerm_subnet.management
}

moved {
  from = azurerm_network_security_group.management
  to   = module.postgres.azurerm_network_security_group.management
}

moved {
  from = azurerm_network_security_rule.management_ssh
  to   = module.postgres.azurerm_network_security_rule.management_ssh
}

moved {
  from = azurerm_network_security_rule.management_rdp
  to   = module.postgres.azurerm_network_security_rule.management_rdp
}

moved {
  from = azurerm_network_security_rule.management_to_postgres
  to   = module.postgres.azurerm_network_security_rule.management_to_postgres
}

moved {
  from = azurerm_subnet_network_security_group_association.management
  to   = module.postgres.azurerm_subnet_network_security_group_association.management
}

moved {
  from = azurerm_private_dns_zone.postgres
  to   = module.postgres.azurerm_private_dns_zone.postgres
}

moved {
  from = azurerm_private_dns_zone_virtual_network_link.postgres
  to   = module.postgres.azurerm_private_dns_zone_virtual_network_link.postgres
}

moved {
  from = azurerm_private_dns_zone_virtual_network_link.aks
  to   = module.postgres.azurerm_private_dns_zone_virtual_network_link.aks
}

moved {
  from = data.azurerm_resource_group.aks_node
  to   = module.postgres.data.azurerm_resource_group.aks_node
}

moved {
  from = data.azurerm_resources.aks_vnets
  to   = module.postgres.data.azurerm_resources.aks_vnets
}

moved {
  from = azurerm_virtual_network_peering.postgres_to_aks
  to   = module.postgres.azurerm_virtual_network_peering.postgres_to_aks
}

moved {
  from = azurerm_virtual_network_peering.aks_to_postgres
  to   = module.postgres.azurerm_virtual_network_peering.aks_to_postgres
}

moved {
  from = azurerm_postgresql_flexible_server.pg
  to   = module.postgres.azurerm_postgresql_flexible_server.pg
}

moved {
  from = time_sleep.pg_private_dns_ready
  to   = module.postgres.time_sleep.pg_private_dns_ready
}

moved {
  from = null_resource.create_pg_app_dns_record
  to   = module.postgres.null_resource.create_pg_app_dns_record
}

moved {
  from = azurerm_postgresql_flexible_server_database.db
  to   = module.postgres.azurerm_postgresql_flexible_server_database.db
}

moved {
  from = azurerm_postgresql_flexible_server_database.plugin_db
  to   = module.postgres.azurerm_postgresql_flexible_server_database.plugin_db
}

moved {
  from = azurerm_postgresql_flexible_server_firewall_rule.all
  to   = module.postgres.azurerm_postgresql_flexible_server_firewall_rule.all
}

moved {
  from = azurerm_postgresql_flexible_server_configuration.require_secure_transport
  to   = module.postgres.azurerm_postgresql_flexible_server_configuration.require_secure_transport
}

moved {
  from = azurerm_postgresql_flexible_server_configuration.azure_extensions
  to   = module.postgres.azurerm_postgresql_flexible_server_configuration.azure_extensions
}

moved {
  from = null_resource.create_extensions_dify
  to   = module.postgres.null_resource.create_extensions_dify
}

moved {
  from = null_resource.create_extensions_plugin
  to   = module.postgres.null_resource.create_extensions_plugin
}
