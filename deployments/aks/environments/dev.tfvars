# Development - aligned with live remote state (dify-rg-9764, private Postgres).
# Secrets via TF_VAR_* in CI (GitHub Environment secrets), not in this file.
# See deployments/aks/terraform.tfvars.dev and GITHUB_ACTIONS_SECRETS.md.

project_name        = "dify"
location            = "australiaeast"
resource_group_name = "" # terraform-managed RG: dify-rg-9764

# AKS - vm_size must match the live node pool (avoid replace-on-apply)
node_count            = 1
vm_size               = "Standard_D2s_v5"
enable_spot_node_pool = false

# Dify blob container name (account/key from TF_VAR_* in CI)
azure_blob_container_name = "difydata"

dify_init_password = ""

# PostgreSQL - private VNet (same as terraform.tfvars.dev)
use_azure_postgres  = true
postgresql_username = "difyadmin"
postgresql_database = "dify"
postgres_version    = "16"
postgres_sku_name   = "B_Standard_B1ms"
postgres_storage_mb = 32768
postgres_storage_tier = "P4"

create_vnet_for_postgres           = true
vnet_address_space                 = ["10.1.0.0/16"]
postgres_subnet_address_prefixes     = ["10.1.1.0/24"]
management_subnet_address_prefixes = ["10.1.2.0/24"]

# When VNet is enabled, postgres_public_access is ignored (server stays private)
postgres_open_firewall_all        = false
postgres_require_secure_transport = false

redis_chart_version  = "19.6.2"
qdrant_chart_version = "1.16.3"

tags = {
  env     = "dev"
  project = "dify"
  managed = "terraform"
}
