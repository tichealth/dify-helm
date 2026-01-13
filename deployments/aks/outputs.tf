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
  description = "FQDN of the PostgreSQL server (if using Azure PostgreSQL)"
  value       = var.use_azure_postgres ? azurerm_postgresql_flexible_server.pg[0].fqdn : "N/A (using in-cluster PostgreSQL via Helm)"
}

output "postgresql_connection_string" {
  description = "PostgreSQL connection string (password not included)"
  value       = var.use_azure_postgres ? "postgresql://${var.postgresql_username}@${azurerm_postgresql_flexible_server.pg[0].fqdn}:5432/${var.postgresql_database}" : "N/A (using in-cluster PostgreSQL via Helm)"
  sensitive   = false
}
