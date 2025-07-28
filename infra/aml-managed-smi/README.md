# Azure ML Workspace Module Configuration Guide

This terraform.tfvars file contains the configuration for deploying an Azure ML workspace with managed virtual network.

## Required Customizations

Before deploying, you MUST update the following values:

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
- `location`: Azure region for resources
- `location_code`: Short code for the region (e.g., "eus" for East US)
- `purpose`: Environment identifier (e.g., "dev", "test", "prod")
- `random_string`: Unique identifier to ensure resource name uniqueness

### Tags
Customize the `tags` section to match your organization's tagging strategy.

## Deployment Commands

1. Initialize Terraform:
```bash
terraform init
```

2. Plan the deployment:
```bash
terraform plan
```

3. Apply the configuration:
```bash
terraform apply
```

## Resources Created

This module creates:
- Resource Group
- Log Analytics Workspace
- Application Insights
- Azure Container Registry
- Storage Account (with private endpoints)
- Key Vault (with private endpoints)
- Azure ML Workspace with managed VNet
- Private Endpoints for all services
- Required role assignments

## Prerequisites

- Azure CLI installed and authenticated
- Terraform installed
- Existing VNet and subnet for private endpoints
- Private DNS zones configured and linked to your VNet
- Appropriate Azure RBAC permissions to create resources
