# Terraform modules

- **aks** – AKS cluster, optional spot node pool, DNS-ready wait, control-plane sleep. Outputs cluster name, FQDN, node resource group (for Postgres VNet peering).
- **postgres** – Optional VNet (delegated subnet, management subnet, NSG), Private DNS zone, VNet peering to AKS, Azure PostgreSQL Flexible Server, databases, firewall, extensions. Depends on AKS when `create_vnet_for_postgres` is true (needs AKS node resource group for peering).

State was migrated from the previous single-root layout using root `moved` blocks so existing resources were not destroyed or recreated.
