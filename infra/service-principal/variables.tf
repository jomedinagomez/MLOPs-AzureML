# ===========================================
# SERVICE PRINCIPAL CONFIGURATION VARIABLES
# ===========================================

variable "service_principal_secret_expiry_hours" {
  description = "Number of hours until the service principal secret expires (default: 2 years = 17520 hours)"
  type        = number
  default     = 17520 # 2 years

  validation {
    condition     = var.service_principal_secret_expiry_hours > 0 && var.service_principal_secret_expiry_hours <= 87600 # Max 10 years
    error_message = "Service principal secret expiry must be between 1 hour and 87600 hours (10 years)."
  }
}

# ===========================================
# DEVELOPMENT ENVIRONMENT RESOURCE GROUPS
# ===========================================

variable "dev_vnet_resource_group_name" {
  description = "The name of the development VNet resource group"
  type        = string
  default     = "rg-aml-vnet-dev-cc01"
}

variable "dev_workspace_resource_group_name" {
  description = "The name of the development workspace resource group"
  type        = string
  default     = "rg-aml-workspace-dev-cc01"
}

variable "dev_registry_resource_group_name" {
  description = "The name of the development registry resource group"
  type        = string
  default     = "rg-aml-registry-dev-cc01"
}

# ===========================================
# PRODUCTION ENVIRONMENT RESOURCE GROUPS
# ===========================================

variable "prod_vnet_resource_group_name" {
  description = "The name of the production VNet resource group"
  type        = string
  default     = "rg-aml-vnet-prod-cc01"
}

variable "prod_workspace_resource_group_name" {
  description = "The name of the production workspace resource group"
  type        = string
  default     = "rg-aml-workspace-prod-cc01"
}

variable "prod_registry_resource_group_name" {
  description = "The name of the production registry resource group"
  type        = string
  default     = "rg-aml-registry-prod-cc01"
}
