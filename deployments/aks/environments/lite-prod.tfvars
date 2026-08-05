# Lite production - single node, lower cost.
# Use when you don't need active-active nodes; one node is enough.
# See PROD_DEPLOY.md for cost and scalability notes; INFRACOST.md for pricing.
#
# Secrets (passwords, keys) are NOT in this file. Set them via:
# - GitHub Actions: workflow passes TF_VAR_* from GitHub Secrets.
# - Local runs: copy to ../terraform.tfvars and add the secret variables there, or export TF_VAR_* in the shell.

project_name = "dify-prod-lite"
location     = "australiaeast"

resource_group_name = "rg-cme-prod"

# AKS - single node (no multi-node HA).
# kubernetes_version is applied only at cluster creation; Terraform ignores
# post-create drift, so manual `az aks upgrade` hops are the source of truth
# (see AKS_KUBERNETES_UPGRADE.md). Bump this pin after Prod is manually upgraded.
node_count            = 1
vm_size               = "Standard_D4s_v5" # or Standard_D2s_v5 for lower cost
kubernetes_version    = "1.35"
enable_spot_node_pool = false

# Azure Blob Storage (secrets via TF_VAR_* from GitHub Secrets in CI)
azure_blob_container_name = "difydata"

# Dify (dify_secret_key via TF_VAR_* in CI)
dify_init_password = ""

# PostgreSQL - smaller SKU and storage for cost savings (postgresql_password via TF_VAR_* in CI)
use_azure_postgres                = true
postgresql_username               = "difyadmin"
postgresql_database               = "dify"
postgres_version                  = "16"
postgres_sku_name                 = "B_Standard_B1ms" # Burstable, 1 vCore, ~32 GB included
postgres_storage_mb               = 32768             # 32 GB
postgres_public_access            = true
postgres_open_firewall_all        = true  # Allow all IPs so AKS pods and CI runner can reach Postgres (same as dev)
postgres_require_secure_transport = false # Allow non-SSL for now; set true + add SSL env in values when enabling SSL
postgres_max_connections          = 200   # Default 50 too low: Dify (~26) + Phoenix (~5) + Azure system (~10) exhausts slots. Matches dev.

# Redis (redis_password via TF_VAR_* in CI)
redis_chart_version = "19.6.2"

# Qdrant (qdrant_api_key via TF_VAR_* in CI)
qdrant_chart_version = "1.16.3"

tags = {
  env     = "prod-lite"
  project = "dify"
  managed = "terraform"
}
