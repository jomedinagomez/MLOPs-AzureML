# Azure ML Registry Infrastructure Module

This Terraform module deploys an Azure Machine Learning Registry with private network connectivity and supporting infrastructure.

## Overview

This module creates a secure Azure ML Registry with:
- Azure ML Registry with system-assigned managed identity
- Private endpoint connectivity for secure access
- System-managed storage and container registry
- Log Analytics workspace for monitoring
- Proper RBAC role assignments

## Required Customizations

Before deploying, you MUST update the following values in `terraform.tfvars`:

### 1. User Object ID
```bash
# Get your Azure AD user object ID
az ad signed-in-user show --query id -o tsv
```
Update `user_object_id` in terraform.tfvars with the returned value.

### 2. Private DNS Zones Resource Group
Update `resource_group_name_dns` with the name of the resource group that contains your private DNS zones for:
- privatelink.api.azureml.ms

This should typically match the DNS resource group created by the `aml-vnet` module.

### 3. Subnet ID
Update `subnet_id` with the full resource ID of the subnet where private endpoints will be deployed.

Example format:
```
/subscriptions/{subscription-id}/resourceGroups/{vnet-rg-name}/providers/Microsoft.Network/virtualNetworks/{vnet-name}/subnets/{subnet-name}
```

### 4. Subscription ID
The `sub_id` should match your target Azure subscription ID. You can get it with:
```bash
az account show --query id -o tsv
```

### 5. Workload VNet Location
Update `workload_vnet_location` and `workload_vnet_location_code` to match the region where your VNet is deployed.

## Optional Customizations

### Location and Naming
- `location`: Azure region for resources (default: canadacentral)
- `location_code`: Short code for the region (e.g., "cc" for Canada Central)
- `purpose`: Environment identifier (e.g., "dev", "test", "prod")
- `random_string`: Unique identifier to ensure resource name uniqueness

### Tags
Customize the `tags` section to match your organization's tagging strategy.

## Architecture

This module creates the following Azure resources:

```
┌─────────────────────────────────────────────────────────┐
│                   Resource Group                        │
│ ┌─────────────────────────────────────────────────────┐ │
│ │            Azure ML Registry                        │ │
│ │  - System-assigned managed identity                 │ │
│ │  - Private network access only                      │ │
│ │  - System-managed storage (Standard_LRS)            │ │
│ │  - System-managed ACR (Premium SKU)                 │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│  Supporting Services:                                   │
│  - Log Analytics Workspace (monitoring)                 │
│  - Private Endpoint (secure connectivity)               │
└─────────────────────────────────────────────────────────┘
```

## Security Features

- **Network Isolation**: Registry accessible only via private endpoint
- **System-Managed Identity**: Automatic identity management for registry operations
- **Private Endpoint**: Secure connectivity from your VNet
- **Premium ACR**: High-performance container registry with security features
- **Monitoring**: Log Analytics integration for audit and monitoring

## Role Assignments

The module automatically creates the following role assignments:

**User Account:**
- Azure AI Developer (Registry scope)
- AzureML Registry User (Registry scope)

**Registry System Identity:**
- Contributor (Resource Group scope) - for managing system resources

## Prerequisites

- Azure CLI installed and authenticated
- Terraform >= 1.0 installed
- Existing VNet and subnet for private endpoints
- Private DNS zones configured and linked to your VNet (deployed via `aml-vnet` module)
- Appropriate Azure RBAC permissions to create resources
- Azure subscription with sufficient quota for ML resources

## Deployment Steps

1. **Initialize Terraform:**
```bash
terraform init
```

2. **Review and customize terraform.tfvars:**
```bash
# Copy the example file and customize
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values
```

3. **Plan the deployment:**
```bash
terraform plan
```

4. **Apply the configuration:**
```bash
terraform apply
```

5. **Verify deployment:**
```bash
# Check registry status
az ml registry show --name <registry-name> --resource-group <resource-group>

# List registry models (if any)
az ml model list --registry-name <registry-name>
```

## Post-Deployment Configuration

### Configure Registry Access
After deployment, the registry is accessible only via private endpoint from your VNet:

1. **Verify Private Endpoint Connectivity:**
```bash
# Test DNS resolution from a VM in your VNet
nslookup <registry-name>.privatelink.api.azureml.ms
```

2. **Connect from Azure ML Workspace:**
```bash
# Register the registry in your workspace
az ml registry connect --name <registry-name> --workspace-name <workspace-name>
```

## Resources Created

This module creates the following Azure resources:

### Core Infrastructure
- **Resource Group**: Container for all registry resources
- **Log Analytics Workspace**: Centralized logging and monitoring

### ML Registry Components
- **Azure ML Registry**: Main registry for models, components, and environments
- **System Storage Account**: Automatic storage (Standard_LRS, HNS disabled)
- **System Container Registry**: Automatic ACR (Premium SKU)

### Security & Connectivity
- **Private Endpoint**: Secure connectivity to the registry
- **Role Assignments**: Proper RBAC for users and system identity

## Outputs

The module provides the following outputs:

- `registry_name`: Name of the created ML registry
- `registry_id`: Full resource ID of the ML registry
- `resource_group_name`: Name of the created resource group
- `log_analytics_workspace_name`: Name of the Log Analytics workspace
- `registry_identity_principal_id`: Principal ID of the registry's system identity

## Troubleshooting

### Common Issues

1. **DNS Resolution Issues:**
   - Ensure private DNS zones are properly linked to your VNet
   - Verify DNS zone name matches exactly: `privatelink.api.azureml.ms`

2. **Permission Errors:**
   - Check if your user has sufficient RBAC permissions
   - Verify registry identity role assignments

3. **Network Connectivity:**
   - Confirm subnet has sufficient IP addresses
   - Check if Network Security Groups allow traffic
   - Verify private endpoint creation succeeded

### Useful Commands

```bash
# Check private endpoint status
az network private-endpoint list --resource-group <resource-group>

# Verify DNS resolution
nslookup <registry-name>.privatelink.api.azureml.ms

# Check role assignments
az role assignment list --scope <registry-resource-id>

# Test registry connectivity
az ml registry show --name <registry-name>
```

## Clean Up

To remove all resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete the registry including any models, components, or environments stored in it.

## Dependencies

This module depends on:
- `aml-vnet` module for networking infrastructure and private DNS zones
- Existing Azure subscription with proper quotas
- VNet and subnet for private endpoint connectivity

## Module Structure

```
aml-registry-smi/
├── main.tf                 # Main Terraform configuration
├── variables.tf            # Variable definitions
├── outputs.tf              # Output definitions
├── locals.tf               # Local value definitions
├── data.tf                 # Data source definitions
├── terraform.tfvars        # Configuration values
├── providers.tf            # Provider configuration
├── versions.tf             # Provider version constraints
└── README.md              # This documentation
```

## Related Modules

- **aml-vnet**: Creates VNet, subnets, and private DNS zones
- **aml-managed-smi**: Creates Azure ML workspace with managed VNet
- **modules/private-endpoint**: Shared module for private endpoint creation

## Best Practices

1. **Naming Convention**: Follow consistent naming patterns across all modules
2. **Network Security**: Use private endpoints for all ML services
3. **Access Control**: Implement least-privilege RBAC assignments
4. **Monitoring**: Enable Log Analytics for audit trails
5. **Resource Organization**: Use consistent tagging strategy
6. **Version Control**: Pin Terraform provider versions for stability
