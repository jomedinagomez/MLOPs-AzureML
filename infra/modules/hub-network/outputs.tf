# Hub Network Module Outputs

output "hub_vnet_id" {
  description = "Resource ID of the hub VNet"
  value       = azurerm_virtual_network.hub_vnet.id
}

output "hub_vnet_name" {
  description = "Name of the hub VNet"
  value       = azurerm_virtual_network.hub_vnet.name
}

output "hub_vnet_address_space" {
  description = "Address space of the hub VNet"
  value       = azurerm_virtual_network.hub_vnet.address_space
}

output "vpn_gateway_id" {
  description = "Resource ID of the VPN Gateway"
  value       = azurerm_virtual_network_gateway.vpn_gateway.id
}

output "vpn_gateway_public_ip" {
  description = "Public IP address of the VPN Gateway"
  value       = azurerm_public_ip.vpn_gateway_pip.ip_address
}

output "vpn_gateway_fqdn" {
  description = "FQDN of the VPN Gateway"
  value       = azurerm_public_ip.vpn_gateway_pip.fqdn
}

output "gateway_subnet_id" {
  description = "Resource ID of the gateway subnet"
  value       = azurerm_subnet.gateway_subnet.id
}

output "vpn_client_address_space" {
  description = "Address space configured for VPN clients"
  value       = var.vpn_client_address_space
}
