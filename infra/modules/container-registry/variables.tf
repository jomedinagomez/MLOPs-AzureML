
variable "bypass_network_rules" {
  description = "Determines whether trusted Azure services are allowed to bypass the service firewall. Set to AzureServices or None"
  type        = string
  default     = "AzureServices"
}

variable "default_network_action" {
  description = "The default network action for the resource. Set to either Allow or Deny"
  type        = string
  default     = "Deny"
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

variable "public_network_access_enabled" {
  description = "The three character purpose of the resource"
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
  description = "Suffix for resource naming (preferred over random_string)"
  type        = string
  default     = null
}

variable "resource_group_name" {
  description = "The name of the resource group to deploy the resources to"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}

variable "enable_auto_purge" {
  description = "Enable automatic purging of Container Registry on destroy (useful for dev/test environments)"
  type        = bool
  default     = false
}
