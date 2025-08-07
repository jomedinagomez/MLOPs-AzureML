# Service Principal Deployment Guide

This guide explains how to use the Terraform-managed service principal for automated Azure ML platform deployment.

## Overview

The Terraform configuration automatically creates a service principal with the exact permissions required by the deployment strategy:

- **Contributor** role on all 6 resource groups
- **User Access Administrator** role on all 6 resource groups  
- **Network Contributor** role on all 6 resource groups

## Initial Setup (One-Time)

### 1. Deploy with Service Principal Creation

First deployment creates the infrastructure AND the service principal:

```bash
# Deploy infrastructure with service principal creation
terraform init
terraform plan -var="purpose=dev"
terraform apply -var="purpose=dev"
```

### 2. Retrieve Service Principal Credentials

After successful deployment, get the service principal credentials:

```bash
# Get service principal information (sensitive outputs)
terraform output -json service_principal_auth_instructions
terraform output service_principal_secret

# Save these values securely - you'll need them for CI/CD
export ARM_CLIENT_ID=$(terraform output -raw service_principal_application_id)
export ARM_CLIENT_SECRET=$(terraform output -raw service_principal_secret)
export ARM_TENANT_ID=$(terraform output -json service_principal_auth_instructions | jq -r '.tenant_id')
export ARM_SUBSCRIPTION_ID=$(terraform output -json service_principal_auth_instructions | jq -r '.subscription_id')
```

## CI/CD Pipeline Setup

### GitHub Actions Example

Create `.github/workflows/deploy-infrastructure.yml`:

```yaml
name: Deploy Azure ML Infrastructure

on:
  push:
    branches: [main]
    paths: ['infra/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v3
      with:
        terraform_version: 1.5.0
    
    - name: Configure Azure Credentials
      env:
        ARM_CLIENT_ID: ${{ secrets.ARM_CLIENT_ID }}
        ARM_CLIENT_SECRET: ${{ secrets.ARM_CLIENT_SECRET }}
        ARM_SUBSCRIPTION_ID: ${{ secrets.ARM_SUBSCRIPTION_ID }}
        ARM_TENANT_ID: ${{ secrets.ARM_TENANT_ID }}
      run: |
        echo "Azure credentials configured"
    
    - name: Terraform Init
      run: terraform init
      working-directory: ./infra
    
    - name: Terraform Plan
      run: terraform plan -var-file="environments/dev.tfvars"
      working-directory: ./infra
      env:
        ARM_CLIENT_ID: ${{ secrets.ARM_CLIENT_ID }}
        ARM_CLIENT_SECRET: ${{ secrets.ARM_CLIENT_SECRET }}
        ARM_SUBSCRIPTION_ID: ${{ secrets.ARM_SUBSCRIPTION_ID }}
        ARM_TENANT_ID: ${{ secrets.ARM_TENANT_ID }}
    
    - name: Terraform Apply
      run: terraform apply -auto-approve -var-file="environments/dev.tfvars"
      working-directory: ./infra
      env:
        ARM_CLIENT_ID: ${{ secrets.ARM_CLIENT_ID }}
        ARM_CLIENT_SECRET: ${{ secrets.ARM_CLIENT_SECRET }}
        ARM_SUBSCRIPTION_ID: ${{ secrets.ARM_SUBSCRIPTION_ID }}
        ARM_TENANT_ID: ${{ secrets.ARM_TENANT_ID }}
```

### Azure DevOps Example

Create `azure-pipelines.yml`:

```yaml
trigger:
  branches:
    include:
    - main
  paths:
    include:
    - infra/*

pool:
  vmImage: 'ubuntu-latest'

variables:
- group: azure-ml-infrastructure # Variable group with service principal secrets

stages:
- stage: Deploy
  jobs:
  - job: DeployInfrastructure
    steps:
    - task: TerraformInstaller@0
      displayName: 'Install Terraform'
      inputs:
        terraformVersion: '1.5.0'
    
    - task: TerraformTaskV4@4
      displayName: 'Terraform Init'
      inputs:
        provider: 'azurerm'
        command: 'init'
        workingDirectory: '$(System.DefaultWorkingDirectory)/infra'
        backendServiceArm: 'azure-ml-service-connection'
    
    - task: TerraformTaskV4@4
      displayName: 'Terraform Plan'
      inputs:
        provider: 'azurerm'
        command: 'plan'
        workingDirectory: '$(System.DefaultWorkingDirectory)/infra'
        commandOptions: '-var-file="environments/dev.tfvars"'
        environmentServiceNameAzureRM: 'azure-ml-service-connection'
    
    - task: TerraformTaskV4@4
      displayName: 'Terraform Apply'
      inputs:
        provider: 'azurerm'
        command: 'apply'
        workingDirectory: '$(System.DefaultWorkingDirectory)/infra'
        commandOptions: '-var-file="environments/dev.tfvars" -auto-approve'
        environmentServiceNameAzureRM: 'azure-ml-service-connection'
```

## Environment-Specific Deployment

### Development Environment

Create `environments/dev.tfvars`:

```hcl
# Core Configuration
purpose = "dev"
location = "canadacentral"
location_code = "cc"
random_string = "01"

# Network Configuration  
vnet_address_space = "10.1.0.0/16"
subnet_address_prefix = "10.1.1.0/24"

# Environment-Specific Settings
enable_auto_purge = true
create_service_principal = true

# Tags
tags = {
  environment = "dev"
  project     = "ml-platform"
  created_by  = "terraform"
  cost_center = "development"
}

# Cross-environment RBAC (leave disabled for dev)
enable_cross_env_rbac = false
```

### Production Environment

Create `environments/prod.tfvars`:

```hcl
# Core Configuration
purpose = "prod"
location = "canadacentral"
location_code = "cc"
random_string = "01"

# Network Configuration
vnet_address_space = "10.2.0.0/16"
subnet_address_prefix = "10.2.1.0/24"

# Environment-Specific Settings
enable_auto_purge = false
create_service_principal = true

# Tags
tags = {
  environment = "prod"
  project     = "ml-platform"
  created_by  = "terraform"
  cost_center = "production"
}

# Cross-environment RBAC (enable for asset promotion)
enable_cross_env_rbac = true
cross_env_registry_resource_group = "rg-aml-reg-dev-cc01"
cross_env_registry_name = "amlrdevcc01"
cross_env_workspace_principal_id = "dev-workspace-principal-id-here"
```

## Service Principal Management

### Rotating Secrets

The service principal secret expires every 2 years by default. To rotate:

```bash
# Plan secret rotation
terraform plan -var="service_principal_secret_expiry_hours=17520"

# Apply to create new secret (old one remains valid until expiry)
terraform apply -var="service_principal_secret_expiry_hours=17520"

# Get new secret
terraform output service_principal_secret

# Update CI/CD pipeline secrets with new value
```

### Disabling Service Principal Creation

For manual service principal management:

```bash
terraform apply -var="create_service_principal=false"
```

### Service Principal Permissions Verification

The created service principal has these permissions per the deployment strategy:

```bash
# List role assignments for the service principal
az role assignment list --assignee $(terraform output -raw service_principal_id) --output table

# Expected roles (3 per resource group × 6 resource groups = 18 total):
# - Contributor on rg-aml-vnet-{purpose}-cc01
# - User Access Administrator on rg-aml-vnet-{purpose}-cc01  
# - Network Contributor on rg-aml-vnet-{purpose}-cc01
# - Contributor on rg-aml-ws-{purpose}-cc01
# - User Access Administrator on rg-aml-ws-{purpose}-cc01
# - Network Contributor on rg-aml-ws-{purpose}-cc01
# - Contributor on rg-aml-reg-{purpose}-cc01
# - User Access Administrator on rg-aml-reg-{purpose}-cc01
# - Network Contributor on rg-aml-reg-{purpose}-cc01
```

## Security Best Practices

### 1. Secret Management
- Store service principal secrets in secure key vaults
- Use CI/CD secret management (GitHub Secrets, Azure DevOps Variable Groups)
- Rotate secrets regularly (every 6-12 months)
- Monitor secret expiration dates

### 2. Access Control
- Limit service principal usage to CI/CD pipelines only
- Use dedicated service principals per environment
- Regularly audit role assignments
- Enable Azure AD sign-in logs monitoring

### 3. Network Security
- Deploy from secure CI/CD agents
- Use private endpoints where possible
- Monitor deployment activities

## Troubleshooting

### Common Issues

#### 1. Permission Denied During Deployment

```bash
# Check service principal permissions
az role assignment list --assignee $ARM_CLIENT_ID --output table

# Verify authentication
az login --service-principal -u $ARM_CLIENT_ID -p $ARM_CLIENT_SECRET --tenant $ARM_TENANT_ID
az account show
```

#### 2. Service Principal Not Created

```bash
# Check if variable is set correctly
terraform plan -var="create_service_principal=true"

# Verify Azure AD permissions of current user
az ad app list --display-name "sp-aml-deployment-*"
```

#### 3. Secret Expiry

```bash
# Check secret expiration
az ad app credential list --id $(terraform output -raw service_principal_application_id)

# Rotate secret
terraform apply -var="service_principal_secret_expiry_hours=17520"
```

## Deployment Workflow Summary

1. **Initial Setup**: Deploy with `create_service_principal=true`
2. **Extract Credentials**: Save service principal details securely
3. **Configure CI/CD**: Set up pipeline with service principal authentication
4. **Deploy Environments**: Use environment-specific tfvars files
5. **Maintain**: Rotate secrets and monitor permissions regularly

The service principal approach provides a secure, automated deployment pipeline that follows the principle of least privilege while enabling comprehensive infrastructure management.
