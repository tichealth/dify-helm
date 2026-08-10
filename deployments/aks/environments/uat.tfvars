# UAT - production-like services with development-sized compute.
# This replaces the former test profile. Secrets are supplied through the
# GitHub Environment named `uat` (or local TF_VAR_* variables).

project_name = "dify-uat"
location     = "australiaeast"

# No UAT resource group currently exists, so Terraform creates and owns one.
resource_group_name = ""

# AKS - intentionally small and stable: one on-demand node, no Spot pool.
# kubernetes_version is applied only when the cluster is first created; ongoing
# upgrades are manual via `az aks upgrade` (see UPGRADE_KUBERNETES.md).
node_count            = 1
vm_size               = "Standard_D2s_v5"
kubernetes_version    = "1.35.6"
enable_spot_node_pool = false

# The account/key are supplied separately; this name is retained for future
# object-storage wiring. Current application persistence uses AKS PVCs.
azure_blob_container_name = "difydata"

dify_init_password = ""

# PostgreSQL - same managed service type as prod, with dev-sized capacity.
#
# VNet-injected and private, matching Dev. The earlier public + allow-all
# firewall left only the difyadmin password between the internet and the data,
# which is not acceptable once the Dev restore lands real user content here.
# AKS reaches the server through the private DNS zone link and the VNet peering
# the module creates; coredns-custom.yaml forwards postgres.database.azure.com
# to Azure DNS so the privatelink name resolves inside the cluster.
#
# 10.2.0.0/16 avoids Dev's 10.1.0.0/16 and every AKS node VNet, which all sit in
# 10.224.0.0/12. Note that switching a Flexible Server between public and
# VNet-injected forces replacement — this is only cheap while UAT is empty.
use_azure_postgres                 = true
create_vnet_for_postgres           = true
vnet_address_space                 = ["10.2.0.0/16"]
postgres_subnet_address_prefixes   = ["10.2.1.0/24"]
management_subnet_address_prefixes = ["10.2.2.0/24"]
postgresql_username                = "difyadmin"
postgresql_database                = "dify"
postgres_version                   = "16"
postgres_sku_name                  = "B_Standard_B1ms"
postgres_storage_mb                = 32768
postgres_storage_tier              = "P4"
postgres_backup_retention_days     = 14
postgres_public_access             = false
postgres_open_firewall_all         = false
postgres_require_secure_transport  = true
postgres_max_connections           = 200

# deploy.sh consumes qdrant_chart_version for the UAT Qdrant release.
redis_chart_version  = "19.6.2"
qdrant_chart_version = "1.16.3"

tags = {
  env     = "uat"
  project = "dify"
  managed = "terraform"
}
