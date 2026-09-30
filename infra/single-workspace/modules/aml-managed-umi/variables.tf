
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

variable "resource_group_name" {
  description = "The name of the existing resource group where all AML workspace resources will be deployed"
  type        = string
}

variable "naming_suffix" {
  description = "Suffix for resource naming"
  type        = string
  default     = null
}

variable "sub_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "tags" {
  description = "Map of tags to apply to resources"
  type        = map(string)
}

variable "allowed_public_ip_cidrs" {
  description = "Public IPv4 CIDRs allowed through workspace and ACR firewalls and retained on private linked-service firewalls"
  type        = list(string)
}

variable "network_profile" {
  description = "Workspace network profile: managed or public"
  type        = string

  validation {
    condition     = contains(["managed", "public"], var.network_profile)
    error_message = "network_profile must be managed or public."
  }
}

variable "create_compute_resources" {
  description = "Create AML compute resources"
  type        = bool
  default     = false
}

variable "compute_cluster_identity_id" {
  description = "ID of the compute cluster user-assigned managed identity (passed from root orchestration)"
  type        = string
}

variable "compute_cluster_principal_id" {
  description = "Principal ID of the compute cluster user-assigned managed identity (passed from root orchestration)"
  type        = string
}

variable "compute_instance_identity_id" {
  description = "ID of the compute instance user-assigned managed identity"
  type        = string
}

variable "compute_instance_principal_id" {
  description = "Principal ID of the compute instance user-assigned managed identity"
  type        = string
}

variable "online_endpoint_identity_id" {
  description = "Resource ID of the managed online endpoint user-assigned managed identity"
  type        = string
}

variable "online_endpoint_principal_id" {
  description = "Principal ID of the managed online endpoint user-assigned managed identity"
  type        = string
}

variable "online_endpoint_deployer_principal_ids" {
  description = "Object IDs allowed to attach the online endpoint user-assigned managed identity"
  type        = set(string)
  default     = []
}

variable "compute_cluster_name" {
  description = "Optional explicit name for the AML compute cluster (overrides generated)."
  type        = string
  default     = null
}

variable "compute_cluster_vm_size" {
  description = "VM size for the AML compute cluster"
  type        = string
}

variable "compute_cluster_min_nodes" {
  description = "Minimum node count for the AML compute cluster"
  type        = number
}

variable "compute_cluster_max_nodes" {
  description = "Maximum node count for the AML compute cluster"
  type        = number
}

variable "compute_cluster_idle_seconds_before_scale_down" {
  description = "Idle duration in seconds before AML compute cluster scale-down"
  type        = number
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace for diagnostic settings"
  type        = string
}

variable "enable_auto_purge" {
  description = "Enable automatic purging of Key Vault on destroy (useful for dev/test environments)"
  type        = bool
  default     = false
}

variable "key_vault_purge_protection_enabled" {
  description = "Enable purge protection on the Key Vault created for the AML workspace"
  type        = bool
  default     = false
}

variable "provision_cmk_prerequisites" {
  description = "Provision CMK resources independently from enabling CMK on the AML workspace"
  type        = bool
  default     = false
}

variable "workspace_encryption" {
  description = "Encryption mode for the AML workspace"
  type        = string
  default     = "pmk"

  validation {
    condition     = contains(["pmk", "cmk"], var.workspace_encryption)
    error_message = "workspace_encryption must be either pmk or cmk."
  }
}

variable "key_vault_cmk_rbac_enabled" {
  description = "Use Azure RBAC instead of access policies for CMK authorization"
  type        = bool
  default     = true
}

variable "cmk_key_name" {
  description = "Name of the customer-managed key"
  type        = string
  default     = "cmkamlws"
}

// Human RBAC inputs are centralized in infra/spark-workspace/main.tf.

variable "compute_instance_name" {
  description = "Optional explicit name for the compute instance (overrides generated). Must be unique per workspace."
  type        = string
  default     = null
}

variable "compute_instance_vm_size" {
  description = "VM size for the AML compute instance"
  type        = string
}

variable "assigned_user_object_id" {
  description = "Object ID of the user to assign the compute instance to (POBO to disable SSO by default). If null, falls back to current caller."
  type        = string
  default     = null
}