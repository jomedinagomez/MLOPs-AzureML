variable "subscription_id" {
  description = "Azure subscription in which to create this independent deployment."
  type        = string
}

variable "location" {
  description = "Azure region for the workspace, registry, compute, and customer VNet."
  type        = string
}

variable "location_code" {
  description = "Short lowercase region code used in deterministic resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.location_code))
    error_message = "Use two to six lowercase letters or digits."
  }
}

variable "naming_suffix" {
  description = "Globally unique lowercase alphanumeric suffix; use a different suffix from existing stacks."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.naming_suffix))
    error_message = "Use two to eight lowercase letters or digits."
  }
}

variable "prefix" {
  description = "Prefix for resource group and network names."
  type        = string
  default     = "aml"
}

variable "purpose" {
  description = "Short environment name used in workspace, registry, and dependency names."
  type        = string
  default     = "private"

  validation {
    condition     = can(regex("^[a-z0-9]{2,7}$", var.purpose))
    error_message = "Use two to seven lowercase letters or digits."
  }
}

variable "assigned_user_object_id" {
  description = "Entra object ID of the human compute-instance owner, not the deployment managed identity."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.assigned_user_object_id))
    error_message = "Supply the human user's Entra object ID as a GUID."
  }
}

variable "registry_managed_rg_assigned_principal_ids" {
  description = "Optional service-principal object IDs, such as a deployment UAMI, requiring access to registry-managed resources. Never include a human user object ID."
  type        = set(string)
  default     = []
}

variable "vnet_address_space" {
  description = "Customer VNet address space for inbound private endpoints; this is not the AML-managed VNet."
  type        = list(string)
  default     = ["10.30.0.0/16"]
}

variable "private_endpoint_subnet_prefix" {
  description = "Subnet CIDR for workspace, registry, and dependency private endpoints."
  type        = string
  default     = "10.30.1.0/24"
}

variable "tags" {
  description = "Tags applied to resources."
  type        = map(string)
  default = {
    project    = "ml-platform"
    managed_by = "terraform"
  }
}
