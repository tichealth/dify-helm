# Outputs for Hybrid Approach (deploy.sh reads these)

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks.aks_cluster_name
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = local.rg_name
}

output "aks_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = module.aks.aks_fqdn
}

output "postgresql_fqdn" {
  description = "FQDN of the PostgreSQL server (if using Azure PostgreSQL). Returns private FQDN when VNet is enabled, public FQDN otherwise."
  value       = var.use_azure_postgres ? module.postgres.postgresql_fqdn : "N/A (using in-cluster PostgreSQL via Helm)"
}

output "postgresql_connection_string" {
  description = "PostgreSQL connection string (password not included)"
  value       = module.postgres.postgresql_connection_string
}

output "postgresql_read_replica_fqdns" {
  description = "FQDNs of PostgreSQL read replicas (if any) - Currently not implemented, returns empty list"
  value       = []
}

output "postgresql_private_fqdn" {
  description = "Private FQDN of PostgreSQL server (when using VNet integration). Use this from within the VNet."
  value       = module.postgres.postgresql_private_fqdn
}

output "vnet_id" {
  description = "ID of the VNet created for PostgreSQL (if create_vnet_for_postgres = true)"
  value       = var.create_vnet_for_postgres ? module.postgres.vnet_id : "N/A"
}

output "postgres_subnet_id" {
  description = "ID of the delegated subnet for PostgreSQL (if create_vnet_for_postgres = true)"
  value       = var.create_vnet_for_postgres ? module.postgres.postgres_subnet_id : "N/A"
}

output "management_subnet_id" {
  description = "ID of the management subnet for jumpbox VMs (if create_vnet_for_postgres = true and management_subnet_address_prefixes is set)"
  value       = var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? module.postgres.management_subnet_id : "N/A"
}

output "management_subnet_name" {
  description = "Name of the management subnet (for reference when creating VMs)"
  value       = var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? module.postgres.management_subnet_name : "N/A"
}
