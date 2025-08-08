# Variables for Single-Deployment Azure ML Platform

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  default     = "5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25"
}

variable "assign_user_roles" {
  description = "Whether to assign roles to the current user (data.azurerm_client_config.current.object_id)"
  type        = bool
  default     = true
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "canadacentral"
}

variable "location_code" {
  description = "Short code for the Azure region"
  type        = string
  default     = "cc"
}

variable "naming_suffix" {
  description = "Suffix for resource naming"
  type        = string
  # Updated from 01 to 02 for new deployment baseline
  default     = "02"
}

variable "tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    project     = "ml-platform"
    created_by  = "terraform"
    owner       = "ml-team"
  }
}

variable "prefix" {
  description = "Base prefix for all resource names to ensure uniqueness and consistency"
  type        = string
  default     = "aml"
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
    subnet             = "snet-aml"
    workspace          = "mlw"
    registry           = "mlr"
    storage            = "st"
    container_registry = "cr"
    key_vault          = "kv"
    log_analytics      = "log"
  }
}

variable "vpn_root_certificate_data" {
  description = "Base64 encoded root certificate data for P2S VPN authentication (without BEGIN/END certificate markers)"
  type        = string
  sensitive   = true
  default     = ""
  
  validation {
    condition     = var.vpn_root_certificate_data == "" || can(base64decode(var.vpn_root_certificate_data))
    error_message = "The vpn_root_certificate_data must be a valid base64 encoded string."
  }
}

# Azure AD (Entra ID) Point-to-Site VPN authentication
# Provide the Server Application (audience) App Registration ID created per
# https://learn.microsoft.com/azure/vpn-gateway/point-to-site-entra-gateway#create-the-azure-ad-apps
variable "azure_ad_p2s_audience" {
  description = "Application (client) ID of the Azure AD Server App used as audience for P2S AAD auth. Leave empty to disable AAD auth."
  type        = string
  default     = ""
  validation {
    condition     = !(var.azure_ad_p2s_audience != "" && var.vpn_root_certificate_data != "")
    error_message = "Provide either azure_ad_p2s_audience (AAD auth) OR vpn_root_certificate_data (certificate auth), not both."
  }
}

variable "azure_ad_p2s_tenant_id" {
  description = "Tenant ID to use for Azure AD P2S VPN auth. Defaults to current context tenant when null."
  type        = string
  default     = null
}

variable "user_object_id" {
  description = "The object ID of the user who will manage the Azure Machine Learning Workspace"
  type        = string
  default     = null
}

variable "shared_aml_dns_rg_name" {
  description = "Optional explicit name for the shared AML private DNS resource group (if null a name is generated)."
  type        = string
  default     = null
}
