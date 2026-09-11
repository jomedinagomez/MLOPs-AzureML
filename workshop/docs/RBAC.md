# Workshop Managed Identity RBAC

Apply these assignments before the workshop from an administrator session that can create Azure role assignments. Do not attempt to assign roles while signed in as one of the workshop managed identities.

Role assignments can take up to one hour to propagate through cached Azure services. After an administrator changes RBAC, refresh the compute-instance session with:

```bash
az login --identity --client-id "$DEFAULT_IDENTITY_CLIENT_ID"
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
```

## Identity Responsibilities

| Identity | Used by | Purpose |
| --- | --- | --- |
| Compute-instance UMI | `AzureCliCredential` in the notebooks | Reads and changes Azure ML control-plane resources, uploads assets, submits jobs, creates endpoints, and invokes endpoints |
| Compute-cluster UMI | Azure ML command and pipeline jobs | Reads inputs, writes outputs, pulls job images, and authenticates code running on cluster nodes |
| Managed-online-endpoint UMI | Managed online endpoint runtime | Pulls the serving image and reads model/environment artifacts from workspace resources |
| Workspace managed identity | Azure ML service | Builds environments and accesses workspace dependencies such as storage, ACR, and Key Vault |

The compute-instance and compute-cluster UMIs are intentionally different. `DEFAULT_IDENTITY_CLIENT_ID` identifies the compute-instance UMI. `AZUREML_COMPUTE_IDENTITY_CLIENT_ID` identifies the compute-cluster UMI.

## Required Role Matrix

### Compute-instance UMI

| Role | Scope | Why |
| --- | --- | --- |
| `AzureML Data Scientist` or an approved equivalent custom role | Azure ML workspace | Read/create assets, submit jobs, create deployments, invoke Microsoft Entra-authenticated endpoints |
| `Storage Blob Data Contributor` | Workspace storage account | Upload local data and code and download workshop outputs |
| `Storage File Data Privileged Contributor` | Workspace storage account | Use the Azure ML workspace file share mounted on the compute instance |
| `Managed Identity Operator` | Managed-online-endpoint UMI resource | Attach the endpoint UMI while creating the managed online endpoint |

The endpoint attachment specifically requires `Microsoft.ManagedIdentity/userAssignedIdentities/assign/action`. Grant `Managed Identity Operator` on the individual endpoint UMI, not at subscription scope.

### Compute-cluster UMI

| Role | Scope | Why |
| --- | --- | --- |
| `AzureML Data Scientist` | Azure ML workspace | Run Azure ML jobs and interact with workspace job resources |
| `Storage Blob Data Contributor` | Workspace storage account | Read job inputs and write job outputs |
| `AcrPull` | Workspace container registry | Pull job and environment images |
| `Key Vault Secrets User` | Workspace Key Vault | Resolve workspace-managed secrets used by jobs |

The repository Terraform also grants the cluster UMI `Storage File Data Privileged Contributor`, storage table/queue data roles, `AcrPush`, workspace `Contributor`, and resource-group `Reader`. Preserve those assignments when deploying this repository's full infrastructure. They are broader platform-operation assignments and are not all required by every workshop notebook.

If automation running on the cluster creates endpoints and attaches the endpoint UMI, also grant the cluster UMI `Managed Identity Operator` on that endpoint UMI.

### Managed-online-endpoint UMI

Microsoft documents the following runtime roles as required for managed online endpoints using a UMI:

| Role | Scope | Why |
| --- | --- | --- |
| `AcrPull` | Workspace container registry | Pull the built serving image |
| `Storage Blob Data Reader` | Workspace storage account | Read registered model and environment artifacts |
| `AzureML Metrics Writer (preview)` | Azure ML workspace | Emit endpoint metrics; included by this repository's Terraform |

Grant additional data-plane roles only when the scoring code directly accesses another Azure resource.

## Administrator Variables

```bash
SUBSCRIPTION_ID="<SUBSCRIPTION_ID>"
RESOURCE_GROUP="<WORKSPACE_RESOURCE_GROUP>"
WORKSPACE_NAME="<WORKSPACE_NAME>"
STORAGE_ACCOUNT_NAME="<WORKSPACE_STORAGE_ACCOUNT>"
ACR_NAME="<WORKSPACE_CONTAINER_REGISTRY>"
KEY_VAULT_NAME="<WORKSPACE_KEY_VAULT>"
ENDPOINT_UMI_NAME="<ONLINE_ENDPOINT_UMI_NAME>"

WORKSPACE_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/workspaces/${WORKSPACE_NAME}"
STORAGE_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT_NAME}"
ACR_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ContainerRegistry/registries/${ACR_NAME}"
KEY_VAULT_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}"
ENDPOINT_UMI_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${ENDPOINT_UMI_NAME}"

COMPUTE_INSTANCE_UMI_PRINCIPAL_ID="<COMPUTE_INSTANCE_UMI_PRINCIPAL_ID>"
COMPUTE_CLUSTER_UMI_PRINCIPAL_ID="<COMPUTE_CLUSTER_UMI_PRINCIPAL_ID>"
```

Retrieve the endpoint UMI principal ID from the administrator session:

```bash
ENDPOINT_UMI_PRINCIPAL_ID=$(az identity show \
  --ids "$ENDPOINT_UMI_SCOPE" \
  --query principalId \
  --output tsv)
```

## Administrator Commands

Run only the assignments missing from the target environment.

### Compute-instance UMI

```bash
az role assignment create \
  --assignee-object-id "$COMPUTE_INSTANCE_UMI_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "AzureML Data Scientist" \
  --scope "$WORKSPACE_SCOPE"

az role assignment create \
  --assignee-object-id "$COMPUTE_INSTANCE_UMI_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "$STORAGE_SCOPE"

az role assignment create \
  --assignee-object-id "$COMPUTE_INSTANCE_UMI_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage File Data Privileged Contributor" \
  --scope "$STORAGE_SCOPE"

az role assignment create \
  --assignee-object-id "$COMPUTE_INSTANCE_UMI_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Managed Identity Operator" \
  --scope "$ENDPOINT_UMI_SCOPE"
```

### Compute-cluster UMI

```bash
az role assignment create \
  --assignee-object-id "$COMPUTE_CLUSTER_UMI_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "AzureML Data Scientist" \
  --scope "$WORKSPACE_SCOPE"

az role assignment create \
  --assignee-object-id "$COMPUTE_CLUSTER_UMI_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "$STORAGE_SCOPE"

az role assignment create \
  --assignee-object-id "$COMPUTE_CLUSTER_UMI_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "AcrPull" \
  --scope "$ACR_SCOPE"

az role assignment create \
  --assignee-object-id "$COMPUTE_CLUSTER_UMI_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" \
  --scope "$KEY_VAULT_SCOPE"
```

### Managed-online-endpoint UMI

```bash
az role assignment create \
  --assignee-object-id "$ENDPOINT_UMI_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "AcrPull" \
  --scope "$ACR_SCOPE"

az role assignment create \
  --assignee-object-id "$ENDPOINT_UMI_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Reader" \
  --scope "$STORAGE_SCOPE"

az role assignment create \
  --assignee-object-id "$ENDPOINT_UMI_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "AzureML Metrics Writer (preview)" \
  --scope "$WORKSPACE_SCOPE"
```

## Verify Assignments

From the administrator session:

```bash
az role assignment list \
  --assignee-object-id "$COMPUTE_INSTANCE_UMI_PRINCIPAL_ID" \
  --all \
  --query "[].{role:roleDefinitionName,scope:scope}" \
  --output table

az role assignment list \
  --assignee-object-id "$COMPUTE_CLUSTER_UMI_PRINCIPAL_ID" \
  --all \
  --query "[].{role:roleDefinitionName,scope:scope}" \
  --output table

az role assignment list \
  --assignee-object-id "$ENDPOINT_UMI_PRINCIPAL_ID" \
  --all \
  --query "[].{role:roleDefinitionName,scope:scope}" \
  --output table
```

Then return to the compute instance, refresh `az login --identity`, and rerun the blocked notebook cells.

## Error-to-Role Map

| Error | Missing authorization |
| --- | --- |
| `AuthorizationFailed` on `Microsoft.MachineLearningServices/workspaces/read` | Compute-instance UMI lacks workspace `AzureML Data Scientist` or equivalent |
| `Unknown compute target 'azureml:<name>'` | Not RBAC; Python SDK job must use the bare compute name |
| `LinkedAuthorizationFailed` on `userAssignedIdentities/assign/action` | Endpoint creator lacks `Managed Identity Operator` on the endpoint UMI |
| Endpoint image pull fails with ACR authorization | Endpoint UMI lacks `AcrPull` on workspace ACR |
| Endpoint cannot load model artifacts | Endpoint UMI lacks `Storage Blob Data Reader` on workspace storage |
| Job cannot read inputs or write outputs | Cluster UMI lacks storage data-plane access |
| `ImageNotFound` for the base image | Not RBAC; register a new environment version with a valid MCR image |

## Security Notes

- Managed identity client IDs, principal IDs, and resource IDs are identifiers, not secrets.
- Never put credentials, tokens, passwords, storage keys, or client secrets in `.env`.
- Scope `Managed Identity Operator` to the individual UMI wherever possible.
- The identity attached to a managed online endpoint is immutable after endpoint creation. Verify it before creating the endpoint.
