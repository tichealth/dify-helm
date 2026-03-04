variable "project_name" {
  description = "Short name used as a prefix for resource naming."
  type        = string
}

variable "location" {
  description = "Azure location, e.g., eastus, westeurope"
  type        = string
}

variable "azure_subscription_id" {
  type        = string
  description = "Azure subscription ID"
  default     = "cce1d8e5-9a56-4bb4-ad7d-9c17aaa74482"
}

variable "node_count" {
  description = "AKS default node pool count"
  type        = number
  default     = 3
}

variable "vm_size" {
  description = "AKS node VM size"
  type        = string
  default     = "Standard_D4s_v5"
}

# Optional Spot node pool (recommended for non-prod)
variable "enable_spot_node_pool" {
  description = "Whether to create a Spot node pool (test/dev)."
  type        = bool
  default     = false
}

variable "spot_node_pool_name" {
  description = "Spot node pool name (lowercase, <=12 chars recommended)."
  type        = string
  default     = "spot"
}

variable "spot_vm_size" {
  description = "VM size for Spot node pool"
  type        = string
  default     = "Standard_D4s_v5"
}

variable "spot_node_count" {
  description = "Initial node count for Spot node pool"
  type        = number
  default     = 1
}

variable "spot_max_price" {
  description = "Max price for Spot instances. Use -1 for on-demand price cap."
  type        = number
  default     = -1
}

variable "resource_group_name" {
  description = "Optional: use an existing RG name. If empty, one will be created."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags applied to resources"
  type        = map(string)
  default     = {}
}

# Storage: Azure Blob (for Dify storage; deploy.sh/tfvars single source – not used in main.tf)
variable "azure_blob_account_name" {
  type        = string
  description = "Azure Storage account name for Blob"
}

variable "azure_blob_account_key" {
  type        = string
  description = "Azure Storage account key"
  sensitive   = true
}

variable "azure_blob_container_name" {
  type        = string
  description = "Azure Blob container name"
}

variable "azure_blob_account_url" {
  type        = string
  description = "Azure Blob account URL, e.g., https://<acct>.blob.core.windows.net"
}

# Optional admin init
variable "dify_secret_key" {
  description = "Dify SECRET_KEY for signing/encryption"
  type        = string
  sensitive   = true
}

variable "dify_init_password" {
  description = "Optional initial admin password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "plugin_database_name" {
  description = "Plugin daemon database name"
  type        = string
  default     = "dify_plugin"
}

# Postgres config
variable "postgresql_username" {
  type        = string
  default     = "postgres"
}

variable "postgresql_password" {
  type        = string
  sensitive   = true
}

variable "postgresql_database" {
  type        = string
  default     = "dify"
}

# Use Azure Database for PostgreSQL Flexible instead of in-cluster Postgres
variable "use_azure_postgres" {
  description = "If true, provision Azure Database for PostgreSQL Flexible and wire Dify to it. Disables Helm Postgres."
  type        = bool
  default     = false
}

variable "postgresql_server_name" {
  description = "Azure PostgreSQL flexible server name. If empty, a name will be derived from project."
  type        = string
  default     = ""
}

variable "postgres_version" {
  description = "Azure PostgreSQL engine version"
  type        = string
  default     = "16"
}

variable "postgres_sku_name" {
  description = "Azure PostgreSQL SKU, e.g., B_Standard_B1ms, GP_Standard_D2ds_v5, MO_Standard_E2ds_v5"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_storage_mb" {
  description = "Azure PostgreSQL storage in MB"
  type        = number
  default     = 32768
}

variable "postgres_storage_tier" {
  description = "Azure PostgreSQL storage performance tier (e.g. P4, P6, P10, P15, P20, P30). Leave null for Azure default based on storage_mb."
  type        = string
  default     = null
}

variable "postgres_public_access" {
  description = "Enable public network access on Azure Postgres (simpler). For private access, set false and configure VNet/PE."
  type        = bool
  default     = true
}

variable "postgres_require_secure_transport" {
  description = "If true, keep SSL required on Azure Postgres. If false, we will turn it off (not recommended)."
  type        = bool
  default     = true
}

variable "postgres_open_firewall_all" {
  description = "If true (dev only), open Azure Postgres firewall to all IPv4. Set to false and add specific rules for production."
  type        = bool
  default     = true
}

# VNet configuration for PostgreSQL private access
variable "create_vnet_for_postgres" {
  description = "Create VNet and delegated subnet for PostgreSQL private access. When true, postgres_public_access is automatically set to false."
  type        = bool
  default     = false
}

variable "vnet_address_space" {
  description = "Address space for the VNet (CIDR notation)"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "postgres_subnet_address_prefixes" {
  description = "Address prefixes for PostgreSQL delegated subnet (CIDR notation)"
  type        = list(string)
  default     = ["10.1.1.0/24"]
}

variable "management_subnet_address_prefixes" {
  description = "Address prefixes for management/jumpbox subnet (for VMs to access PostgreSQL). Leave empty to skip creating this subnet."
  type        = list(string)
  default     = ["10.1.2.0/24"]
}

# Redis config
variable "redis_chart_version" {
  type        = string
  default     = "18.1.2"
  description = "Redis Helm chart version (referenced in tfvars; deploy/Helm use values.yaml)"
}

variable "redis_password" {
  type        = string
  sensitive   = true
}

# Qdrant config
variable "qdrant_chart_version" {
  type        = string
  default     = "1.16.3"
  description = "Qdrant Helm chart version"
}

variable "qdrant_api_key" {
  type        = string
  sensitive   = true
}
