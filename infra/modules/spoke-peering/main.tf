# Spoke to Hub VNet Peering

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = var.peering_name
  resource_group_name       = var.spoke_resource_group_name
  virtual_network_name      = var.spoke_vnet_name
  remote_virtual_network_id = var.hub_vnet_id

  allow_virtual_network_access = var.allow_virtual_network_access
  allow_forwarded_traffic      = var.allow_forwarded_traffic
  allow_gateway_transit        = var.allow_gateway_transit
  use_remote_gateways         = var.use_remote_gateways
}
