# Model Data Collection with OneLake Integration

This guide shows how to configure Azure ML online endpoints to write inference data to a dedicated ADLS Gen2 storage account, then access it from Microsoft Fabric using OneLake Shortcuts.

## Architecture

```
Azure ML Real-time Endpoint
  └── Model Data Collector
        └── ADLS Gen2 Storage Account
              └── OneLake Shortcut
                    └── Fabric Lakehouse
```

## Benefits

- **No Data Duplication**: OneLake Shortcuts reference data in place
- **Separation of Concerns**: Dedicated storage for inference data
- **Cost Optimization**: Lifecycle policies on ADLS Gen2
- **Fabric Integration**: Direct access from notebooks, Power BI, Spark

## Step 1: Deploy Infrastructure

### 1.1 Update terraform.tfvars (Optional)

Add these optional variables to customize your data collection storage:

```hcl
# Optional: Restrict public network access with IP allowlist
datacollection_storage_public_access = true
datacollection_storage_default_action = "Allow"  # or "Deny" with IP allowlist

# Optional: Allowed IPs for management access
datacollection_storage_allowed_ips = ["1.2.3.4"]

# Optional: Enable versioning for audit trail
datacollection_storage_versioning_enabled = false
```

Note: This is the no-networking template with public access. For private networking, use the `infra/` folder instead.

### 1.2 Deploy with Terraform

```bash
cd infra_no_networking

# Initialize
terraform init

# Plan
terraform plan -out=tfplan

# Apply
terraform apply tfplan
```

### 1.3 Get Storage Account Information

After deployment, capture the outputs:

```bash
terraform output datacollection_storage_account_name
terraform output datacollection_storage_primary_dfs_endpoint
terraform output -raw datacollection_abfss_path
```

## Step 2: Register ADLS Gen2 Datastore in Azure ML

Create a datastore in your Azure ML workspace pointing to the data collection storage:

```python
from azure.ai.ml import MLClient
from azure.ai.ml.entities import AzureDataLakeGen2Datastore
from azure.ai.ml.entities import AccountKeyConfiguration
from azure.identity import DefaultAzureCredential

# Connect to workspace
ml_client = MLClient(
    DefaultAzureCredential(),
    subscription_id="<your-sub-id>",
    resource_group="rg-aml-workspace-dev-cc-<suffix>",
    workspace_name="mlw-aml-dev-cc<suffix>"
)

# Get storage account name from Terraform output
storage_account_name = "stamldc cc<suffix>"  # From terraform output

# Create datastore
datastore = AzureDataLakeGen2Datastore(
    name="datacollection_adls",
    description="ADLS Gen2 for model inference data collection",
    account_name=storage_account_name,
    filesystem="model-inputs",  # or "model-outputs"
)

# Register datastore (uses workspace managed identity by default)
ml_client.datastores.create_or_update(datastore)

print(f"✅ Datastore 'datacollection_adls' registered")
```

## Step 3: Configure Online Endpoint Data Collector

Update your deployment to write to the ADLS Gen2 datastore:

```python
from azure.ai.ml.entities import (
    ManagedOnlineDeployment,
    DataCollector,
    DeploymentCollection,
)

# Configure data collector to write to ADLS Gen2
collections = {
    "model_inputs": DeploymentCollection(enabled=True),
    "model_outputs": DeploymentCollection(enabled=True),
}

data_collector = DataCollector(
    collections=collections,
    sampling_rate=1.0,  # 100% sampling
    destination="azureml://datastores/datacollection_adls/paths/modelDataCollector/"
)

# Create deployment with data collector
deployment = ManagedOnlineDeployment(
    name="blue",
    endpoint_name=endpoint_name,
    model=model,
    environment=env,
    data_collector=data_collector,  # Add data collector
    # ... other deployment config
)

ml_client.begin_create_or_update(deployment).result()
```

## Step 4: Create OneLake Shortcut in Fabric

### Method 1: Using Fabric UI

1. Open your **Fabric Workspace**
2. Navigate to your **Lakehouse**
3. Right-click **Files** folder → **New shortcut**
4. Select **Azure Data Lake Storage Gen2**
5. Configure connection:
   - **URL**: `https://stamldc<location><suffix>.dfs.core.windows.net/`
   - **Authentication**: Organizational account or Service Principal
6. Select **model-inputs** and/or **model-outputs** containers
7. Name your shortcut (e.g., `model_inference_data`)

### Method 2: Using Fabric REST API

```python
import requests
from azure.identity import DefaultAzureCredential

# Get access token
credential = DefaultAzureCredential()
token = credential.get_token("https://api.fabric.microsoft.com/.default")

# Fabric configuration
workspace_id = "<your-fabric-workspace-id>"
lakehouse_id = "<your-lakehouse-id>"

# ADLS Gen2 configuration (from Terraform outputs)
storage_account = "stamldc<location><suffix>"
container = "model-inputs"
adls_url = f"https://{storage_account}.dfs.core.windows.net/{container}"

# Create shortcut
url = f"https://api.fabric.microsoft.com/v1/workspaces/{workspace_id}/items/{lakehouse_id}/shortcuts"

shortcut_data = {
    "name": "model_inference_inputs",
    "path": "Files",
    "target": {
        "adlsGen2": {
            "location": adls_url,
            "connectionId": "<connection-id>",  # Or use SAS/managed identity
            "subpath": "/modelDataCollector/"
        }
    }
}

headers = {
    "Authorization": f"Bearer {token.token}",
    "Content-Type": "application/json"
}

response = requests.post(url, json=shortcut_data, headers=headers)
print(response.json())
```

## Step 5: Access Data in Fabric

### From Fabric Notebook (PySpark)

```python
# Access data through OneLake shortcut
df = spark.read.format("json") \
    .option("multiline", "true") \
    .load("Files/model_inference_inputs/*/blue/model_inputs/*/*/*/*/*.jsonl")

# Show schema
df.printSchema()

# Query recent predictions
df.createOrReplaceTempView("inference_data")
spark.sql("""
    SELECT 
        from_unixtime(time/1000) as timestamp,
        correlationid,
        data
    FROM inference_data
    WHERE from_unixtime(time/1000) >= current_date() - 7
    ORDER BY time DESC
    LIMIT 100
""").show()
```

### From Fabric Notebook (Pandas)

```python
import pandas as pd
from notebookutils import mssparkutils

# List all JSONL files
files = mssparkutils.fs.ls("Files/model_inference_inputs/")

# Read specific file
file_path = "Files/model_inference_inputs/<endpoint>/<deployment>/model_inputs/2026/01/30/14/instance.jsonl"
df = pd.read_json(file_path, lines=True)

print(df.head())
```

### From Power BI

1. In Power BI Desktop, select **Get Data** → **OneLake data hub**
2. Navigate to your **Lakehouse** → **Files** → **model_inference_inputs**
3. Select the JSON files you want to analyze
4. Power Query will load the data for transformation

## Data Schema

Each JSONL file contains CloudEvents-formatted records:

```json
{
  "specversion": "1.0",
  "id": "unique-id",
  "source": "azureml://...",
  "type": "azureml.inference.request",
  "time": "2026-01-30T14:35:22.123Z",
  "correlationid": "abc-123",
  "data": {
    // Your model input/output data as DataFrame JSON
  }
}
```

## File Organization

```
model-inputs/  (or model-outputs/)
└── modelDataCollector/
    └── {endpoint_name}/
        └── {deployment_name}/
            └── {collection_name}/
                └── {yyyy}/
                    └── {MM}/
                        └── {dd}/
                            └── {HH}/
                                └── {instance_id}.jsonl
```

## Cost Optimization

The ADLS Gen2 storage includes:
- **30-day retention policies** for deleted data
- **Hot tier** by default (change to Cool/Archive for older data)
- **Optional versioning** for audit trail

Consider adding lifecycle management rules:

```bash
az storage account management-policy create \
  --account-name stamldc<location><suffix> \
  --resource-group rg-aml-datacollection-<location>-<suffix> \
  --policy @lifecycle-policy.json
```

Example `lifecycle-policy.json`:

```json
{
  "rules": [
    {
      "enabled": true,
      "name": "move-old-data-to-cool",
      "type": "Lifecycle",
      "definition": {
        "actions": {
          "baseBlob": {
            "tierToCool": {
              "daysAfterModificationGreaterThan": 30
            },
            "tierToArchive": {
              "daysAfterModificationGreaterThan": 90
            }
          }
        },
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["model-inputs/", "model-outputs/"]
        }
      }
    }
  ]
}
```

## Monitoring

The Terraform configuration includes diagnostic settings that send metrics to Log Analytics:

```kusto
// Query storage transactions
StorageBlobLogs
| where AccountName == "stamldc<location><suffix>"
| where TimeGenerated > ago(24h)
| summarize 
    RequestCount = count(),
    TotalBytes = sum(ResponseBodySize)
    by bin(TimeGenerated, 1h), OperationName
| render timechart
```

## Troubleshooting

### Issue: Data collector writes to default blob storage

**Solution**: Verify the datastore is registered and the `destination` parameter is set correctly in the `DataCollector` configuration.

### Issue: OneLake shortcut shows "Access Denied"

**Solution**: Ensure the Fabric workspace managed identity or your user account has **Storage Blob Data Reader** role on the ADLS Gen2 account.

```bash
# Grant Fabric workspace managed identity access
az role assignment create \
  --assignee <fabric-workspace-managed-identity-id> \
  --role "Storage Blob Data Reader" \
  --scope /subscriptions/<sub-id>/resourceGroups/rg-aml-datacollection-<location>-<suffix>/providers/Microsoft.Storage/storageAccounts/stamldc<location><suffix>
```

### Issue: No data appearing in ADLS Gen2

**Solution**: 
1. Verify the endpoint has received requests
2. Check the deployment logs for data collector errors
3. Ensure the workspace managed identity has **Storage Blob Data Contributor** role

## Next Steps

- Configure scheduled jobs to aggregate/summarize inference data
- Set up alerts for data quality issues
- Build Power BI dashboards for model monitoring
- Implement drift detection using Fabric notebooks
