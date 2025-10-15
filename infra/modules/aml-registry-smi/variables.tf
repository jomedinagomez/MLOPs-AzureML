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
  description = "Short code for the region (e.g., 'we' for West Europe)"
  type        = string
}

variable "naming_suffix" {
  description = "Suffix for resource naming"
  type        = string
  default     = null
}

variable "resource_group_name_dns" {
  description = "The name of the resource group where the Private DNS Zones exist"
  type        = string
}

variable "sub_id" {
  description = "The subscription where the Private DNS Zones are located"
  type        = string
}

variable "subnet_id" {
  description = "The subnet id to deploy the private endpoints to"
  type        = string
}

variable "tags" {
  description = "Map of tags to apply to resources"
  type        = map(string)
}

variable "resource_group_name" {
  description = "Resource group name where the registry will be deployed (must exist)"
  type        = string
}


variable "workload_vnet_location" {
  description = "The region where the workload virtual network is located"
  type        = string
}

variable "workload_vnet_location_code" {
  description = "The region code where the workload virtual network is located"
  type        = string
}

# Optional DNS Zone IDs (for when using module outputs)
variable "dns_zone_blob_id" {
  description = "ID of the blob storage DNS zone"
  type        = string
  default     = null
}

variable "dns_zone_file_id" {
  description = "ID of the file storage DNS zone"
  type        = string
  default     = null
}

variable "dns_zone_keyvault_id" {
  description = "ID of the Key Vault DNS zone"
  type        = string
  default     = null
}

variable "dns_zone_acr_id" {
  description = "ID of the Container Registry DNS zone"
  type        = string
  default     = null
}

variable "dns_zone_aml_api_id" {
  description = "ID of the Azure ML API DNS zone"
  type        = string
  default     = null
}


variable "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace for diagnostic settings"
  type        = string
}

// RBAC-related inputs removed; RBAC is centralized in infra/main.tf

// Principal to assign to the registry's managed resource group so it inherits Azure AI admin capabilities
// Use the object ID of the service principal provisioning the resources
variable "managed_rg_assigned_principal_id" {
  description = "Object ID of the principal to assign in the registry managed resource group (assignedIdentities.principalId)"
  type        = string
}