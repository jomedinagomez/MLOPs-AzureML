# Azure ML Virtual Network Infrastructure Module

This Terraform module deploys the foundational networking infrastructure required for Azure Machine Learning services, including virtual network, subnets, private DNS zones, and managed identities.

## Overview

This module creates the networking foundation for secure Azure ML deployments:
- Virtual Network with dedicated subnet for ML resources
- Nine private DNS zones for all Azure ML and supporting services
- VNet links for proper DNS resolution
- User-assigned managed identities for compute clusters and endpoints
- Complete network isolation foundation

## Required Customizations

Before deploying, you MUST update the following values in `terraform.tfvars`:

### 1. Network Configuration
Update the following network settings to match your requirements:

```hcl
vnet_address_space     = "10.1.0.0/16"        # VNet address range
subnet_address_prefix  = "10.1.1.0/24"        # Subnet for ML resources
```

**Important**: Ensure these address ranges don't conflict with existing networks in your environment.

### 2. Location and Naming
- `location`: Azure region for all resources
- `location_code`: Short code for the region (e.g., "cc" for Canada Central)
- `purpose`: Environment identifier (e.g., "dev", "test", "prod")
- `random_string`: Unique identifier to ensure resource name uniqueness

### 3. Tags
Customize the `tags` section to match your organization's tagging strategy.

## Optional Customizations

All variables have sensible defaults but can be customized based on your requirements:

- **Network Sizing**: Adjust VNet and subnet address spaces based on your scale requirements
- **Naming Convention**: Modify the naming pattern in `locals.tf` if needed
- **Resource Organization**: Update tags for consistent resource management

## Architecture

This module creates the networking foundation for a complete Azure ML environment:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Networking Resource Group                    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                Virtual Network                          │    │
│  │  Address Space: 10.1.0.0/16 (customizable)              │    │
│  │                                                         │    │
│  │  ┌─────────────────────────────────────────────────┐    │    │
│  │  │              ML Subnet                          │    │    │
│  │  │  Address: 10.1.1.0/24 (customizable)            │    │    │
│  │  │  - Private endpoints for ML services            │    │    │
│  │  │  - Compute clusters and endpoints               │    │    │
│  │  └─────────────────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  Private DNS Zones (9 zones):                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Storage Account DNS Zones:                             │    │
│  │  • privatelink.blob.core.windows.net                    │    │
│  │  • privatelink.file.core.windows.net                    │    │
│  │  • privatelink.table.core.windows.net                   │    │
│  │  • privatelink.queue.core.windows.net                   │    │
│  │                                                         │    │
│  │  Supporting Service DNS Zones:                          │    │
│  │  • privatelink.vaultcore.azure.net (Key Vault)          │    │
│  │  • privatelink.azurecr.io (Container Registry)          │    │
│  │                                                         │    │
│  │  Azure ML DNS Zones:                                    │    │
│  │  • privatelink.api.azureml.ms (ML API)                  │    │
│  │  • privatelink.notebooks.azure.net (Notebooks)          │    │
│  │  • instances.azureml.ms (Compute Instances)             │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  Managed Identities:                                            │
│  • Compute Cluster Identity                                     │
│  • Managed Online Endpoint Identity                             │
└─────────────────────────────────────────────────────────────────┘
```

## Security Features

- **Network Isolation**: Dedicated VNet and subnet for ML workloads
- **Private DNS**: Complete DNS resolution for private endpoints
- **Managed Identities**: Secure identity management for compute resources
- **DNS Zone Linking**: Automatic VNet linking for all private DNS zones
- **Foundation for Zero-Trust**: Network architecture supports complete private connectivity

## Resources Created

This module creates the following Azure resources:

### Core Network Infrastructure
- **Resource Group**: Container for all networking resources
- **Virtual Network**: Dedicated network for ML workloads
- **Subnet**: Dedicated subnet for ML services and private endpoints

### DNS Infrastructure (9 Private DNS Zones)
**Storage Account DNS Zones:**
- `privatelink.blob.core.windows.net` - Blob storage private connectivity
- `privatelink.file.core.windows.net` - File share private connectivity  
- `privatelink.table.core.windows.net` - Table storage private connectivity
- `privatelink.queue.core.windows.net` - Queue storage private connectivity

**Supporting Service DNS Zones:**
- `privatelink.vaultcore.azure.net` - Key Vault private connectivity
- `privatelink.azurecr.io` - Container Registry private connectivity

**Azure ML Service DNS Zones:**
- `privatelink.api.azureml.ms` - ML workspace API private connectivity
- `privatelink.notebooks.azure.net` - ML notebooks private connectivity
- `instances.azureml.ms` - ML compute instances private connectivity

### VNet Links
- **9 VNet Links**: Connect all private DNS zones to the VNet for proper name resolution

### Identity Management
- **Compute Cluster Identity**: User-assigned managed identity for ML compute clusters
- **Managed Online Endpoint Identity**: User-assigned managed identity for ML endpoints

## Prerequisites

- Azure CLI installed and authenticated
- Terraform >= 1.0 installed
- Appropriate Azure RBAC permissions to create networking resources
- Azure subscription with sufficient quota for networking resources
- Understanding of your network addressing requirements

## Deployment Steps

1. **Initialize Terraform:**
```bash
terraform init
```

2. **Review and customize terraform.tfvars:**
```bash
# Copy the example file and customize
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific network configuration
```

3. **Validate network configuration:**
```bash
# Ensure your address spaces don't conflict with existing networks
az network vnet list --query "[].addressSpace.addressPrefixes" -o table
```

4. **Plan the deployment:**
```bash
terraform plan
```

5. **Apply the configuration:**
```bash
terraform apply
```

6. **Verify deployment:**
```bash
# Check VNet creation
az network vnet show --name <vnet-name> --resource-group <resource-group>

# Verify DNS zones
az network private-dns zone list --resource-group <resource-group> -o table

# Check VNet links
az network private-dns link vnet list --zone-name privatelink.api.azureml.ms --resource-group <resource-group>
```

## Post-Deployment Configuration

### Network Validation
After deployment, validate the network infrastructure:

1. **DNS Resolution Testing:**
```bash
# From a VM in the VNet, test DNS resolution
nslookup privatelink.blob.core.windows.net
nslookup privatelink.api.azureml.ms
```

2. **Connectivity Validation:**
```bash
# Verify subnet has sufficient IP addresses for your planned deployments
az network vnet subnet show --vnet-name <vnet-name> --name <subnet-name> --resource-group <resource-group>
```

3. **Identity Verification:**
```bash
# Check managed identities are created
az identity list --resource-group <resource-group> -o table
```

## Outputs

The module provides the following outputs for use by other modules:

### Network Outputs
- `resource_group_name`: Name of the networking resource group
- `vnet_id`: Full resource ID of the virtual network
- `vnet_name`: Name of the virtual network
- `subnet_id`: Full resource ID of the ML subnet

### DNS Zone Outputs
- `dns_zone_blob_id`: Resource ID of blob storage DNS zone
- `dns_zone_file_id`: Resource ID of file storage DNS zone
- `dns_zone_table_id`: Resource ID of table storage DNS zone
- `dns_zone_queue_id`: Resource ID of queue storage DNS zone
- `dns_zone_keyvault_id`: Resource ID of Key Vault DNS zone
- `dns_zone_acr_id`: Resource ID of Container Registry DNS zone
- `dns_zone_aml_api_id`: Resource ID of ML API DNS zone
- `dns_zone_aml_notebooks_id`: Resource ID of ML notebooks DNS zone
- `dns_zone_aml_instances_id`: Resource ID of ML instances DNS zone

### Identity Outputs
- `cc_identity_id`: Resource ID of compute cluster managed identity
- `moe_identity_id`: Resource ID of managed online endpoint identity

## Troubleshooting

### Common Issues

1. **Address Space Conflicts:**
   - Verify VNet address space doesn't overlap with existing networks
   - Check peering requirements if connecting to other VNets

2. **DNS Resolution Issues:**
   - Ensure all VNet links are properly created
   - Verify DNS zones are correctly named
   - Check if custom DNS servers are interfering

3. **Permission Errors:**
   - Verify you have Network Contributor permissions
   - Check subscription limits for VNets and DNS zones

4. **Resource Naming Conflicts:**
   - Ensure `random_string` provides sufficient uniqueness
   - Check for existing resources with similar names

### Useful Commands

```bash
# Check VNet configuration
az network vnet show --name <vnet-name> --resource-group <resource-group>

# List all private DNS zones
az network private-dns zone list --resource-group <resource-group> -o table

# Verify VNet links for a specific DNS zone
az network private-dns link vnet list --zone-name <dns-zone-name> --resource-group <resource-group>

# Check subnet details
az network vnet subnet show --vnet-name <vnet-name> --name <subnet-name> --resource-group <resource-group>

# Verify managed identities
az identity list --resource-group <resource-group>

# Test DNS resolution (from a VM in the VNet)
nslookup privatelink.api.azureml.ms
dig @168.63.129.16 privatelink.blob.core.windows.net
```

## Clean Up

To remove all resources:

```bash
terraform destroy
```

**Warning**: This will delete the entire network infrastructure. Ensure no other resources depend on these networking components before destroying.

## Dependencies

This module has minimal external dependencies:
- Azure subscription with appropriate quotas
- Sufficient RBAC permissions for networking operations
- No conflicts with existing network address spaces

## Module Structure

```
aml-vnet/
├── main.tf                 # Main Terraform configuration
├── variables.tf            # Variable definitions
├── locals.tf               # Local value definitions
├── terraform.tfvars        # Configuration values
├── provider.tf             # Provider configuration
└── README.md              # This documentation
```

## Related Modules

This module provides foundational networking for:
- **aml-managed-smi**: Azure ML workspace with managed VNet
- **aml-registry-smi**: Azure ML registry with private connectivity
- **modules/private-endpoint**: Shared private endpoint creation

## Best Practices

1. **Network Planning**: Carefully plan address spaces to avoid future conflicts
2. **DNS Management**: Maintain consistent DNS zone naming across environments
3. **Security**: Use private endpoints for all Azure services
4. **Monitoring**: Enable network monitoring and flow logs
5. **Documentation**: Document network topology and addressing scheme
6. **Standardization**: Use consistent naming and tagging across environments

## Network Planning Guidelines

### Address Space Recommendations

| Environment | VNet CIDR | Subnet CIDR | Max Private Endpoints |
|-------------|-----------|-------------|----------------------|
| Development | /20 (4096 IPs) | /24 (256 IPs) | ~200 |
| Testing | /19 (8192 IPs) | /23 (512 IPs) | ~400 |
| Production | /18 (16384 IPs) | /22 (1024 IPs) | ~800 |

### DNS Zone Requirements

All 9 private DNS zones are required for complete Azure ML functionality:
- Storage zones enable private access to ML data and artifacts
- Key Vault zone secures secrets and certificates
- Container Registry zone protects ML container images
- ML-specific zones enable private workspace and compute access
