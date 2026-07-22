# Destroy Azure ML Infrastructure - Quick Guide

## Overview
This guide helps you safely destroy the Terraform-managed Azure ML infrastructure in the `infra_no_networking` folder.

## ⚠️ Important Warnings

- **This operation is DESTRUCTIVE and PERMANENT**
- All data in storage accounts will be deleted
- All models, experiments, and pipelines will be removed
- Key Vaults will be purged (if auto-purge is enabled)
- Service principals will be deleted

## Prerequisites

1. **Azure CLI** installed and authenticated
   ```powershell
   az login
   az account set --subscription "your-subscription-id"
   ```

2. **Terraform** installed (same version used for deployment)
   ```powershell
   terraform version
   ```

3. **Permissions**: You need Owner or Contributor role on the subscription

## Method 1: Automated Script (Recommended)

Run the automated destruction script from the repository root:

```powershell
cd c:\Users\jomedin\Documents\MLOPs-AzureML
.\destroy_infrastructure.ps1
```

The script will:
1. Verify infrastructure exists
2. Read your naming suffix from `terraform.tfvars`
3. Show you what will be destroyed
4. Ask for confirmation (type `DESTROY`)
5. Generate destroy plan
6. Execute destruction
7. Verify cleanup

**Estimated time**: 10-15 minutes

## Method 2: Manual Terraform Destroy

### Step-by-Step

1. **Navigate to infrastructure folder**
   ```powershell
   cd c:\Users\jomedin\Documents\MLOPs-AzureML\infra_no_networking
   ```

2. **Initialize Terraform (if needed)**
   ```powershell
   terraform init
   ```

3. **Review what will be destroyed**
   ```powershell
   terraform plan -destroy -var naming_suffix="01"
   ```

4. **Execute destruction**
   ```powershell
   terraform destroy -auto-approve -var naming_suffix="01"
   ```

   Replace `"01"` with your actual naming suffix from `terraform.tfvars`.

### What Happens During Destroy

The destroy process includes automatic cleanup hooks:

1. **Azure ML Workspaces**: Permanently deleted (not just soft-deleted)
   ```powershell
   az ml workspace delete --permanently-delete --yes
   ```

2. **Key Vaults**: Purged if `enable_auto_purge = true` (default)
   ```powershell
   az keyvault purge --name <kv-name>
   ```

3. **Storage Accounts**: Soft-deleted contents cleaned up
4. **Container Registries**: Repositories deleted
5. **Resource Groups**: All resource groups removed

## Verification After Destroy

### Check Resource Groups
```powershell
# Should return nothing
az group list --query "[?contains(name, '-01') && starts_with(name, 'rg-aml-')].name" -o table
```

### Check Workspaces
```powershell
# Should return empty
az ml workspace list --query "[?contains(name, 'aml')].name" -o table
```

### Check Azure Portal
1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to Resource Groups
3. Search for `rg-aml-` - should find nothing with your suffix

## Common Issues & Solutions

### Issue: "Resource is locked"
**Solution**: Remove locks manually first
```powershell
az lock list --resource-group <rg-name>
az lock delete --name <lock-name> --resource-group <rg-name>
```

### Issue: "Workspace soft-deleted, name in use"
**Solution**: Permanently delete soft-deleted workspace
```powershell
az ml workspace delete \
  --name <workspace-name> \
  --resource-group <rg-name> \
  --permanently-delete \
  --yes
```

### Issue: "Key Vault purge protection enabled"
**Solution**: Wait 90 days or manually purge with proper permissions
```powershell
# List soft-deleted vaults
az keyvault list-deleted

# Purge specific vault (if allowed)
az keyvault purge --name <kv-name> --location canadacentral
```

### Issue: "Terraform state out of sync"
**Solution**: Refresh state before destroy
```powershell
terraform refresh -var naming_suffix="01"
terraform destroy -var naming_suffix="01"
```

### Issue: "Some resources still exist after destroy"
**Solution**: Targeted destroy for stubborn resources
```powershell
# List resources in state
terraform state list

# Target specific resource
terraform destroy -target=<resource_address> -var naming_suffix="01"
```

## Selective Destruction

If you only want to destroy specific environments:

### Destroy only Dev environment
```powershell
terraform destroy \
  -target=module.dev_managed_umi \
  -target=module.dev_registry \
  -target=azurerm_resource_group.dev \
  -var naming_suffix="01"
```

### Destroy only Prod environment
```powershell
terraform destroy \
  -target=module.prod_managed_umi \
  -target=module.prod_registry \
  -target=azurerm_resource_group.prod \
  -var naming_suffix="01"
```

**⚠️ Warning**: Selective destruction may leave orphaned resources or broken dependencies.

## Manual Cleanup (Last Resort)

If Terraform destroy fails completely:

1. **Delete Resource Groups via Portal or CLI**
   ```powershell
   az group delete --name rg-aml-dev-cc-01 --yes --no-wait
   az group delete --name rg-aml-int-cc-01 --yes --no-wait
   az group delete --name rg-aml-prod-cc-01 --yes --no-wait
   ```

2. **Delete Service Principal**
   ```powershell
   # Find the service principal
   az ad sp list --display-name "sp-aml-deployment-platform" --query "[].{Name:displayName, AppId:appId, ObjectId:id}"
   
   # Delete it
   az ad sp delete --id <object-id>
   ```

3. **Purge Key Vaults**
   ```powershell
   az keyvault list-deleted
   az keyvault purge --name <kv-name> --location canadacentral
   ```

4. **Clean Terraform State**
   ```powershell
   rm terraform.tfstate*
   rm -r .terraform/
   ```

## Cost Savings (Alternative to Full Destroy)

If you want to keep infrastructure but reduce costs:

### Stop Compute Resources
```powershell
# Stop compute clusters (not delete)
az ml compute stop --name <compute-name> --workspace-name <workspace-name> --resource-group <rg-name>
```

### Scale Down
```powershell
# Update compute to min instances = 0
az ml compute update \
  --name <compute-name> \
  --min-instances 0 \
  --workspace-name <workspace-name> \
  --resource-group <rg-name>
```

## Before Redeploying

If you plan to deploy again with the same naming suffix:

1. **Verify complete cleanup**
   ```powershell
   az group list --query "[?contains(name, '-01')].name" -o table
   ```

2. **Check Key Vault purged**
   ```powershell
   az keyvault list-deleted --query "[?contains(name, 'kv')]"
   ```

3. **Wait for Azure propagation** (2-5 minutes)

4. **Re-run terraform init**
   ```powershell
   cd infra_no_networking
   terraform init -reconfigure
   ```

## Support & Documentation

- **Terraform State**: Located at `infra_no_networking/terraform.tfstate`
- **Configuration**: `infra_no_networking/terraform.tfvars`
- **Full Documentation**: `infra_no_networking/README.md`
- **Your Naming Suffix**: `01` (from terraform.tfvars)
- **Subscription**: `5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25`
- **Location**: `canadacentral`

## Quick Reference Commands

```powershell
# From repository root
cd c:\Users\jomedin\Documents\MLOPs-AzureML\infra_no_networking

# Show current infrastructure
terraform show

# Plan destroy
terraform plan -destroy -var naming_suffix="01"

# Execute destroy
terraform destroy -auto-approve -var naming_suffix="01"

# Verify cleanup
az group list --query "[?contains(name, '-01')].name" -o table
```

---

**Last Updated**: Based on your current deployment with naming suffix `01`
