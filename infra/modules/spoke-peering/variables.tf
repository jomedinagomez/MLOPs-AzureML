# Spoke VNet Peering Module Variables

variable "spoke_vnet_name" {
  description = "Name of the spoke VNet"
  type        = string
}

variable "spoke_resource_group_name" {
  description = "Resource group name of the spoke VNet"
  type        = string
}

variable "hub_vnet_id" {
  description = "Resource ID of the hub VNet"
  type        = string
}

variable "peering_name" {
  description = "Name for the peering connection"
  type        = string
}

variable "allow_virtual_network_access" {
  description = "Allow virtual network access"
  type        = bool
  default     = true
}

variable "allow_forwarded_traffic" {
  description = "Allow forwarded traffic"
  type        = bool
  default     = true
}

variable "allow_gateway_transit" {
  description = "Allow gateway transit"
  type        = bool
  default     = false
}

variable "use_remote_gateways" {
  description = "Use remote gateways"
  type        = bool
  default     = true
}
