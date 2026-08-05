variable "name_prefix" {
  description = "Prefix for resource names (e.g. project name)"
  type        = string
}

variable "suffix_hex" {
  description = "Short hex suffix for uniqueness (from random_id.suffix.hex)"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "location" {
  description = "Azure location"
  type        = string
}

variable "node_count" {
  type        = number
  default     = 3
  description = "Default node pool count"
}

variable "vm_size" {
  type        = string
  default     = "Standard_D4s_v5"
  description = "Node VM size"
}

variable "kubernetes_version" {
  type        = string
  default     = null
  description = <<-EOT
    Target Kubernetes minor (e.g. "1.35") or exact patch (e.g. "1.35.9").
    Applied only at cluster creation; ongoing upgrades are manual via `az aks upgrade`
    (see UPGRADE_KUBERNETES.md). Terraform ignores post-create version changes
    so out-of-band upgrades never cause drift.
  EOT
}

variable "enable_spot_node_pool" {
  type        = bool
  default     = false
  description = "Create optional Spot node pool"
}

variable "spot_node_pool_name" {
  type        = string
  default     = "spot"
  description = "Spot node pool name"
}

variable "spot_vm_size" {
  type        = string
  default     = "Standard_D4s_v5"
  description = "Spot pool VM size"
}

variable "spot_node_count" {
  type        = number
  default     = 1
  description = "Spot pool node count"
}

variable "spot_max_price" {
  type        = number
  default     = -1
  description = "Spot max price (-1 = on-demand cap)"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags"
}
