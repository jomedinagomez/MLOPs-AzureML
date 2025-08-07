# Spoke Peering Module Outputs

output "peering_id" {
  description = "Resource ID of the VNet peering"
  value       = azurerm_virtual_network_peering.spoke_to_hub.id
}

output "peering_name" {
  description = "Name of the VNet peering"
  value       = azurerm_virtual_network_peering.spoke_to_hub.name
}
