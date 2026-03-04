output "postgresql_fqdn" {
  description = "PostgreSQL FQDN (private when VNet, public otherwise)"
  value       = var.use_azure_postgres ? (
    var.create_vnet_for_postgres ?
      "${azurerm_postgresql_flexible_server.pg[0].name}.privatelink.postgres.database.azure.com" :
      azurerm_postgresql_flexible_server.pg[0].fqdn
  ) : "N/A"
}

output "postgresql_connection_string" {
  description = "PostgreSQL connection string (no password)"
  value       = var.use_azure_postgres ? "postgresql://${var.postgresql_username}@${azurerm_postgresql_flexible_server.pg[0].fqdn}:5432/${var.postgresql_database}" : "N/A"
}

output "postgresql_private_fqdn" {
  description = "Private FQDN when VNet enabled"
  value       = var.use_azure_postgres && var.create_vnet_for_postgres ? "${azurerm_postgresql_flexible_server.pg[0].name}.privatelink.postgres.database.azure.com" : "N/A"
}

output "vnet_id" {
  description = "VNet ID when create_vnet_for_postgres = true"
  value       = var.create_vnet_for_postgres ? azurerm_virtual_network.postgres[0].id : "N/A"
}

output "postgres_subnet_id" {
  description = "PostgreSQL delegated subnet ID"
  value       = var.create_vnet_for_postgres ? azurerm_subnet.postgres[0].id : "N/A"
}

output "management_subnet_id" {
  description = "Management subnet ID"
  value       = var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? azurerm_subnet.management[0].id : "N/A"
}

output "management_subnet_name" {
  description = "Management subnet name"
  value       = var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? azurerm_subnet.management[0].name : "N/A"
}
