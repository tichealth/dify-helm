variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"
}

variable "suffix_hex" {
  type        = string
  description = "Short hex suffix (from random_id.suffix.hex)"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
}

variable "location" {
  type        = string
  description = "Azure location"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags"
}

variable "use_azure_postgres" {
  type        = bool
  default     = false
  description = "Provision Azure PostgreSQL Flexible Server"
}

variable "create_vnet_for_postgres" {
  type        = bool
  default     = false
  description = "Create VNet and private access for Postgres"
}

variable "aks_node_resource_group" {
  type        = string
  default     = null
  description = "AKS node resource group name (for VNet peering when create_vnet_for_postgres = true)"
}

variable "vnet_address_space" {
  type        = list(string)
  default     = ["10.1.0.0/16"]
  description = "VNet address space"
}

variable "postgres_subnet_address_prefixes" {
  type        = list(string)
  default     = ["10.1.1.0/24"]
  description = "PostgreSQL delegated subnet prefixes"
}

variable "management_subnet_address_prefixes" {
  type        = list(string)
  default     = ["10.1.2.0/24"]
  description = "Management subnet prefixes (empty to skip)"
}

variable "postgresql_server_name" {
  type        = string
  default     = ""
  description = "PostgreSQL server name (empty = derived from name_prefix)"
}

variable "postgres_version" {
  type        = string
  default     = "16"
  description = "PostgreSQL engine version"
}

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

variable "plugin_database_name" {
  type        = string
  default     = "dify_plugin"
}

variable "postgres_sku_name" {
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_storage_mb" {
  type        = number
  default     = 32768
}

variable "postgres_storage_tier" {
  type        = string
  default     = null
  description = "Storage tier (e.g. P4, P15, P30); null = Azure default"
}

variable "postgres_public_access" {
  type        = bool
  default     = true
  description = "Public network access (ignored when create_vnet_for_postgres = true)"
}

variable "postgres_require_secure_transport" {
  type        = bool
  default     = true
}

variable "postgres_open_firewall_all" {
  type        = bool
  default     = true
  description = "Allow 0.0.0.0-255.255.255.255 when public access"
}
