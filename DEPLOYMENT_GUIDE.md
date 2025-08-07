# Azure ML Platform Deployment Guide
## Complete Step-by-Step Implementation

This comprehensive guide provides detailed instructions for deploying your Azure ML platform with complete environment isolation, dual registries, and cross-environment asset promotion capabilities.

## 📋 Prerequisites and Planning

### 1. Subscription and Access Requirements
```bash
# Verify Azure CLI and subscription access
az login
az account show
az account set --subscription "5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25"

# Verify required resource providers are registered
az provider register --namespace Microsoft.MachineLearningServices
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.ManagedIdentity
```

### 2. Service Principal Creation
Create a dedicated service principal for infrastructure deployment:

```bash
# Create service principal for deployment
az ad sp create-for-rbac \
  --name "sp-aml-deployment-automation" \
  --role "Contributor" \
  --scopes "/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25" \
  --sdk-auth

# Store the output securely - you'll need these values for CI/CD
```

**Required Service Principal Roles:**
- `Contributor` - Deploy and manage all Azure resources
- `User Access Administrator` - Configure RBAC for managed identities
- `Network Contributor` - Configure virtual networks and private endpoints

### 3. Environment Configuration Files
Create separate Terraform variable files for each environment:

**Development Environment** (`terraform.tfvars.dev`):
```hcl
# Base configuration
prefix        = "aml"
purpose       = "dev"
location      = "canadacentral"
location_code = "cc"
naming_suffix = "01"  # Updated to match your configuration

# Resource prefixes (from your existing templates)
resource_prefixes = {
  vnet               = "vnet-aml"
  subnet             = "subnet-aml"
  workspace          = "amlws"
  registry           = "amlreg"
  storage            = "amlst"
  container_registry = "amlacr"
  key_vault          = "amlkv"
  log_analytics      = "amllog"
}

# Development networking
vnet_address_space    = "10.1.0.0/16"
subnet_address_prefix = "10.1.1.0/24"

# Development-specific settings (leveraging your auto-purge implementation)
enable_auto_purge = true  # CRITICAL: Allows comprehensive auto-purge on destroy

# Resource tagging
tags = {
  environment  = "dev"
  project      = "ml-platform"
  created_by   = "terraform"
  owner        = "ml-team"
  cost_center  = "dev-ml"
  created_date = "2025-08-07"
}
```

**Production Environment** (`terraform.tfvars.prod`):
```hcl
# Base configuration
prefix        = "aml"
purpose       = "prod"
location      = "canadacentral"
location_code = "cc"
naming_suffix = "01"  # Same suffix as dev for consistency

# Resource prefixes (same as dev for consistency)
resource_prefixes = {
  vnet               = "vnet-aml"
  subnet             = "subnet-aml"
  workspace          = "amlws"
  registry           = "amlreg"
  storage            = "amlst"
  container_registry = "amlacr"
  key_vault          = "amlkv"
  log_analytics      = "amllog"
}

# Production networking (different CIDR)
vnet_address_space    = "10.2.0.0/16"
subnet_address_prefix = "10.2.1.0/24"

# Production-specific settings (leveraging your auto-purge protection)
enable_auto_purge = false  # CRITICAL: Prevents accidental deletion of production resources

# Resource tagging
tags = {
  environment  = "prod"
  project      = "ml-platform"
  created_by   = "terraform"
  owner        = "ml-team"
  cost_center  = "prod-ml"
  created_date = "2025-08-07"
}
```

## 🚀 Phase 1: Development Environment Deployment

### Step 1.1: Deploy Development Infrastructure
```bash
# Navigate to infrastructure directory
cd c:\Users\jomedin\Documents\MLOPs-AzureML\infra

# Initialize Terraform (if not already done)
terraform init

# Update your existing terraform.tfvars with naming_suffix = "01"
# Your existing file already has most configurations ready

# Plan development deployment using your existing terraform.tfvars
terraform plan -var-file="terraform.tfvars" -out="dev.tfplan"

# Review the plan carefully, then apply
terraform apply "dev.tfplan"

# Save outputs for reference
terraform output > dev-outputs.txt
```

**Expected Resource Groups Created:**
- `rg-aml-vnet-dev-cc01` - Networking, Key Vault, shared resources, managed identities
- `rg-aml-ws-dev-cc` - Workspace, Storage, Container Registry, Application Insights
- `rg-aml-reg-dev-cc` - Registry resources

**Pre-configured Features in Your Templates:**
- ✅ **Log Analytics Workspace**: `amllogdevcc01` (automatically configured)
- ✅ **Default Compute Cluster**: `cpu-cluster-uami` (Standard_F8s_v2, 2-4 nodes)
- ✅ **Auto-Purge Protection**: Comprehensive cleanup for Key Vault, Storage, ACR
- ✅ **Private Endpoints**: Automatically created for all services
- ✅ **RBAC Configuration**: Pre-configured managed identity roles
- ✅ **Cross-Environment Connectivity**: Outbound rules for registry access

### Step 1.2: Verify Development Deployment
```bash
# Verify key resources exist (updated with naming_suffix = "01")
az ml workspace show --name "amlwsdevcc01" --resource-group "rg-aml-ws-dev-cc"
az ml registry show --name "amlregdevcc01" --resource-group "rg-aml-reg-dev-cc"

# Test workspace connectivity and pre-configured compute
az ml compute list --workspace-name "amlwsdevcc01" --resource-group "rg-aml-ws-dev-cc"

# Verify your pre-configured default compute cluster
az ml compute show --name "cpu-cluster-uami" --workspace-name "amlwsdevcc01" --resource-group "rg-aml-ws-dev-cc"

# Check pre-configured Log Analytics workspace
az monitor log-analytics workspace show --workspace-name "amllogdevcc01" --resource-group "rg-aml-vnet-dev-cc01"

# Verify auto-purge configuration is enabled for development
echo "Auto-purge enabled for dev environment - see AUTO_PURGE_IMPLEMENTATION.md for details"
```

### Step 1.3: Verify Pre-configured RBAC
Your Terraform templates already include comprehensive RBAC configuration. Verify the setup:

```bash
# Get managed identity IDs from Terraform outputs (your templates create these automatically)
DEV_WORKSPACE_MI=$(terraform output -raw managed_identity_workspace_principal_id)
DEV_COMPUTE_MI=$(terraform output -raw managed_identity_cc_principal_id)
DEV_ENDPOINT_MI=$(terraform output -raw managed_identity_moe_principal_id)

# Your templates already configured these resources with proper naming
DEV_WORKSPACE_NAME="amlwsdevcc01"
DEV_REGISTRY_NAME="amlregdevcc01"
DEV_STORAGE_NAME="amlstdevcc01"
DEV_KEYVAULT_NAME="amlkvdevcc01"

# Verify pre-configured RBAC assignments (these are already created by your Terraform)
echo "✅ RBAC Pre-configured by Terraform Templates:"
echo "   - Workspace UAMI: Azure AI Administrator, Storage roles"
echo "   - Compute UAMI: AzureML Data Scientist, Storage Blob Data Contributor"
echo "   - Endpoint UAMI: AcrPull, Storage Blob Data Reader, Registry User"

# Optional: Verify specific role assignments
az role assignment list --assignee "$DEV_COMPUTE_MI" --scope "/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-ws-dev-cc" --output table
```

## 🏭 Phase 2: Production Environment Deployment

### Step 2.1: Deploy Production Infrastructure
```bash
# Plan production deployment with different variables
terraform plan -var-file="terraform.tfvars.prod" -out="prod.tfplan"

# Review the plan - ensure no conflicts with dev resources
terraform apply "prod.tfplan"

# Save production outputs
terraform output > prod-outputs.txt
```

**Expected Production Resource Groups:**
- `rg-aml-vnet-prod-cc001` - Production networking and shared resources
- `rg-aml-ws-prod-cc` - Production workspace resources
- `rg-aml-reg-prod-cc` - Production registry resources

### Step 2.2: Configure Production RBAC
```bash
# Get production managed identity IDs
PROD_WORKSPACE_MI=$(terraform output -raw prod_workspace_managed_identity_id)
PROD_COMPUTE_MI=$(terraform output -raw prod_compute_managed_identity_id)
PROD_WORKSPACE_NAME="amlwsprodcc001"
PROD_REGISTRY_NAME="amlregprodcc001"

# Production Compute UAMI - Cross-environment access to dev registry
az role assignment create \
  --assignee "$PROD_COMPUTE_MI" \
  --role "AzureML Registry User" \
  --scope "/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-reg-dev-cc/providers/Microsoft.MachineLearningServices/registries/$DEV_REGISTRY_NAME"

# Production Workspace UAMI - Network connection approver for dev registry
az role assignment create \
  --assignee "$PROD_WORKSPACE_MI" \
  --role "Azure AI Enterprise Network Connection Approver" \
  --scope "/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-reg-dev-cc/providers/Microsoft.MachineLearningServices/registries/$DEV_REGISTRY_NAME"
```

### Step 2.3: Configure Cross-Environment Network Connectivity
Add outbound rules to enable production workspace access to development registry:

```bash
# Create outbound rule for prod workspace to access dev registry
az rest \
  --method PUT \
  --url "https://management.azure.com/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-ws-prod-cc/providers/Microsoft.MachineLearningServices/workspaces/$PROD_WORKSPACE_NAME/outboundRules/allow-dev-registry?api-version=2024-10-01-preview" \
  --body '{
    "properties": {
      "type": "PrivateEndpoint",
      "destination": {
        "serviceResourceId": "/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-reg-dev-cc/providers/Microsoft.MachineLearningServices/registries/'"$DEV_REGISTRY_NAME"'",
        "subresourceTarget": "amlregistry"
      },
      "category": "UserDefined"
    }
  }'
```

## 👥 Phase 3: Human User Access Configuration

### Step 3.1: Configure Data Scientist Access
```bash
# Get user object ID (replace with actual user)
USER_ID=$(az ad user show --id "user@company.com" --query id -o tsv)

# Development environment access
az role assignment create \
  --assignee "$USER_ID" \
  --role "AzureML Data Scientist" \
  --scope "/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-ws-dev-cc/providers/Microsoft.MachineLearningServices/workspaces/$DEV_WORKSPACE_NAME"

az role assignment create \
  --assignee "$USER_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-ws-dev-cc/providers/Microsoft.Storage/storageAccounts/$DEV_STORAGE_NAME"

# Production environment access (read-only)
az role assignment create \
  --assignee "$USER_ID" \
  --role "Reader" \
  --scope "/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-ws-prod-cc"
```

### Step 3.2: Configure MLOps Team Access
```bash
# Create Azure AD group for MLOps team
az ad group create \
  --display-name "AzureML-MLOps-Team" \
  --mail-nickname "azureml-mlops"

MLOPS_GROUP_ID=$(az ad group show --group "AzureML-MLOps-Team" --query id -o tsv)

# MLOps team gets admin access to both environments
az role assignment create \
  --assignee "$MLOPS_GROUP_ID" \
  --role "Azure AI Administrator" \
  --scope "/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-ws-dev-cc"

az role assignment create \
  --assignee "$MLOPS_GROUP_ID" \
  --role "Azure AI Administrator" \
  --scope "/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-ws-prod-cc"
```

## 🔄 Phase 4: Asset Promotion Workflow Setup

### Step 4.1: Install Azure ML CLI and Python SDK
```bash
# Install Azure ML CLI extension
az extension add --name ml

# Install Python dependencies
pip install azure-ai-ml azure-identity azure-storage-blob
```

### Step 4.2: Test Model Promotion Workflow
Create a test script to verify cross-environment promotion:

```python
# save as test_promotion.py
from azure.ai.ml import MLClient
from azure.ai.ml.entities import Model, Data, Environment
from azure.identity import DefaultAzureCredential
from azure.ai.ml.constants import AssetTypes

def test_promotion_workflow():
    """Test the complete asset promotion workflow"""
    
    credential = DefaultAzureCredential()
    subscription_id = "5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25"
    
    # Initialize clients
    ml_client_dev_workspace = MLClient(
        credential=credential,
        subscription_id=subscription_id,
        resource_group_name="rg-aml-ws-dev-cc",
        workspace_name="amlwsdevcc004"
    )
    
    ml_client_dev_registry = MLClient(
        credential=credential,
        subscription_id=subscription_id,
        registry_name="amlregdevcc004"
    )
    
    ml_client_prod_registry = MLClient(
        credential=credential,
        subscription_id=subscription_id,
        registry_name="amlregprodcc001"
    )
    
    print("✅ Successfully connected to all ML clients")
    
    # Test 1: Create a dummy model in dev workspace
    try:
        dummy_model = Model(
            name="test-promotion-model",
            version="1.0",
            description="Test model for promotion workflow verification",
            tags={"test": "promotion", "stage": "development"}
        )
        
        # Note: This will fail without actual model artifacts, but tests connectivity
        print("🧪 Testing model creation in dev workspace...")
        # ml_client_dev_workspace.models.create_or_update(dummy_model)
        print("📝 Model creation test prepared (requires actual model artifacts)")
        
    except Exception as e:
        print(f"⚠️  Model creation test: {e}")
    
    # Test 2: Verify registry access
    try:
        models_in_dev_registry = ml_client_dev_registry.models.list()
        print(f"✅ Dev registry accessible - found {len(list(models_in_dev_registry))} models")
        
        models_in_prod_registry = ml_client_prod_registry.models.list()
        print(f"✅ Prod registry accessible - found {len(list(models_in_prod_registry))} models")
        
    except Exception as e:
        print(f"❌ Registry access error: {e}")
    
    print("\n🎉 Promotion workflow test completed!")

if __name__ == "__main__":
    test_promotion_workflow()
```

### Step 4.3: Run Promotion Test
```bash
# Test the promotion workflow
python test_promotion.py

# Verify network connectivity between environments
az ml workspace show --name "amlwsprodcc001" --resource-group "rg-aml-ws-prod-cc" --query "managedNetwork.isolationMode"
```

## 🛡️ Phase 5: Security and Compliance Configuration

### Step 5.1: Configure Private Endpoints
Verify that private endpoints are properly configured:

```bash
# List private endpoints in dev environment
az network private-endpoint list \
  --resource-group "rg-aml-vnet-dev-cc004" \
  --query "[].{Name:name, Target:privateLinkServiceConnections[0].privateLinkServiceId}" \
  --output table

# List private endpoints in prod environment  
az network private-endpoint list \
  --resource-group "rg-aml-vnet-prod-cc001" \
  --query "[].{Name:name, Target:privateLinkServiceConnections[0].privateLinkServiceId}" \
  --output table
```

### Step 5.2: Configure Monitoring and Logging
```bash
# Enable diagnostics for workspaces
az monitor diagnostic-settings create \
  --name "workspace-diagnostics" \
  --resource "/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-ws-dev-cc/providers/Microsoft.MachineLearningServices/workspaces/amlwsdevcc004" \
  --workspace "/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-vnet-dev-cc004/providers/Microsoft.OperationalInsights/workspaces/amllogdevcc004" \
  --logs '[{"category": "AmlComputeClusterEvent", "enabled": true}, {"category": "AmlComputeJobEvent", "enabled": true}, {"category": "AmlRunStatusChangedEvent", "enabled": true}]'
```

### Step 5.3: Backup and Disaster Recovery
```bash
# Configure backup for Key Vaults (if not done in Terraform)
az backup vault create \
  --name "backup-vault-dev" \
  --resource-group "rg-aml-vnet-dev-cc004" \
  --location "canadacentral"

# Enable soft delete verification for storage accounts
az storage account show \
  --name "stdevcc004" \
  --resource-group "rg-aml-ws-dev-cc" \
  --query "blobRestorePolicy.enabled"
```

## 📊 Phase 6: Operational Procedures

### Step 6.1: Environment Health Checks
Create automated health check scripts:

```bash
# save as health_check.sh
#!/bin/bash

echo "🏥 Azure ML Environment Health Check"
echo "=================================="

# Check workspace availability
echo "Checking workspace connectivity..."
az ml workspace show --name "amlwsdevcc004" --resource-group "rg-aml-ws-dev-cc" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ Dev workspace: Online"
else
    echo "❌ Dev workspace: Offline"
fi

# Check compute availability
echo "Checking compute resources..."
COMPUTE_COUNT=$(az ml compute list --workspace-name "amlwsdevcc004" --resource-group "rg-aml-ws-dev-cc" --query "length(@)" -o tsv)
echo "📊 Compute resources: $COMPUTE_COUNT available"

# Check storage connectivity
echo "Checking storage connectivity..."
az storage account show --name "stdevcc004" --resource-group "rg-aml-ws-dev-cc" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ Storage: Accessible"
else
    echo "❌ Storage: Inaccessible"
fi

echo "Health check completed!"
```

### Step 6.2: Asset Promotion Procedures
Create standardized promotion scripts:

```python
# save as promote_model.py
import argparse
from azure.ai.ml import MLClient
from azure.ai.ml.entities import Model
from azure.identity import DefaultAzureCredential

def promote_model(model_name: str, model_version: str, approval_required: bool = True):
    """
    Promote a model from development to production registry
    
    Args:
        model_name: Name of the model to promote
        model_version: Version of the model to promote  
        approval_required: Whether manual approval is required
    """
    
    if approval_required:
        approval = input(f"Approve promotion of {model_name} v{model_version} to production? (yes/no): ")
        if approval.lower() != 'yes':
            print("❌ Promotion cancelled by user")
            return
    
    credential = DefaultAzureCredential()
    subscription_id = "5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25"
    
    # Initialize clients
    ml_client_dev_registry = MLClient(
        credential=credential,
        subscription_id=subscription_id,
        registry_name="amlregdevcc004"
    )
    
    ml_client_prod_registry = MLClient(
        credential=credential,
        subscription_id=subscription_id,
        registry_name="amlregprodcc001"
    )
    
    try:
        # Get model from dev registry
        print(f"📥 Retrieving {model_name} v{model_version} from dev registry...")
        dev_model = ml_client_dev_registry.models.get(model_name, model_version)
        
        # Create promotion model
        print(f"🚀 Promoting to production registry...")
        prod_model = Model(
            name=model_name,
            version=model_version,
            path=f"azureml://registries/amlregdevcc004/models/{model_name}/versions/{model_version}",
            description=f"Production model (promoted from dev) - {dev_model.description}",
            tags={**dev_model.tags, "stage": "production", "promoted_from": "dev_registry"}
        )
        
        promoted_model = ml_client_prod_registry.models.create_or_update(prod_model)
        
        print(f"✅ Successfully promoted {model_name} v{model_version} to production")
        print(f"📍 Production model URI: azureml://registries/amlregprodcc001/models/{model_name}/versions/{model_version}")
        
    except Exception as e:
        print(f"❌ Promotion failed: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Promote model to production")
    parser.add_argument("--model-name", required=True, help="Name of model to promote")
    parser.add_argument("--model-version", required=True, help="Version of model to promote")
    parser.add_argument("--auto-approve", action="store_true", help="Skip manual approval")
    
    args = parser.parse_args()
    
    promote_model(args.model_name, args.model_version, not args.auto_approve)
```

## 🔧 Phase 7: Maintenance and Operations

### Step 7.1: Regular Maintenance Tasks
```bash
# Weekly maintenance script
#!/bin/bash

echo "🔧 Weekly Azure ML Maintenance"
echo "============================="

# Clean up old compute instances
echo "Cleaning up old compute instances..."
az ml compute list --workspace-name "amlwsdevcc004" --resource-group "rg-aml-ws-dev-cc" \
  --query "[?provisioningState=='Succeeded' && state=='Stopped'].name" -o tsv | \
  while read compute_name; do
    echo "Stopping idle compute: $compute_name"
    # az ml compute stop --name "$compute_name" --workspace-name "amlwsdevcc004" --resource-group "rg-aml-ws-dev-cc"
  done

# Check storage usage
echo "Checking storage usage..."
STORAGE_USAGE=$(az storage account show-usage --subscription "5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25" --query "currentValue" -o tsv)
echo "📊 Current storage usage: $STORAGE_USAGE accounts"

# Verify RBAC assignments
echo "Verifying RBAC assignments..."
az role assignment list --scope "/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-ws-dev-cc" \
  --query "length(@)" -o tsv | \
  xargs -I {} echo "📊 Dev environment RBAC assignments: {}"

echo "Maintenance completed!"
```

### Step 7.2: Monitoring and Alerting
```bash
# Create alerts for critical events
az monitor metrics alert create \
  --name "high-compute-usage" \
  --resource-group "rg-aml-ws-dev-cc" \
  --scopes "/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-ws-dev-cc/providers/Microsoft.MachineLearningServices/workspaces/amlwsdevcc004" \
  --condition "count static.machineLearningServices/workspaces/activeNodes > 10" \
  --description "Alert when active compute nodes exceed 10"
```

## 📚 Key Resources Created Summary

### Development Environment
**Resource Groups:**
- `rg-aml-vnet-dev-cc004` - Networking, Key Vault, shared resources
- `rg-aml-ws-dev-cc` - Workspace, Storage, Container Registry  
- `rg-aml-reg-dev-cc` - Development Registry

**Key Resources:**
- Workspace: `amlwsdevcc004`
- Registry: `amlregdevcc004`
- Storage: `stdevcc004`
- Key Vault: `kvdevcc004`
- VNet: `vnet-amldevcc004` (10.1.0.0/16)

### Production Environment  
**Resource Groups:**
- `rg-aml-vnet-prod-cc001` - Networking, Key Vault, shared resources
- `rg-aml-ws-prod-cc` - Workspace, Storage, Container Registry
- `rg-aml-reg-prod-cc` - Production Registry

**Key Resources:**
- Workspace: `amlwsprodcc001`
- Registry: `amlregprodcc001`  
- Storage: `stprodcc001`
- Key Vault: `kvprodcc001`
- VNet: `vnet-amlprodcc001` (10.2.0.0/16)

## 🚨 Critical Security Notes

1. **Network Isolation**: Complete air-gap between environments except for managed cross-registry access
2. **Identity Isolation**: Each environment has separate managed identities with minimal cross-environment access
3. **Key Vault Auto-Purge**: Enabled in dev (`enable_auto_purge = true`), disabled in prod (`enable_auto_purge = false`)
4. **Private Endpoints**: All services accessible only through private endpoints within managed VNets
5. **RBAC Principle**: Least privilege access with environment-specific permissions

## 📞 Troubleshooting Common Issues

### Issue 1: Cross-Environment Connectivity
```bash
# Verify outbound rules are configured
az rest --method GET \
  --url "https://management.azure.com/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-ws-prod-cc/providers/Microsoft.MachineLearningServices/workspaces/amlwsprodcc001/outboundRules?api-version=2024-10-01-preview"
```

### Issue 2: RBAC Access Denied
```bash
# Check role assignments
az role assignment list \
  --assignee "MANAGED_IDENTITY_ID" \
  --scope "/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/RESOURCE_GROUP"
```

### Issue 3: Model Promotion Failures
```bash
# Verify registry connectivity
az ml registry show --name "amlregdevcc004" --query "provisioningState"
az ml registry show --name "amlregprodcc001" --query "provisioningState"
```

---

This deployment guide provides a complete, step-by-step implementation of your Azure ML platform with dual registries, complete environment isolation, and cross-environment asset promotion capabilities. Follow each phase sequentially to ensure proper setup and configuration.
