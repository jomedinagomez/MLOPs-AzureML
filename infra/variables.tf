# Terraform variable definitions for root orchestration
terraform {
  required_version = ">= 1.0"
}

variable "prefix" {
  description = "Base prefix for all resource names to ensure uniqueness and consistency"
  type        = string
  default     = "aml"

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.prefix))
    error_message = "Prefix must be between 2-8 characters, lowercase letters and numbers only."
  }
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
  default = {
    vnet               = "vnet-aml"
    subnet             = "subnet-aml"
    workspace          = "amlws"
    registry           = "amlreg"
    storage            = "amlst"
    container_registry = "amlacr"
    key_vault          = "amlkv"
    log_analytics      = "amllog"
  }
}

variable "purpose" {
  description = "Environment identifier (e.g., 'dev', 'prod', 'test')"
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.purpose))
    error_message = "Purpose must be between 2-8 characters, lowercase letters and numbers only."
  }
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "canadacentral"

  validation {
    condition = contains([
      "canadacentral", "canadaeast", "eastus", "eastus2", "westus", "westus2",
      "centralus", "northcentralus", "southcentralus", "westcentralus",
      "westeurope", "northeurope", "uksouth", "ukwest", "francecentral",
      "germanywestcentral", "switzerlandnorth", "norwayeast",
      "australiaeast", "australiasoutheast", "southeastasia", "eastasia",
      "japaneast", "japanwest", "koreacentral", "koreasouth",
      "southafricanorth", "brazilsouth", "uaenorth", "centralindia", "southindia"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "location_code" {
  description = "Short code for the region (e.g., 'cc' for Canada Central)"
  type        = string
  default     = "cc"

  validation {
    condition     = can(regex("^[a-z]{2,4}$", var.location_code))
    error_message = "Location code must be between 2-4 characters, lowercase letters only."
  }
}

variable "random_string" {
  description = "Unique string for resource naming (must be '01' per deployment strategy)"
  type        = string
  default     = "01"

  validation {
    condition     = var.random_string == "01"
    error_message = "DEPLOYMENT STRATEGY REQUIREMENT: random_string must be '01' for both dev and prod environments."
  }

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.random_string))
    error_message = "Random string must be between 2-8 characters, lowercase letters and numbers only."
  }
}

variable "vnet_address_space" {
  description = "Address space for the VNet (e.g., '10.1.0.0/16')"
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition     = can(cidrhost(var.vnet_address_space, 0))
    error_message = "VNet address space must be a valid CIDR block."
  }
}

variable "subnet_address_prefix" {
  description = "Address prefix for the subnet (e.g., '10.1.1.0/24')"
  type        = string
  default     = "10.1.1.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_address_prefix, 0))
    error_message = "Subnet address prefix must be a valid CIDR block."
  }
}

variable "tags" {
  description = "Map of tags to apply to resources"
  type        = map(string)
  default = {
    environment = "dev"
    project     = "ml-platform"
    created_by  = "terraform"
  }

  validation {
    condition     = alltrue([for k, v in var.tags : can(regex("^[a-zA-Z0-9-_]+$", k)) && can(regex("^[a-zA-Z0-9-_\\s]+$", v))])
    error_message = "Tag keys and values must contain only alphanumeric characters, hyphens, underscores, and spaces."
  }
}

variable "enable_auto_purge" {
  description = "Enable automatic purging of Key Vault on destroy (useful for dev/test environments)"
  type        = bool
  default     = false

  validation {
    condition     = var.enable_auto_purge == true || var.enable_auto_purge == false
    error_message = "Enable auto purge must be true or false."
  }
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

# Service Principal Configuration
variable "service_principal_secret_expiry_hours" {
  description = "Hours until the service principal secret expires (default: 17520 = 2 years)"
  type        = number
  default     = 17520 # 2 years

  validation {
    condition     = var.service_principal_secret_expiry_hours > 0 && var.service_principal_secret_expiry_hours <= 87600 # Max 10 years
    error_message = "Service principal secret expiry must be between 1 hour and 87600 hours (10 years)."
  }
}
