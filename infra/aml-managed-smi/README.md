# Azure ML Workspace Infrastructure Module

This Terraform module deploys a complete Azure Machine Learning workspace with managed virtual network, supporting services, and security configurations.

## Overview

This module creates a production-ready Azure ML workspace with:
- Managed virtual network for secure communication
- Private endpoints for all Azure services
- Supporting infrastructure (Storage, Key Vault, Container Registry, Application Insights)
- Compute cluster with managed identity
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
- privatelink.blob.core.windows.net
- privatelink.file.core.windows.net
- privatelink.table.core.windows.net
- privatelink.queue.core.windows.net
- privatelink.vaultcore.azure.net
- privatelink.azurecr.io
- privatelink.api.azureml.ms
- privatelink.notebooks.azure.net
- instances.azureml.ms

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

## Optional Customizations

### Location and Naming
- `location`: Azure region for resources (default: canadacentral)
- `location_code`: Short code for the region (e.g., "cc" for Canada Central)
- `purpose`: Environment identifier (e.g., "dev", "test", "prod")
- `random_string`: Unique identifier to ensure resource name uniqueness

### Compute Configuration
- `compute_cluster_min_nodes`: Minimum number of nodes in the compute cluster (default: 2)
- `compute_cluster_max_nodes`: Maximum number of nodes in the compute cluster (default: 2)
- `compute_cluster_vm_size`: VM size for compute nodes (default: Standard_DS3_v2)

### Tags
Customize the `tags` section to match your organization's tagging strategy.

## Architecture

This module creates the following Azure resources:

```
┌─────────────────────────────────────────────────────────┐
│                   Resource Group                        │
│ ┌─────────────────────────────────────────────────────┐ │
│ │              Azure ML Workspace                     │ │
│ │  ┌─────────────────────────────────────────────────┐│ │
│ │  │         Managed Virtual Network                 ││ │
│ │  │  - Isolation Mode: allow_only_approved_outbound ││ │
│ │  │  - Private endpoints for all services           ││ │
│ │  │  - Compute cluster with managed identity        ││ │
│ │  └─────────────────────────────────────────────────┘│ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│  Supporting Services:                                   │
│  - Storage Account (blob, file, table, queue)           │
│  - Key Vault (secrets, keys, certificates)              │
│  - Container Registry (Docker images)                   │
│  - Application Insights (monitoring)                    │
│  - Log Analytics Workspace (logging)                    │
└─────────────────────────────────────────────────────────┘
```

## Security Features

- **Network Isolation**: All services communicate via private endpoints
- **Managed Identity**: User-assigned managed identity for compute resources
- **RBAC**: Automatic role assignments for workspace and compute operations
- **Key Management**: Azure Key Vault integration for secrets
- **Monitoring**: Application Insights and Log Analytics integration

## Role Assignments

The module automatically creates the following role assignments:

**User Account:**
- Azure AI Developer (Workspace scope)
- AzureML Compute Operator (Workspace scope) 
- AzureML Data Scientist (Workspace scope)

**Managed Identity (Compute Cluster):**
- AzureML Data Scientist (Resource Group scope)
- Storage Blob Data Contributor (Resource Group scope)
- Key Vault Secrets User (Resource Group scope)

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
# Check workspace status
az ml workspace show --name <workspace-name> --resource-group <resource-group>

# List compute clusters
az ml compute list --workspace-name <workspace-name> --resource-group <resource-group>
```

## Post-Deployment Configuration

### Configure IP Whitelisting
After deployment, configure network access:

1. **Workspace Network ACLs:**
```bash
# Add your IP to workspace access
az ml workspace update \
  --name <workspace-name> \
  --resource-group <resource-group> \
  --public-network-access Enabled \
  --allowed-ips <your-ip>/32
```

2. **Storage Account Network ACLs:**
```bash
# Add your IP to storage account
az storage account network-rule add \
  --account-name <storage-account-name> \
  --resource-group <resource-group> \
  --ip-address <your-ip>
```

## Resources Created

This module creates the following Azure resources:

### Core Infrastructure
- **Resource Group**: Container for all ML workspace resources
- **Log Analytics Workspace**: Centralized logging and monitoring
- **Application Insights**: Application performance monitoring

### ML Workspace Components  
- **Azure ML Workspace**: Main ML workspace with managed VNet
- **Compute Cluster**: Auto-scaling compute with managed identity
- **User-Assigned Managed Identity**: For secure resource access

### Supporting Services
- **Azure Container Registry**: Container image storage
- **Storage Account**: Data and artifact storage with multiple endpoints
- **Key Vault**: Secure secrets and key management

### Private Connectivity
- **7 Private Endpoints**: Secure connectivity for all services
  - Storage Account (blob, file, table, queue)
  - Key Vault
  - Container Registry  
  - ML Workspace

### Security & Access
- **Role Assignments**: Proper RBAC for users and managed identities
- **Network Security**: Private endpoint connectivity only

## Outputs

The module provides the following outputs:

- `workspace_name`: Name of the created ML workspace
- `workspace_id`: Full resource ID of the ML workspace
- `resource_group_name`: Name of the created resource group
- `compute_cluster_name`: Name of the created compute cluster
- `managed_identity_id`: ID of the user-assigned managed identity
- `storage_account_name`: Name of the created storage account
- `key_vault_name`: Name of the created Key Vault
- `container_registry_name`: Name of the created Container Registry

## Troubleshooting

### Common Issues

1. **DNS Resolution Issues:**
   - Ensure private DNS zones are properly linked to your VNet
   - Verify DNS zone names match exactly

2. **Permission Errors:**
   - Check if your user has sufficient RBAC permissions
   - Verify managed identity role assignments

3. **Network Connectivity:**
   - Confirm subnet has sufficient IP addresses
   - Check if Network Security Groups allow traffic
   - Verify private endpoint creation succeeded

### Useful Commands

```bash
# Check private endpoint status
az network private-endpoint list --resource-group <resource-group>

# Verify DNS resolution
nslookup <workspace-name>.workspace.<region>.api.azureml.ms

# Check role assignments
az role assignment list --scope <resource-scope>

# Monitor deployment logs
az monitor activity-log list --resource-group <resource-group>
```

## Clean Up

To remove all resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete all resources including data stored in the storage account and any trained models.

## Dependencies

This module depends on:
- `aml-vnet` module for networking infrastructure
- Private DNS zones for name resolution
- Existing Azure subscription with proper quotas

## Module Structure

```
aml-managed-smi/
├── main.tf                 # Main Terraform configuration
├── variables.tf            # Variable definitions
├── outputs.tf              # Output definitions  
├── terraform.tfvars        # Configuration values
├── providers.tf            # Provider configuration
└── README.md              # This documentation
```
