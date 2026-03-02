# Test - single node, optional spot pool
# Secrets via TF_VAR_* (GitHub Secrets in CI, or local terraform.tfvars / env).
# See OPERATIONS.md and PROD_DEPLOY.md.

project_name = "dify-test"
location     = "australiaeast"

resource_group_name = "rg-cme-test"

# AKS - 1 node + optional spot pool
kubernetes_version    = null
node_count            = 1
vm_size               = "Standard_D2s_v5"
enable_spot_node_pool = true
spot_node_pool_name   = "spot"
spot_vm_size          = "Standard_D4s_v5"
spot_node_count       = 1
spot_max_price        = -1

# Azure Blob Storage (secrets via TF_VAR_* in CI)
azure_blob_container_name = "difydata"

dify_init_password = ""

# PostgreSQL
use_azure_postgres = true
postgresql_username = "difyadmin"
postgresql_database = "dify"
postgres_version   = "16"
postgres_sku_name  = "B_Standard_B1ms"
postgres_storage_mb = 32768
postgres_public_access = true
postgres_open_firewall_all = true
postgres_require_secure_transport = true

redis_chart_version = "19.6.2"
qdrant_chart_version = "1.16.3"

tags = {
  env     = "test"
  project = "dify"
  managed = "terraform"
}
