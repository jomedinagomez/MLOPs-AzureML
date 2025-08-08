# Hub Network Module Variables

variable "prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "location_code" {
  description = "Short location code for resource naming"
  type        = string
}

variable "naming_suffix" {
  description = "Suffix for unique resource naming"
  type        = string
  default     = null
}

variable "resource_group_name" {
  description = "Name of the resource group for hub network resources"
  type        = string
}

variable "hub_vnet_address_space" {
  description = "Address space for the hub VNet"
  type        = string
  default     = "10.0.0.0/16"
}

variable "gateway_subnet_address_prefix" {
  description = "Address prefix for the gateway subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "vpn_client_address_space" {
  description = "Address space for VPN clients"
  type        = string
  default     = "172.16.0.0/24"
}

variable "vpn_root_certificate_data" {
  description = "Base64 encoded root certificate data for P2S VPN authentication"
  type        = string
  sensitive   = true
}

variable "azure_ad_p2s_audience" {
  description = "Application (client) ID of the Azure AD Server App used as audience for P2S AAD auth. Empty disables AAD auth."
  type        = string
  default     = ""
  validation {
    condition     = !(var.azure_ad_p2s_audience != "" && var.vpn_root_certificate_data != "")
    error_message = "Provide only one P2S auth method: azure_ad_p2s_audience or vpn_root_certificate_data."
  }
}

variable "azure_ad_p2s_tenant_id" {
  description = "Tenant ID for Azure AD P2S auth. If null current tenant will be used (passed from root)."
  type        = string
  default     = null
}

variable "aad_enforce_mutual_exclusion" {
  description = "Internal safety toggle to ensure only one auth method configured."
  type        = bool
  default     = true
}

variable "vpn_gateway_sku" {
  description = "SKU for the VPN Gateway"
  type        = string
  default     = "VpnGw2"
}

variable "enable_bgp" {
  description = "Enable BGP for the VPN Gateway"
  type        = bool
  default     = false
}

variable "dev_vnet_id" {
  description = "Resource ID of the development VNet for peering"
  type        = string
  default     = ""
}

variable "prod_vnet_id" {
  description = "Resource ID of the production VNet for peering"
  type        = string
  default     = ""
}

variable "dev_vnet_name" {
  description = "Name of the development VNet"
  type        = string
  default     = ""
}

variable "prod_vnet_name" {
  description = "Name of the production VNet"
  type        = string
  default     = ""
}

variable "dev_vnet_resource_group" {
  description = "Resource group name of the development VNet"
  type        = string
  default     = ""
}

variable "prod_vnet_resource_group" {
  description = "Resource group name of the production VNet"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
