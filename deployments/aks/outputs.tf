# Outputs for Hybrid Approach
# These outputs are used by the deployment script to get cluster information

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = local.rg_name
}

output "aks_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.fqdn
}

output "postgresql_fqdn" {
  description = "FQDN of the PostgreSQL server (if using Azure PostgreSQL). Returns private FQDN when VNet is enabled, public FQDN otherwise."
  value       = var.use_azure_postgres ? (
    var.create_vnet_for_postgres ? 
      "${azurerm_postgresql_flexible_server.pg[0].name}.privatelink.postgres.database.azure.com" :
      azurerm_postgresql_flexible_server.pg[0].fqdn
  ) : "N/A (using in-cluster PostgreSQL via Helm)"
}

output "postgresql_connection_string" {
  description = "PostgreSQL connection string (password not included)"
  value       = var.use_azure_postgres ? "postgresql://${var.postgresql_username}@${azurerm_postgresql_flexible_server.pg[0].fqdn}:5432/${var.postgresql_database}" : "N/A (using in-cluster PostgreSQL via Helm)"
  sensitive   = false
}

output "postgresql_read_replica_fqdns" {
  description = "FQDNs of PostgreSQL read replicas (if any) - Currently not implemented, returns empty list"
  value       = []  # Read replicas not implemented in current version
}

output "postgresql_private_fqdn" {
  description = "Private FQDN of PostgreSQL server (when using VNet integration). Use this from within the VNet."
  value       = var.use_azure_postgres && var.create_vnet_for_postgres ? "${azurerm_postgresql_flexible_server.pg[0].name}.privatelink.postgres.database.azure.com" : "N/A (public access or not using Azure PostgreSQL)"
}

output "vnet_id" {
  description = "ID of the VNet created for PostgreSQL (if create_vnet_for_postgres = true)"
  value       = var.create_vnet_for_postgres ? azurerm_virtual_network.postgres[0].id : "N/A"
}

output "postgres_subnet_id" {
  description = "ID of the delegated subnet for PostgreSQL (if create_vnet_for_postgres = true)"
  value       = var.create_vnet_for_postgres ? azurerm_subnet.postgres[0].id : "N/A"
}

output "management_subnet_id" {
  description = "ID of the management subnet for jumpbox VMs (if create_vnet_for_postgres = true and management_subnet_address_prefixes is set)"
  value       = var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? azurerm_subnet.management[0].id : "N/A"
}

output "management_subnet_name" {
  description = "Name of the management subnet (for reference when creating VMs)"
  value       = var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? azurerm_subnet.management[0].name : "N/A"
}
