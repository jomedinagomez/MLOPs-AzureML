# Hub Network Module README

## Overview
This module creates a hub network infrastructure for a hub-and-spoke architecture in Azure. It includes:

- Hub VNet with configurable address space
- VPN Gateway for Point-to-Site (P2S) connectivity
- Gateway subnet for the VPN Gateway
- Public IP for the VPN Gateway
- Optional VNet peering to spoke networks

## Features
- **Point-to-Site VPN**: Secure connectivity from local machines to Azure
- **Hub-and-Spoke Ready**: Designed for peering with spoke VNets
- **Certificate-based Authentication**: Uses root certificates for VPN client authentication
- **Configurable Gateway SKU**: Supports different VPN Gateway SKUs based on requirements

## Usage

```hcl
module "hub_network" {
  source = "./modules/hub-network"
  
  prefix                      = var.prefix
  location                    = var.location
  location_code              = var.location_code
  random_string              = random_string.main.result
  resource_group_name        = azurerm_resource_group.hub_network_rg.name
  
  hub_vnet_address_space           = "10.0.0.0/16"
  gateway_subnet_address_prefix    = "10.0.1.0/24"
  vpn_client_address_space         = "172.16.0.0/24"
  vpn_root_certificate_data        = var.vpn_root_certificate_data
  vpn_gateway_sku                  = "VpnGw2"
  
  # Optional: VNet peering configuration
  dev_vnet_id                = module.dev_vnet.vnet_id
  prod_vnet_id               = module.prod_vnet.vnet_id
  dev_vnet_name              = module.dev_vnet.vnet_name
  prod_vnet_name             = module.prod_vnet.vnet_name
  dev_vnet_resource_group    = azurerm_resource_group.dev_vnet_rg.name
  prod_vnet_resource_group   = azurerm_resource_group.prod_vnet_rg.name
  
  tags = var.tags
}
```

## Certificate Generation

Before using this module, you need to generate a root certificate for P2S VPN authentication:

### PowerShell (Windows)
```powershell
# Generate root certificate
$cert = New-SelfSignedCertificate -Type Custom -KeySpec Signature `
-Subject "CN=P2S-Root-Cert" -KeyExportPolicy Exportable `
-HashAlgorithm sha256 -KeyLength 2048 `
-CertStoreLocation "Cert:\CurrentUser\My" -KeyUsageProperty Sign -KeyUsage CertSign

# Export certificate (Base64 format needed)
[System.Convert]::ToBase64String($cert.RawData)
```

### Linux/macOS
```bash
# Generate private key
openssl genrsa -out P2SRootCert.key 2048

# Generate root certificate
openssl req -new -x509 -key P2SRootCert.key -out P2SRootCert.crt -days 3650 -subj "/CN=P2S-Root-Cert"

# Get Base64 content (remove header/footer)
openssl x509 -in P2SRootCert.crt -outform der | base64
```

## VPN Gateway SKUs

| SKU | Throughput | P2S Connections | S2S Tunnels |
|-----|------------|-----------------|-------------|
| VpnGw1 | 650 Mbps | 128 | 30 |
| VpnGw2 | 1 Gbps | 128 | 30 |
| VpnGw3 | 1.25 Gbps | 128 | 30 |

## Network Architecture

```
Hub VNet (10.0.0.0/16)
├── Gateway Subnet (10.0.1.0/24)
│   └── VPN Gateway
├── Peering to Dev VNet (10.1.0.0/16)
└── Peering to Prod VNet (10.2.0.0/16)

VPN Clients (172.16.0.0/24)
└── Connected via P2S VPN
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| prefix | Prefix for resource naming | string | n/a | yes |
| location | Azure region | string | n/a | yes |
| location_code | Short location code | string | n/a | yes |
| random_string | Random string for naming | string | n/a | yes |
| resource_group_name | Resource group name | string | n/a | yes |
| vpn_root_certificate_data | Base64 certificate data | string | n/a | yes |
| hub_vnet_address_space | Hub VNet address space | string | "10.0.0.0/16" | no |
| gateway_subnet_address_prefix | Gateway subnet prefix | string | "10.0.1.0/24" | no |
| vpn_client_address_space | VPN client address space | string | "172.16.0.0/24" | no |
| vpn_gateway_sku | VPN Gateway SKU | string | "VpnGw2" | no |

## Outputs

| Name | Description |
|------|-------------|
| hub_vnet_id | Hub VNet resource ID |
| vpn_gateway_id | VPN Gateway resource ID |
| vpn_gateway_public_ip | VPN Gateway public IP |
| vpn_client_address_space | VPN client address space |

## Dependencies

This module requires:
- Azure Resource Group (created externally)
- Root certificate for VPN authentication
- Spoke VNets (if peering is desired)

## Cost Considerations

- VPN Gateway: ~$140-280/month depending on SKU
- Public IP: ~$3-4/month
- Data transfer: Variable based on usage
- No additional cost for VNet peering within same region
