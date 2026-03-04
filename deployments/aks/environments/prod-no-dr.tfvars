# Production - No DR
# No read replicas or multi-region; single PostgreSQL, single region.
#
# Secrets (passwords, keys) are NOT in this file. Set them via:
# - GitHub Actions: workflow passes TF_VAR_* from GitHub Secrets.
# - Local runs: copy to ../terraform.tfvars and add the secret variables there, or export TF_VAR_* in the shell.

project_name = "dify-prod"
location     = "australiaeast"

resource_group_name = "rg-cme-prod"

# AKS
node_count         = 3
vm_size            = "Standard_D4s_v5"
enable_spot_node_pool = false

# Azure Blob Storage (secrets via TF_VAR_* from GitHub Secrets in CI)
azure_blob_container_name = "difydata"

# Dify (dify_secret_key via TF_VAR_* in CI)
dify_init_password = ""

# PostgreSQL - Azure Flexible Server (single instance, no DR) (postgresql_password via TF_VAR_* in CI)
use_azure_postgres = true
postgresql_username = "difyadmin"
postgresql_database = "dify"
postgres_version   = "16"
postgres_sku_name  = "GP_Standard_D2ds_v5"
postgres_storage_mb = 131072  # 128GB
postgres_public_access = true
postgres_open_firewall_all = true   # Allow all so AKS/CI can reach Postgres
postgres_require_secure_transport = true

# Redis (redis_password via TF_VAR_* in CI)
redis_chart_version = "19.6.2"

# Qdrant (qdrant_api_key via TF_VAR_* in CI)
qdrant_chart_version = "1.16.3"

tags = {
  env     = "prod"
  project = "dify"
  managed = "terraform"
}
