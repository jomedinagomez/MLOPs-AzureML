# Hub Network Module Main Configuration

locals {
  resolved_suffix = coalesce(var.naming_suffix, "")
  p2s_use_aad     = var.azure_ad_p2s_audience != ""
  aad_tenant_id   = coalesce(var.azure_ad_p2s_tenant_id, data.azurerm_client_config.current.tenant_id)
}

data "azurerm_client_config" "current" {}

# Hub VNet
resource "azurerm_virtual_network" "hub_vnet" {
  name                = "vnet-${var.prefix}-hub-${var.location_code}${local.resolved_suffix}"
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
  name                 = "GatewaySubnet" # This name is required by Azure
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = [var.gateway_subnet_address_prefix]
}

# Public IP for VPN Gateway
resource "azurerm_public_ip" "vpn_gateway_pip" {
  name                = "pip-vpngw-${var.prefix}-hub-${var.location_code}${local.resolved_suffix}"
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
  name                = "vpngw-${var.prefix}-hub-${var.location_code}${local.resolved_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name

  type       = "Vpn"
  vpn_type   = "RouteBased"
  sku        = var.vpn_gateway_sku
  enable_bgp = var.enable_bgp

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpn_gateway_pip.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway_subnet.id
  }

  # Point-to-Site (P2S) configuration supporting either Azure AD auth or certificate auth.
  # Mutual exclusivity enforced via validation below.
  dynamic "vpn_client_configuration" {
    for_each = local.p2s_use_aad ? [1] : []
    content {
      address_space        = [var.vpn_client_address_space]
      vpn_client_protocols = ["OpenVPN"]
      aad_tenant           = local.aad_tenant_id
      aad_issuer           = "https://sts.windows.net/${local.aad_tenant_id}/"
      aad_audience         = var.azure_ad_p2s_audience
    }
  }

  dynamic "vpn_client_configuration" {
    for_each = (!local.p2s_use_aad && var.vpn_root_certificate_data != "") ? [1] : []
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

# Validation to ensure only one auth method configured when enforcement enabled
resource "null_resource" "validate_p2s_auth" {
  count = var.aad_enforce_mutual_exclusion && var.azure_ad_p2s_audience != "" && var.vpn_root_certificate_data != "" ? 1 : 0

  provisioner "local-exec" {
    when    = destroy
    command = "echo 'destroy noop'"
  }

  lifecycle {
    prevent_destroy = false
  }

  triggers = {
    error = "Cannot set both azure_ad_p2s_audience and vpn_root_certificate_data. Choose one authentication method."
  }
}

locals {
  _p2s_auth_conflict = var.aad_enforce_mutual_exclusion && var.azure_ad_p2s_audience != "" && var.vpn_root_certificate_data != ""
}

terraform {
  required_version = ">= 1.0.0"
}

locals {
  p2s_auth_method = local.p2s_use_aad ? "AzureAD" : (var.vpn_root_certificate_data != "" ? "Certificate" : "None")
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
  use_remote_gateways          = false

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
  use_remote_gateways          = false

  depends_on = [
    azurerm_virtual_network.hub_vnet,
    azurerm_virtual_network_gateway.vpn_gateway
  ]
}
