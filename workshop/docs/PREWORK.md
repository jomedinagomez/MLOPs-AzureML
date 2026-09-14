# Workshop Prework

Complete this checklist before the workshop. Durable infrastructure should be deployed beforehand so workshop time is spent using Azure ML rather than waiting for provisioning.

## Customer Workspace

- Azure ML workspace is provisioned and reachable from the assigned compute instance.
- A CPU compute cluster exists and can scale from zero.
- A compute instance is running for the customer operator.
- Workspace default storage, Key Vault, and ACR are healthy.
- Managed online endpoint quota is available for the selected VM SKU.
- If private networking is enabled, required private endpoints, DNS, and approved outbound rules are active.
- CMK configuration is healthy and the workspace identity can access its key.

## Identity and Permissions

The customer operator needs enough access to:

- Read the workspace and its assets.
- Create/update data, model, environment, job, and endpoint resources used by the workshop.
- Use the selected compute cluster.
- Read/write the workspace datastore used for inputs and outputs.
- Assign the configured endpoint UMI when `AZUREML_ONLINE_ENDPOINT_IDENTITY_ID` is set.

When notebooks authenticate as the compute-instance UMI, grant that UMI `AzureML Data Scientist` on the workspace and the required Blob/File data roles on the default storage account. Grant the same caller `Managed Identity Operator` on the endpoint UMI so it can create or update an endpoint linked to that identity.

The endpoint UMI has a separate runtime role set. It needs `AcrPull` on the workspace registry, `Storage Blob Data Reader` on the workspace storage account, and `AzureML Metrics Writer` on the workspace. Do not substitute endpoint runtime permissions for the caller's `Managed Identity Operator` permission.

Use organization-approved roles and least-privilege custom roles where available. Do not place credentials in `.env`.

## Compute Instance

```bash
az --version
az extension show --name ml
python --version
java -version
git --version
uv --version
```

Required runtime:

- Python 3.12 for the workshop virtual environment.
- OpenJDK 17 for H2O binary models.
- Azure CLI with the current `ml` extension.
- Network access to package repositories, Azure control-plane endpoints, and any optional GitHub/Copilot services used during the call.

## Predeployed Tour Assets

Prepare representative examples of:

- Data asset
- Registered model
- Registered environment
- Completed command job
- Completed pipeline job
- Managed online endpoint and deployment

Workshop-created assets use the names in `.env` and remain separate from these tour assets.