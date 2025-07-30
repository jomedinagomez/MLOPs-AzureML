
variable "purpose" {
  description = "Environment identifier (e.g., 'dev', 'prod', 'test')"
  type        = string
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
}

variable "location_code" {
  description = "Short code for the region (e.g., 'we' for West Europe)"
  type        = string
}

variable "random_string" {
  description = "Unique string for resource naming"
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

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
}

variable "log_analytics_retention_days" {
  description = "Retention period in days for Log Analytics workspace"
  type        = number
  default     = 30
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "enable_auto_purge" {
  description = "Enable automatic purging of Log Analytics workspace on destroy (useful for dev/test environments)"
  type        = bool
  default     = false
  validation {
    condition     = var.enable_auto_purge == true || var.enable_auto_purge == false
    error_message = "Enable auto purge must be true or false."
  }
}