variable "access_policies" {
  description = "The access policies if the Key Vault is not using Azure RBAC for authorization"
  type = list(object({
    object_id               = string
    secret_permissions      = optional(list(string))
    key_permissions         = optional(list(string))
    certificate_permissions = optional(list(string))
  }))

  default = []
}

variable "disk_encryption" {
  description = "Specifies whether Azure Disk Encryption is permitted to write secrets to the Key Vault"
  type        = bool
  default     = false
}

variable "firewall_bypass" {
  description = "The bypass rules for the Key Vault firewall"
  type        = string
  default     = "AzureServices"
}

variable "firewall_default_action" {
  description = "The default action for the Key Vault firewall"
  type        = string
  default     = "Deny"
}

variable "firewall_ip_rules" {
  description = "The IPs to allowed to bypass the Key Vault firewall"
  type        = list(string)
  default     = []
}



variable "law_resource_id" {
  description = "The resource id of the Log Analytics Workspace to send diagnostic logs to"
  type        = string
}

variable "location" {
  description = "The name of the location to provision the resources to"
  type        = string
}

variable "location_code" {
  description = "The location code to append to the resource name"
  type        = string
}

variable "purge_protection" {
  description = "Specify whether purge protection is enabled for the Key Vault"
  type        = bool
  default     = false
}

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
  description = "The three character purpose of the resource"
  type        = string
}

variable "naming_suffix" {
  description = "Suffix for resource naming"
  type        = string
  default     = null
}

variable "rbac_enabled" {
  description = "The Key Vault should use Azure RBAC for authorization"
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "The name of the resource group to deploy the resources to"
  type        = string
}

variable "soft_delete_retention_days" {
  description = "The number of days that items should be retained for once soft deleted"
  type        = number
  default     = 7
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}

variable "enable_auto_purge" {
  description = "Enable automatic purging of Key Vault on destroy (useful for dev/test environments)"
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Whether public network access is enabled for the Key Vault. Set to false to require private endpoints."
  type        = bool
  default     = false
}
