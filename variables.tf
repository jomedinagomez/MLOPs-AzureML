variable "resource_group_name" {
  description = "Name for the resource group (VNet)"
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

variable "vnet_name" {
  description = "Name for the virtual network"
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the VNet (e.g., '10.1.0.0/16')"
  type        = string
}

variable "subnet_name" {
  description = "Name for the subnet"
  type        = string
}

variable "subnet_address_prefix" {
  description = "Address prefix for the subnet (e.g., '10.1.1.0/24')"
  type        = string
}

variable "tags" {
  description = "Map of tags to apply to resources"
  type        = map(string)
}

variable "random_string" {
  description = "Unique string for resource naming"
  type        = string
}

variable "purpose" {
  description = "Purpose or environment tag (e.g., 'dev', 'prod')"
  type        = string
}

variable "user_object_id" {
  description = "Azure AD object ID for role assignments (AML workspace)"
  type        = string
}

variable "workload_vnet_location" {
  description = "Region of the workload VNet (usually same as location)"
  type        = string
}

variable "workload_vnet_location_code" {
  description = "Short code for the workload VNet region (usually same as location_code)"
  type        = string
}

variable "subnet_id" {
  description = "Subnet resource ID (output from VNet, input to registry/workspace)"
  type        = string
}

variable "sub_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "resource_group_name_dns" {
  description = "Resource group name for private DNS zones"
  type        = string
}
