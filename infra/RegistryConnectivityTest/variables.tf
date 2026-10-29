variable "subscription_id" {
  description = "Subscription for the new, independently managed workspace."
  type        = string
}

variable "registry_id" {
  description = "Existing AML registry to test; this root does not manage its configuration or backing resources."
  type        = string

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.MachineLearningServices/registries/[^/]+$", var.registry_id))
    error_message = "Supply the full resource ID of an existing Azure ML registry."
  }
}

variable "assigned_user_object_id" {
  description = "Human Entra object ID for the duplicated personal compute instance."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.assigned_user_object_id))
    error_message = "Supply the human compute owner's Entra object ID."
  }
}

variable "location" {
  description = "Region matching the source workspace."
  type        = string
  default     = "northcentralus"
}

variable "location_code" {
  description = "Short region code used in resource names."
  type        = string
  default     = "ncus"

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.location_code))
    error_message = "Use two to six lowercase letters or digits."
  }
}

variable "naming_suffix" {
  description = "Fresh suffix; never reuse an existing environment's suffix or state."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.naming_suffix))
    error_message = "Use two to eight lowercase letters or digits."
  }
}

variable "prefix" {
  description = "Resource-group and VNet prefix."
  type        = string
  default     = "aml"
}

variable "purpose" {
  description = "Short environment name matching the source naming convention."
  type        = string
  default     = "private"

  validation {
    condition     = can(regex("^[a-z0-9]{2,7}$", var.purpose))
    error_message = "Use two to seven lowercase letters or digits."
  }
}

variable "vnet_address_space" {
  description = "Independent customer VNet address space for inbound private endpoints."
  type        = list(string)
  default     = ["10.31.0.0/16"]
}

variable "private_endpoint_subnet_prefix" {
  description = "Subnet for the new workspace's inbound private endpoints."
  type        = string
  default     = "10.31.1.0/24"
}

variable "tags" {
  description = "Tags for the new resources; policy opt-outs require separate approval."
  type        = map(string)
  default = {
    project    = "ml-platform"
    managed_by = "terraform"
    experiment = "registry-approver-only"
  }
}
