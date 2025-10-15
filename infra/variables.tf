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
  description = "Required deterministic suffix (e.g. 01, 02a). Always provided; no random generation."
  type        = string
}

variable "tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    project         = "ml-platform"
    created_by      = "terraform"
    owner           = "ml-team"
    SecurityControl = "Ignore"
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
    dns                = "dns-aml"
    workspace          = "mlw"
    registry           = "mlr"
    storage            = "st"
    container_registry = "acr"
    key_vault          = "kv"
    log_analytics      = "log"
  }
}

variable "shared_aml_dns_rg_name" {
  description = "Optional explicit name for the shared AML private DNS resource group (if null a name is generated)."
  type        = string
  default     = null
}

variable "defer_user_role_assignments" {
  description = "If true, skip immediate user RBAC assignments so they can be applied at the end after core infra succeeds."
  type        = bool
  default     = false
}

########################################
# NETWORK ADDRESS SPACES (PARAMETERIZED)
########################################
variable "dev_vnet_address_space" {
  description = "Address space list for the development VNet"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "dev_pe_subnet_prefix" {
  description = "CIDR prefix for the development private endpoints subnet"
  type        = string
  default     = "10.1.1.0/24"
}

variable "prod_vnet_address_space" {
  description = "Address space list for the production VNet"
  type        = list(string)
  default     = ["10.2.0.0/16"]
}

// Gateway subnet is not used; Bastion provides access.

variable "prod_pe_subnet_prefix" {
  description = "CIDR prefix for the production private endpoints subnet"
  type        = string
  default     = "10.2.1.0/24"
}

variable "dns_servers" {
  description = "List of custom DNS servers to apply to both VNets (defaults to Azure-provided wire server)."
  type        = list(string)
  default     = ["168.63.129.16"]
}

#############################
# LOG ANALYTICS CONFIG
#############################
variable "log_analytics_sku" {
  description = "SKU for the shared Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
}

variable "log_analytics_retention_days" {
  description = "Retention (days) for Log Analytics workspace"
  type        = number
  default     = 30
}

#############################
# AML MODULE BEHAVIOR
#############################
variable "enable_auto_purge" {
  description = "Enable auto purge for AML resources where supported"
  type        = bool
  default     = true
}

// No VPN gateway variables; design is Bastion-only.

########################################
# PRIVATE DNS ZONE NAMES (PARAMETERIZED)
########################################
variable "private_dns_zone_names" {
  description = "Object of private DNS zone names used for AML and dependent services"
  type = object({
    aml_api       = string
    aml_notebooks = string
    aml_instances = string
    blob          = string
    file          = string
    queue         = string
    table         = string
    vault         = string
    acr           = string
  })
  default = {
    aml_api       = "privatelink.api.azureml.ms"
    aml_notebooks = "privatelink.notebooks.azure.net"
    aml_instances = "instances.azureml.ms"
    blob          = "privatelink.blob.core.windows.net"
    file          = "privatelink.file.core.windows.net"
    queue         = "privatelink.queue.core.windows.net"
    table         = "privatelink.table.core.windows.net"
    vault         = "privatelink.vaultcore.azure.net"
    acr           = "privatelink.azurecr.io"
  }
}

variable "aml_instances_wildcard_ttl" {
  description = "TTL for AML instances wildcard A record"
  type        = number
  default     = 10
}

#############################
# KEY VAULT SECURITY
#############################
variable "key_vault_purge_protection_enabled" {
  description = "Enable Key Vault purge protection (should be true in production to prevent immediate purge). For sandbox/dev keep false so soft-deleted vaults can be purged automatically."
  type        = bool
  default     = false
}

########################################
# BASTION + JUMPBOX VM SETTINGS
########################################
variable "bastion_subnet_prefix" {
  description = "CIDR for AzureBastionSubnet (must be /26 or larger)."
  type        = string
  default     = "10.2.2.0/26"
}

variable "vm_subnet_prefix" {
  description = "CIDR for the jumpbox VM subnet"
  type        = string
  default     = "10.2.3.0/24"
}

variable "vm_admin_username" {
  description = "Admin username for the jumpbox VM"
  type        = string
}

variable "vm_admin_password" {
  description = "Admin password for the jumpbox VM (12-72 chars; include upper, lower, number, special)."
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.vm_admin_password) >= 12 && length(var.vm_admin_password) <= 72
    error_message = "vm_admin_password must be between 12 and 72 characters."
  }
}
