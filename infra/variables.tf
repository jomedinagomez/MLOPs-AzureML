# Terraform variable definitions for root orchestration
terraform {
  required_version = ">= 1.0"
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
  description = "Unique string for resource naming"
  type        = string
  default     = "001"
  
  validation {
    condition     = can(regex("^[a-z0-9]{3,8}$", var.random_string))
    error_message = "Random string must be between 3-8 characters, lowercase letters and numbers only."
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
