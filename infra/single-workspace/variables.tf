variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  default     = "5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25"

  validation {
    condition     = var.subscription_id == "5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25"
    error_message = "This replacement root is restricted to the confirmed subscription."
  }
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "canadacentral"

  validation {
    condition     = contains(["canadacentral", "northcentralus"], var.location)
    error_message = "location must be canadacentral or northcentralus."
  }
}

variable "location_code" {
  description = "Short code for the Azure region"
  type        = string
  default     = "cc"

  validation {
    condition     = contains(["cc", "ncus"], var.location_code)
    error_message = "location_code must be cc or ncus."
  }
}

variable "prefix" {
  description = "Base prefix for resource names"
  type        = string
  default     = "aml"
}

variable "purpose" {
  description = "Purpose segment used to distinguish this stack from existing environments"
  type        = string
  default     = "spark"

  validation {
    condition     = contains(["spark", "public"], var.purpose)
    error_message = "purpose must be spark or public."
  }
}

variable "network_profile" {
  description = "Workspace network profile: managed uses AllowOnlyApprovedOutbound; public disables AML managed networking"
  type        = string
  default     = "managed"

  validation {
    condition     = contains(["managed", "public"], var.network_profile)
    error_message = "network_profile must be managed or public."
  }
}

variable "naming_suffix" {
  description = "Required deterministic suffix used to keep global Azure resource names unique"
  type        = string
  default     = "03"

  validation {
    condition     = can(regex("^[0-9]{2}$", var.naming_suffix))
    error_message = "naming_suffix must be exactly two digits."
  }
}

variable "create_compute_resources" {
  description = "Create AML compute; keep false during managed-network phase one and true for public workspaces"
  type        = bool
  default     = false
}

variable "allowed_public_ip_cidrs" {
  description = "Public IPv4 CIDRs allowed on the workspace and ACR; also retained on linked-service firewalls even when policy disables public access"
  type        = list(string)

  validation {
    condition = length(var.allowed_public_ip_cidrs) > 0 && alltrue([
      for cidr in var.allowed_public_ip_cidrs :
      can(cidrhost(cidr, 0)) &&
      !strcontains(cidr, ":") &&
      !can(regex("^(10\\.|127\\.|169\\.254\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.)", cidr))
    ])
    error_message = "allowed_public_ip_cidrs must contain at least one public IPv4 CIDR, such as 203.0.113.10/32."
  }
}

variable "assign_user_roles" {
  description = "Assign workspace and data access roles to the current Terraform caller"
  type        = bool
  default     = true
}

variable "assigned_user_object_id" {
  description = "Optional Microsoft Entra object ID assigned to the compute instance; defaults to the Terraform caller"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    project         = "ml-platform"
    created_by      = "terraform"
    owner           = "ml-team"
    SecurityControl = "Ignore"
  }

  validation {
    condition     = lookup(var.tags, "SecurityControl", null) == "Ignore"
    error_message = "tags must include SecurityControl = \"Ignore\"."
  }
}

variable "resource_prefixes" {
  description = "Prefixes used by the copied Azure ML modules"
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
    container_registry = "acr"
    key_vault          = "kv"
    log_analytics      = "log"
  }
}

variable "log_analytics_sku" {
  description = "Log Analytics workspace SKU"
  type        = string
  default     = "PerGB2018"
}

variable "log_analytics_retention_days" {
  description = "Log Analytics retention in days"
  type        = number
  default     = 30
}

variable "enable_auto_purge" {
  description = "Enable development-only purge helpers for supported resources"
  type        = bool
  default     = false
}

variable "key_vault_purge_protection_enabled" {
  description = "Purge protection is disabled for the workspace Key Vault; the CMK Key Vault remains protected"
  type        = bool
  default     = false

  validation {
    condition     = !var.key_vault_purge_protection_enabled
    error_message = "The Spark workspace requires workspace Key Vault purge protection to remain disabled."
  }
}

variable "compute_cluster_name" {
  description = "Optional compute cluster name"
  type        = string
  default     = null
}

variable "compute_cluster_vm_size" {
  description = "VM size for the compute cluster"
  type        = string
  default     = "Standard_F8s_v2"
}

variable "compute_cluster_min_nodes" {
  description = "Minimum compute cluster nodes"
  type        = number
  default     = 0

  validation {
    condition     = var.compute_cluster_min_nodes == 0
    error_message = "The baseline requires compute_cluster_min_nodes to remain 0 for cost control."
  }
}

variable "compute_cluster_max_nodes" {
  description = "Maximum compute cluster nodes"
  type        = number
  default     = 4

  validation {
    condition     = var.compute_cluster_max_nodes > 0
    error_message = "compute_cluster_max_nodes must be greater than zero."
  }
}

variable "compute_cluster_idle_seconds_before_scale_down" {
  description = "Idle seconds before the compute cluster scales down"
  type        = number
  default     = 120

  validation {
    condition = (
      var.compute_cluster_idle_seconds_before_scale_down >= 60 &&
      var.compute_cluster_idle_seconds_before_scale_down % 60 == 0
    )
    error_message = "compute_cluster_idle_seconds_before_scale_down must be at least 60 seconds and divisible by 60."
  }
}

variable "compute_instance_name" {
  description = "Optional compute instance name"
  type        = string
  default     = null
}

variable "compute_instance_vm_size" {
  description = "VM size for the compute instance"
  type        = string
  default     = "Standard_F8s_v2"
}

variable "online_endpoint_deployer_principal_ids" {
  description = "Microsoft Entra object IDs allowed to attach the online endpoint UAMI"
  type        = set(string)
  default     = []
}
