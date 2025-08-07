# Environment Module Variables
# These variables define the interface for each environment deployment

variable "prefix" {
  description = "Base prefix for all resource names to ensure uniqueness and consistency"
  type        = string
}

variable "resource_prefixes" {
  description = "Specific prefixes for each resource type"
  type = object({
    vnet               = string
    subnet             = string
    workspace          = string
    registry           = string
    storage            = string
    container_registry = string
    key_vault          = string
    log_analytics      = string
  })
}

variable "purpose" {
  description = "Environment identifier (e.g., 'dev', 'prod', 'test')"
  type        = string
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
}

variable "location_code" {
  description = "Short code for the region (e.g., 'cc' for Canada Central)"
  type        = string
}

variable "random_string" {
  description = "Unique string for resource naming (must be '01' per deployment strategy)"
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the VNet (e.g., '10.1.0.0/16')"
  type        = string
}

variable "subnet_address_prefix" {
  description = "Address prefix for the subnet (e.g., '10.1.1.0/24')"
  type        = string
}

variable "tags" {
  description = "Map of tags to apply to resources"
  type        = map(string)
}

variable "enable_auto_purge" {
  description = "Enable automatic purging of Key Vault on destroy (useful for dev/test environments)"
  type        = bool
}

# Cross-environment RBAC configuration for asset promotion
variable "enable_cross_env_rbac" {
  description = "Enable cross-environment RBAC for asset promotion between dev and prod"
  type        = bool
  default     = false
}

variable "cross_env_registry_resource_group" {
  description = "Resource group name containing the other environment's registry (for cross-env RBAC)"
  type        = string
  default     = null
}

variable "cross_env_registry_name" {
  description = "Name of the other environment's registry (for cross-env RBAC)"
  type        = string
  default     = null
}

variable "cross_env_workspace_principal_id" {
  description = "Principal ID of the other environment's workspace system-managed identity (for cross-env RBAC)"
  type        = string
  default     = null
}
