# Azure ML Platform Deployment Instructions

This guide provides step-by-step instructions for deploying the Azure ML platform using the Terraform-managed service principal approach.

## 🚀 Quick Start

### Prerequisites

1. **Azure CLI** installed and authenticated
2. **Terraform** v1.5+ installed
3. **Permissions** to create service principals in Azure AD
4. **Subscription** with sufficient quota for Azure ML resources

### One-Command Development Deployment

```bash
# Clone and deploy development environment
git clone <repository-url>
cd MLOPs-AzureML/infra
terraform init
terraform apply -var-file="environments/dev.tfvars" -auto-approve
```

## 📋 Step-by-Step Deployment

### Step 1: Initialize Terraform

```bash
cd infra
terraform init
```

### Step 2: Deploy Development Environment

```bash
# Plan the deployment
terraform plan -var-file="environments/dev.tfvars"

# Apply the deployment
terraform apply -var-file="environments/dev.tfvars"
```

**What gets created:**
- 3 resource groups for dev environment
- Service principal with proper RBAC permissions
- VNet, subnet, and private DNS zones
- Azure ML workspace with managed identity
- Azure ML registry with system-assigned identity
- Storage account, Key Vault, Container Registry
- All required private endpoints and RBAC assignments

### Step 3: Extract Service Principal Credentials

```bash
# Get service principal credentials for CI/CD
terraform output service_principal_application_id
terraform output service_principal_secret
terraform output -json service_principal_auth_instructions

# Save these values securely for CI/CD pipeline setup
```

### Step 4: Update Production Variables (Optional)

If deploying production, update cross-environment values in `environments/prod.tfvars`:

```bash
# Get dev environment outputs
DEV_REGISTRY_RG=$(terraform output resource_group_name_registry)
DEV_REGISTRY_NAME=$(terraform output registry_name)
DEV_WORKSPACE_PRINCIPAL=$(terraform output workspace_principal_id)

# Update prod.tfvars with these values
```

### Step 5: Deploy Production Environment (Optional)

```bash
# Deploy production with cross-environment access
terraform apply -var-file="environments/prod.tfvars"
```

## Configuration Options

### Environment Variables

Set these for automated deployments:

```bash
export ARM_CLIENT_ID="<service-principal-app-id>"
export ARM_CLIENT_SECRET="<service-principal-secret>"
export ARM_TENANT_ID="<your-tenant-id>"
export ARM_SUBSCRIPTION_ID="<your-subscription-id>"
```

### Customization Variables

Key variables you can modify in `.tfvars` files:

| Variable | Description | Dev Default | Prod Default |
|----------|-------------|-------------|--------------|
| `purpose` | Environment name | `"dev"` | `"prod"` |
| `vnet_address_space` | VNet CIDR | `"10.1.0.0/16"` | `"10.2.0.0/16"` |
| `enable_auto_purge` | Key Vault purge | `true` | `false` |
| `enable_cross_env_rbac` | Cross-env access | `false` | `true` |

## Resource Overview

### Development Environment (18 resources)

```
rg-aml-vnet-dev-cc01/
├── vnet-amldevcc01 (VNet)
├── subnet-amldevcc01 (Subnet)
├── dev-mi-compute (User-Assigned Identity)
├── dev-mi-endpoint (User-Assigned Identity)
├── 8x Private DNS Zones
└── Log Analytics Workspace

rg-aml-ws-dev-cc01/
├── amlwdevcc01 (ML Workspace)
├── stamldevcc01 (Storage Account)
├── acrdevcc01 (Container Registry)
├── kvdevcc01 (Key Vault)
├── dev-mi-workspace (User-Assigned Identity)
└── 6x Private Endpoints

rg-aml-reg-dev-cc01/
├── amlrdevcc01 (ML Registry)
├── 1x Private Endpoint
└── System-Assigned Identity (automatic)
```

### Service Principal Permissions (18 role assignments)

```
Per Resource Group (3 roles × 6 RGs = 18 total):
├── Contributor (deploy resources)
├── User Access Administrator (configure RBAC)
└── Network Contributor (configure networking)
```

## 🔒 Security Features

### Network Security
- Private endpoints for all services
- Managed VNet with outbound rules
- Complete network isolation between environments
- Private DNS resolution

### Identity & Access Management
- User-assigned identities for workspaces and compute
- System-assigned identity for registries
- Least-privilege RBAC assignments
- Cross-environment read-only access (prod → dev)

### Data Protection
- Storage account network restrictions
- Key Vault with access policies
- Container registry private access
- Automatic secret rotation support

## Troubleshooting

### Common Issues

#### 1. Service Principal Creation Failed
```bash
# Check Azure AD permissions
az ad app list --display-name "sp-aml-deployment-*"

# Verify you have Application Administrator role
az role assignment list --assignee $(az account show --query user.name -o tsv)
```

#### 2. Resource Group Already Exists
```bash
# Check existing resources
az group list --query "[?starts_with(name, 'rg-aml-')]"

# If needed, import existing resource group
terraform import azurerm_resource_group.aml_vnet_rg /subscriptions/{sub-id}/resourceGroups/{rg-name}
```

#### 3. Quota Exceeded
```bash
# Check ML workspace quota
az ml quota list --location canadacentral

# Request quota increase if needed
az support tickets create \
  --ticket-name "Azure ML Quota Increase" \
  --issue-type "quota" \
  --severity "minimal"
```

#### 4. Permission Denied During Deployment
```bash
# Verify service principal authentication
az login --service-principal \
  -u $ARM_CLIENT_ID \
  -p $ARM_CLIENT_SECRET \
  --tenant $ARM_TENANT_ID

# Check role assignments
az role assignment list --assignee $ARM_CLIENT_ID --output table
```

## 📈 Post-Deployment Validation

### Verify Development Environment

```bash
# Check workspace status
az ml workspace show --name amlwdevcc01 --resource-group rg-aml-ws-dev-cc01

# Check registry status  
az ml registry show --name amlrdevcc01 --resource-group rg-aml-reg-dev-cc01

# Test connectivity
az ml compute list --workspace-name amlwdevcc01 --resource-group rg-aml-ws-dev-cc01
```

### Verify Service Principal

```bash
# List all role assignments
terraform output service_principal_id | xargs az role assignment list --assignee

# Test authentication
az login --service-principal \
  -u $(terraform output -raw service_principal_application_id) \
  -p $(terraform output -raw service_principal_secret) \
  --tenant $(terraform output -json service_principal_auth_instructions | jq -r '.tenant_id')
```

## 🔄 Maintenance

### Regular Tasks

1. **Monitor Secret Expiry** (every 6 months)
   ```bash
   terraform output -json service_principal_auth_instructions
   az ad app credential list --id $(terraform output -raw service_principal_application_id)
   ```

2. **Review RBAC Assignments** (quarterly)
   ```bash
   az role assignment list --assignee $(terraform output -raw service_principal_id) --output table
   ```

3. **Update Dependencies** (monthly)
   ```bash
   terraform providers lock -platform=windows_amd64 -platform=darwin_amd64 -platform=linux_amd64
   ```

### Scaling Considerations

- **Multiple Environments**: Create additional `.tfvars` files for test, staging, etc.
- **Multiple Regions**: Duplicate infrastructure in different Azure regions
- **Shared Services**: Consider separate Terraform state for shared resources

## 📚 Next Steps

After successful deployment:

1. **Set up CI/CD pipelines** using the service principal credentials
2. **Configure cross-environment promotion** between dev and prod
3. **Deploy ML models and pipelines** to test the infrastructure
4. **Set up monitoring and alerting** for the infrastructure
5. **Implement backup and disaster recovery** procedures

## 📞 Support

For issues or questions:
- Check [SERVICE_PRINCIPAL_GUIDE.md](./SERVICE_PRINCIPAL_GUIDE.md) for detailed CI/CD setup
- Review [DeploymentStrategy.md](../DeploymentStrategy.md) for architecture details
- Create GitHub issues for infrastructure problems
- Contact the ML platform team for operational support
