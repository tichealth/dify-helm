output "aks_cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_fqdn" {
  description = "AKS API FQDN"
  value       = azurerm_kubernetes_cluster.aks.fqdn
}

output "aks_id" {
  description = "AKS cluster ID"
  value       = azurerm_kubernetes_cluster.aks.id
}

output "node_resource_group" {
  description = "AKS node resource group name (for VNet peering when using private Postgres)"
  value       = azurerm_kubernetes_cluster.aks.node_resource_group
}
