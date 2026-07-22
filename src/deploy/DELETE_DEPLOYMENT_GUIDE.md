# Delete Deployment Guide

This guide provides multiple methods to delete Azure ML online deployments.

## Method 1: Use the Delete Script

### Basic Usage
```bash
python src/deploy/delete_deployment.py \
  --endpoint_name "your-endpoint-name" \
  --deployment_name "your-deployment-name"
```

### With Explicit Workspace Parameters
```bash
python src/deploy/delete_deployment.py \
  --endpoint_name "your-endpoint-name" \
  --deployment_name "your-deployment-name" \
  --subscription_id "your-subscription-id" \
  --resource_group "your-resource-group" \
  --workspace_name "your-workspace-name"
```

### Delete Deployment AND Endpoint
```bash
python src/deploy/delete_deployment.py \
  --endpoint_name "your-endpoint-name" \
  --deployment_name "your-deployment-name" \
  --delete_endpoint
```

## Method 2: Azure ML CLI

### List Endpoints
```bash
az ml online-endpoint list \
  --resource-group <resource-group> \
  --workspace-name <workspace-name>
```

### List Deployments in an Endpoint
```bash
az ml online-deployment list \
  --endpoint-name <endpoint-name> \
  --resource-group <resource-group> \
  --workspace-name <workspace-name>
```

### Delete a Specific Deployment
```bash
az ml online-deployment delete \
  --name <deployment-name> \
  --endpoint-name <endpoint-name> \
  --resource-group <resource-group> \
  --workspace-name <workspace-name> \
  --yes
```

### Delete the Entire Endpoint
```bash
az ml online-endpoint delete \
  --name <endpoint-name> \
  --resource-group <resource-group> \
  --workspace-name <workspace-name> \
  --yes
```

## Method 3: Python SDK (Interactive)

### Option A: Using your existing workspace context
```python
from azure.ai.ml import MLClient
from azure.identity import DefaultAzureCredential

# Connect to workspace
credential = DefaultAzureCredential()
ml_client = MLClient(
    credential=credential,
    subscription_id="<subscription-id>",
    resource_group_name="<resource-group>",
    workspace_name="<workspace-name>"
)

# Delete deployment
ml_client.online_deployments.begin_delete(
    name="<deployment-name>",
    endpoint_name="<endpoint-name>"
).result()

print("Deployment deleted successfully")
```

### Option B: First redirect traffic, then delete
```python
from azure.ai.ml import MLClient
from azure.identity import DefaultAzureCredential

credential = DefaultAzureCredential()
ml_client = MLClient(
    credential=credential,
    subscription_id="<subscription-id>",
    resource_group_name="<resource-group>",
    workspace_name="<workspace-name>"
)

# Get the endpoint
endpoint = ml_client.online_endpoints.get(name="<endpoint-name>")

# Remove deployment from traffic
endpoint.traffic = {
    "other-deployment": 100,  # Route all traffic to another deployment
    # Remove the deployment you want to delete from traffic dict
}

# Update endpoint
ml_client.online_endpoints.begin_create_or_update(endpoint).result()

# Now delete the deployment
ml_client.online_deployments.begin_delete(
    name="<deployment-name>",
    endpoint_name="<endpoint-name>"
).result()

print("Traffic redirected and deployment deleted")
```

## Method 4: Azure Portal

1. Navigate to [Azure ML Studio](https://ml.azure.com)
2. Go to **Endpoints** in the left menu
3. Click on your endpoint name
4. Find the deployment you want to delete
5. Click the **Delete** button (trash icon)
6. Confirm deletion

## Best Practices

### Before Deleting a Deployment:

1. **Check Traffic**: Ensure the deployment has 0% traffic
   ```bash
   az ml online-endpoint show \
     --name <endpoint-name> \
     --resource-group <resource-group> \
     --workspace-name <workspace-name>
   ```

2. **Redirect Traffic**: If the deployment has traffic, redirect it to another deployment first
   - Use the `update_traffic.py` script (already in your project)
   - Or manually update via Azure ML Studio

3. **Test Other Deployments**: Ensure other deployments are working properly before deleting

4. **Document**: Keep a record of what was deleted and why

### Cost Considerations:
- Deployments consume compute resources even with 0% traffic
- Delete unused deployments to reduce costs
- Consider deleting the entire endpoint if no longer needed

## Troubleshooting

### "Deployment not found"
- Verify the endpoint and deployment names
- Check you're connected to the correct workspace

### "Deployment has traffic"
- Redirect traffic to 0% or another deployment first
- Use the Python SDK or CLI to update endpoint traffic

### Permission Errors
- Ensure you have Owner or Contributor role on the workspace
- Check Azure RBAC permissions

## Integration with Your Existing Scripts

Your project already has traffic management in [`src/traffic/update_traffic.py`](../traffic/update_traffic.py) which includes rollback with deletion:

```bash
# Rollback and delete deployment
python src/traffic/update_traffic.py \
  --endpoint_name "<endpoint-name>" \
  --deployment_name "<deployment-name>" \
  --mode rollback \
  --delete_on_rollback true \
  --deployment_state <path-to-deployment-state>
```

This is useful for CI/CD scenarios where you want to automatically clean up failed deployments.
