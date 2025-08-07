# Hub Network Module Main Configuration

# Hub VNet
resource "azurerm_virtual_network" "hub_vnet" {
  name                = "vnet-${var.prefix}-hub-${var.location_code}${var.random_string}"
  address_space       = [var.hub_vnet_address_space]
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(var.tags, {
    component = "hub-network"
    purpose   = "hub"
  })
}

# Gateway Subnet (required for VPN Gateway)
resource "azurerm_subnet" "gateway_subnet" {
  name                 = "GatewaySubnet"  # This name is required by Azure
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = [var.gateway_subnet_address_prefix]
}

# Public IP for VPN Gateway
resource "azurerm_public_ip" "vpn_gateway_pip" {
  name                = "pip-vpngw-${var.prefix}-hub-${var.location_code}${var.random_string}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = merge(var.tags, {
    component = "vpn-gateway"
    purpose   = "hub"
  })
}

# VPN Gateway
resource "azurerm_virtual_network_gateway" "vpn_gateway" {
  name                = "vpngw-${var.prefix}-hub-${var.location_code}${var.random_string}"
  location            = var.location
  resource_group_name = var.resource_group_name

  type     = "Vpn"
  vpn_type = "RouteBased"
  sku      = var.vpn_gateway_sku
  enable_bgp = var.enable_bgp

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpn_gateway_pip.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway_subnet.id
  }

  # Only configure Point-to-Site (P2S) when a root certificate is provided
  dynamic "vpn_client_configuration" {
    for_each = var.vpn_root_certificate_data != "" ? [1] : []
    content {
      address_space        = [var.vpn_client_address_space]
      vpn_client_protocols = ["OpenVPN", "IkeV2"]

      root_certificate {
        name             = "P2SRootCert"
        public_cert_data = var.vpn_root_certificate_data
      }
    }
  }

  tags = merge(var.tags, {
    component = "vpn-gateway"
    purpose   = "hub"
  })

  depends_on = [
    azurerm_public_ip.vpn_gateway_pip,
    azurerm_subnet.gateway_subnet
  ]
}

# VNet Peering to Dev Environment
resource "azurerm_virtual_network_peering" "hub_to_dev" {
  name                      = "peer-hub-to-dev"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = azurerm_virtual_network.hub_vnet.name
  remote_virtual_network_id = var.dev_vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways         = false

  depends_on = [
    azurerm_virtual_network.hub_vnet,
    azurerm_virtual_network_gateway.vpn_gateway
  ]
}

# VNet Peering to Prod Environment
resource "azurerm_virtual_network_peering" "hub_to_prod" {
  name                      = "peer-hub-to-prod"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = azurerm_virtual_network.hub_vnet.name
  remote_virtual_network_id = var.prod_vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways         = false

  depends_on = [
    azurerm_virtual_network.hub_vnet,
    azurerm_virtual_network_gateway.vpn_gateway
  ]
}
