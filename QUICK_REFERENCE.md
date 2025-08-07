# Azure ML Platform - Quick Reference Guide

## 🚀 Quick Start Commands

### Initial Deployment
```powershell
# Terraform (recommended): deploy dev + prod + hub in one run
cd .\infra
terraform init
terraform apply
```

### Verification Commands
```bash
# Check workspace connectivity
az ml workspace show --name "amlwsdevcc01" --resource-group "rg-aml-ws-dev-cc"
az ml workspace show --name "amlwsprodcc01" --resource-group "rg-aml-ws-prod-cc"

# Check registry connectivity
az ml registry show --name "amlregdevcc01" --resource-group "rg-aml-reg-dev-cc"
az ml registry show --name "amlregprodcc01" --resource-group "rg-aml-reg-prod-cc"

# Test cross-environment connectivity
python test_promotion_connectivity.py

# Check pre-configured logging
az monitor log-analytics workspace show --workspace-name "amllogdevcc01" --resource-group "rg-aml-vnet-dev-cc01"
az monitor log-analytics workspace show --workspace-name "amllogprodcc01" --resource-group "rg-aml-vnet-prod-cc01"

# Verify default compute clusters for image creation
az ml compute show --name "cpu-cluster" --workspace-name "amlwsdevcc01" --resource-group "rg-aml-ws-dev-cc"
az ml compute show --name "cpu-cluster" --workspace-name "amlwsprodcc01" --resource-group "rg-aml-ws-prod-cc"
```

## 📋 Resource Reference

### Development Environment Resources
```
Resource Groups:
├── rg-aml-vnet-dev-cc01     # Networking & shared resources
├── rg-aml-ws-dev-cc         # Workspace & associated services
└── rg-aml-reg-dev-cc        # Registry

Key Resources:
├── Workspace: amlwsdevcc01
├── Registry: amlregdevcc01
├── Storage: stdevcc01
├── Key Vault: kvdevcc01
├── Container Registry: acrdevcc01
├── VNet: vnet-amldevcc01 (10.1.0.0/16)
├── Log Analytics: amllogdevcc01 (pre-configured)
└── Default Compute: cpu-cluster (for image creation)
```

### Production Environment Resources
```
Resource Groups:
├── rg-aml-vnet-prod-cc01    # Networking & shared resources
├── rg-aml-ws-prod-cc        # Workspace & associated services
└── rg-aml-reg-prod-cc       # Registry

Key Resources:
├── Workspace: amlwsprodcc01
├── Registry: amlregprodcc01
├── Storage: stprodcc01
├── Key Vault: kvprodcc01 (auto-purge protection)
├── Container Registry: acrprodcc01
├── VNet: vnet-amlprodcc01 (10.2.0.0/16)
├── Log Analytics: amllogprodcc01 (pre-configured)
└── Default Compute: cpu-cluster (for image creation)
```

## 🔄 Common Operations

### Model Promotion Workflow
```python
# 1. Register model in dev workspace
from azure.ai.ml import MLClient
from azure.ai.ml.entities import Model
from azure.identity import DefaultAzureCredential

credential = DefaultAzureCredential()

# Development workspace client
ml_client_dev_ws = MLClient(
    credential=credential,
    subscription_id="5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25",
    resource_group_name="rg-aml-ws-dev-cc",
    workspace_name="amlwsdevcc01"
)

# Register model in dev workspace
model = Model(
    name="taxi-fare-model",
    version="1.0",
    path="azureml://jobs/{job-id}/outputs/model",
    description="Taxi fare prediction model"
)
dev_model = ml_client_dev_ws.models.create_or_update(model)

# 2. Share to dev registry
shared_model = ml_client_dev_ws.models.share(
    name="taxi-fare-model",
    version="1.0",
    registry_name="amlregdevcc01"
)

# 3. Promote to prod registry
ml_client_prod_reg = MLClient(
    credential=credential,
    subscription_id="5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25",
    registry_name="amlregprodcc001"
)

prod_model = Model(
    name="taxi-fare-model",
    version="1.0",
    path="azureml://registries/amlregdevcc004/models/taxi-fare-model/versions/1.0",
    description="Production model (promoted from dev)"
)
promoted_model = ml_client_prod_reg.models.create_or_update(prod_model)
```

### Environment Management
```python
# Create environment in dev workspace
from azure.ai.ml.entities import Environment

env = Environment(
    name="training-env",
    version="1.0",
    image="mcr.microsoft.com/azureml/openmpi4.1.0-ubuntu20.04:latest",
    conda_file="environment/conda.yaml"
)

# Create in dev workspace
dev_env = ml_client_dev_ws.environments.create_or_update(env)

# Share to dev registry
shared_env = ml_client_dev_ws.environments.share(
    name="training-env",
    version="1.0",
    registry_name="amlregdevcc004"
)

# Reference in production (recommended approach)
prod_env_reference = "azureml://registries/amlregdevcc004/environments/training-env/versions/1.0"
```

### Data Asset Management
```python
# Create data asset in dev workspace
from azure.ai.ml.entities import Data
from azure.ai.ml.constants import AssetTypes

data = Data(
    name="training-data",
    version="1.0",
    path="./data/training",
    type=AssetTypes.URI_FOLDER,
    description="Training dataset"
)

# Register in dev workspace
dev_data = ml_client_dev_ws.data.create_or_update(data)

# Share validation data to dev registry (not training data)
validation_data = Data(
    name="validation-data",
    version="1.0",
    path="./data/validation",
    type=AssetTypes.URI_FOLDER,
    description="Validation dataset for production testing"
)

shared_data = ml_client_dev_ws.data.share(
    name="validation-data",
    version="1.0",
    registry_name="amlregdevcc004"
)
```

## 🔧 Maintenance Commands

### Health Checks
```bash
# Check workspace status
az ml workspace show --name "amlwsdevcc004" --resource-group "rg-aml-ws-dev-cc" --query "provisioningState"

# Check compute status
az ml compute list --workspace-name "amlwsdevcc004" --resource-group "rg-aml-ws-dev-cc" --query "[].{Name:name, State:state}"

# Check storage connectivity
az storage account show --name "stdevcc004" --resource-group "rg-aml-ws-dev-cc" --query "provisioningState"

# Check private endpoints
az network private-endpoint list --resource-group "rg-aml-vnet-dev-cc004" --query "[].name"
```

### Compute Management
```bash
# List compute instances
az ml compute list --workspace-name "amlwsdevcc004" --resource-group "rg-aml-ws-dev-cc" --type ComputeInstance

# Stop idle compute instances
az ml compute stop --name "compute-instance-name" --workspace-name "amlwsdevcc004" --resource-group "rg-aml-ws-dev-cc"

# Delete unused compute instances
az ml compute delete --name "compute-instance-name" --workspace-name "amlwsdevcc004" --resource-group "rg-aml-ws-dev-cc"
```

### Storage Management
```bash
# Check storage usage
az storage account show-usage --subscription "5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25"

# List blobs in workspace storage
az storage blob list --account-name "stdevcc004" --container-name "azureml-blobstore-default" --auth-mode login

# Clean old experiment outputs (be careful!)
# az storage blob delete-batch --account-name "stdevcc004" --source "azureml-blobstore-default" --pattern "ExperimentRun/*" --auth-mode login
```

## 🛡️ Security Operations

### RBAC Verification
```bash
# Check managed identity assignments
az role assignment list --assignee "$(terraform output -raw dev_workspace_managed_identity_id)" --scope "/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-ws-dev-cc"

# Check user assignments
az role assignment list --assignee "user@company.com" --scope "/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-ws-dev-cc"

# List all role assignments for a resource group
az role assignment list --resource-group "rg-aml-ws-dev-cc" --output table
```

### Network Security
```bash
# Check outbound rules
az rest --method GET --url "https://management.azure.com/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-ws-prod-cc/providers/Microsoft.MachineLearningServices/workspaces/amlwsprodcc001/outboundRules?api-version=2024-10-01-preview"

# Verify private endpoint connections
az network private-endpoint show --name "private-endpoint-name" --resource-group "rg-aml-vnet-dev-cc004" --query "connectionState"

# Check network security group rules
az network nsg rule list --nsg-name "nsg-name" --resource-group "rg-aml-vnet-dev-cc004" --output table
```

### Key Vault Operations
```bash
# List secrets
az keyvault secret list --vault-name "kvdevcc004" --query "[].name"

# Check access policies
az keyvault show --name "kvdevcc004" --resource-group "rg-aml-vnet-dev-cc004" --query "properties.accessPolicies"

# Verify managed identity access
az keyvault secret show --vault-name "kvdevcc004" --name "secret-name" --query "id"
```

## 📊 Monitoring & Logging

### Log Analytics Queries
```kusto
// Workspace activity logs
AzureActivity
| where ResourceGroup in ("rg-aml-ws-dev-cc", "rg-aml-ws-prod-cc")
| where TimeGenerated > ago(24h)
| summarize count() by OperationName, Caller
| order by count_ desc

// Compute job events
AMLComputeJobEvent
| where TimeGenerated > ago(24h)
| summarize count() by JobName, JobStatus
| order by count_ desc

// Registry access events
AzureActivity
| where ResourceType == "Microsoft.MachineLearningServices/registries"
| where TimeGenerated > ago(24h)
| project TimeGenerated, Caller, OperationName, ResourceGroup
```

### Metrics and Alerts
```bash
# Create compute usage alert
az monitor metrics alert create \
  --name "high-compute-usage" \
  --resource-group "rg-aml-ws-dev-cc" \
  --scopes "/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-ws-dev-cc/providers/Microsoft.MachineLearningServices/workspaces/amlwsdevcc004" \
  --condition "count static.machineLearningServices/workspaces/activeNodes > 10" \
  --description "Alert when active compute nodes exceed 10"

# Check existing alerts
az monitor metrics alert list --resource-group "rg-aml-ws-dev-cc" --output table
```

## 🚨 Troubleshooting

### Common Issues & Solutions

#### Issue: "Access Denied" when promoting models
```bash
# Check cross-environment RBAC
az role assignment list --assignee "$(terraform output -raw prod_compute_managed_identity_id)" \
  --scope "/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-reg-dev-cc/providers/Microsoft.MachineLearningServices/registries/amlregdevcc004"
```

#### Issue: Private endpoint connection failures
```bash
# Check outbound rules configuration
az rest --method GET \
  --url "https://management.azure.com/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-ws-prod-cc/providers/Microsoft.MachineLearningServices/workspaces/amlwsprodcc001/outboundRules?api-version=2024-10-01-preview"

# Verify private endpoint status
az network private-endpoint list --resource-group "rg-aml-vnet-prod-cc001" --query "[].{Name:name, State:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}"
```

#### Issue: Terraform deployment failures
```bash
# Check resource provider registration
az provider show --namespace Microsoft.MachineLearningServices --query "registrationState"

# Verify subscription permissions
az role assignment list --assignee "$(az account show --query user.name -o tsv)" --scope "/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25"

# Check quota availability
az vm list-usage --location "canadacentral" --query "[?name.value=='cores'].{Name:name.localizedValue, Current:currentValue, Limit:limit}"
```

## 📞 Emergency Procedures

### Environment Recovery
```bash
# Emergency: Destroy and recreate development environment
terraform destroy -var-file="terraform.tfvars.dev" -target="module.aml_workspace"
terraform apply -var-file="terraform.tfvars.dev" -target="module.aml_workspace"

# Emergency: Reset managed identity permissions
az role assignment delete --assignee "MANAGED_IDENTITY_ID" --role "ROLE_NAME" --scope "SCOPE"
az role assignment create --assignee "MANAGED_IDENTITY_ID" --role "ROLE_NAME" --scope "SCOPE"

# Emergency: Recreate private endpoints
az network private-endpoint delete --name "pe-name" --resource-group "rg-name"
# Trigger recreation through workspace outbound rule update
```

### Backup and Restore
```bash
# Export workspace configuration
az ml workspace show --name "amlwsdevcc004" --resource-group "rg-aml-ws-dev-cc" > workspace-backup.json

# Export models and data assets
az ml model list --workspace-name "amlwsdevcc004" --resource-group "rg-aml-ws-dev-cc" > models-backup.json
az ml data list --workspace-name "amlwsdevcc004" --resource-group "rg-aml-ws-dev-cc" > data-backup.json

# Backup storage account (if needed)
az storage blob download-batch --destination "./backup" --source "azureml-blobstore-default" --account-name "stdevcc004" --auth-mode login
```

---

## 📚 Additional Resources

- **Deployment Guide**: `DEPLOYMENT_GUIDE.md` - Complete step-by-step deployment
- **Network Architecture**: `NETWORK_ARCHITECTURE.md` - Detailed network and RBAC diagrams
- **Strategy Document**: `DeploymentStrategy.md` - Comprehensive deployment strategy
- **Automation Script**: `Deploy-AzureMLPlatform.ps1` - PowerShell deployment automation

For support: Review logs in `/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-vnet-{env}-cc{number}/providers/Microsoft.OperationalInsights/workspaces/amllog{env}cc{number}`
