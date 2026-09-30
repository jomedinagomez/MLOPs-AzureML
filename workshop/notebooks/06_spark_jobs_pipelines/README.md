# Azure ML Serverless Spark Jobs from a Notebook

This exercise submits a serverless Azure Machine Learning Spark job from an Azure ML
compute-instance notebook. It adapts Microsoft's managed-identity Titanic example to
the security posture already deployed by this repository.

## Exercise contents

```text
06_spark_jobs_pipelines/
├── 01_submit_serverless_spark_job.ipynb
├── README.md
├── serverless-spark-managed-identity.yml
├── data/
│   └── titanic.csv
└── src/
    └── titanic.py
```

The notebook:

1. Loads workspace configuration from [`workshop/.env`](../../.env.example).
2. Loads [`serverless-spark-managed-identity.yml`](./serverless-spark-managed-identity.yml)
   directly with `load_job`.
3. Prints the configured workspace, Spark runtime, and instance type.
4. Submits only when `RUN_SERVERLESS_SPARK_JOB=true`.
5. Streams the job and requires final status `Completed`.

## Best official demo to add

The strongest match is Microsoft's **serverless Spark standalone job using managed
identity**:

- [Spark job YAML](https://github.com/Azure/azureml-examples/blob/86d53a35d2ecc33ff40c669cc1389b06899e5a4b/cli/jobs/spark/serverless-spark-standalone-managed-identity.yml)
- [PySpark entry point](https://github.com/Azure/azureml-examples/blob/86d53a35d2ecc33ff40c669cc1389b06899e5a4b/cli/jobs/spark/src/titanic.py)
- [Titanic input data](https://github.com/Azure/azureml-examples/blob/86d53a35d2ecc33ff40c669cc1389b06899e5a4b/cli/jobs/spark/data/titanic.csv)
- [Official Spark examples guide](https://github.com/Azure/azureml-examples/blob/86d53a35d2ecc33ff40c669cc1389b06899e5a4b/cli/jobs/spark/README.md)

The checked-in YAML adapts the pinned official YAML. The adapted
[`src/titanic.py`](./src/titanic.py) uses the Spark DataFrame API and actually applies
the mean-age imputation before writing output. Microsoft's source creates an `Imputer`
object but does not apply it.

Additional Microsoft documentation:

- [Submit Spark jobs in Azure Machine Learning](https://learn.microsoft.com/azure/machine-learning/how-to-submit-spark-jobs?view=azureml-api-2)
- [Configure managed networking for serverless Spark](https://learn.microsoft.com/azure/machine-learning/how-to-managed-network?view=azureml-api-2#configure-for-serverless-spark-jobs)
- [Azure ML managed-network isolation](https://learn.microsoft.com/azure/machine-learning/how-to-managed-network?view=azureml-api-2)

## Current repository setup

The codified Spark-ready replacement is defined under
[`infra/spark-workspace/`](../../../infra/spark-workspace/README.md):

- One standard Azure ML workspace with a primary user-assigned managed identity.
- Azure ML managed VNet with `AllowOnlyApprovedOutbound`.
- Workspace selected-public-IP access.
- Premium ACR with selected-public-IP access.
- Private Storage and Key Vault access enforced by `MCAPSGovDeployPolicies`.
- CMK encryption for the workspace and default Storage account.
- AML compute cluster and compute instance using UAMIs.
- No customer VNet, subnet, private DNS, Bastion, or jump box.

Azure ML managed networking already owns the private connections to the linked Storage,
Key Vault, ACR, and workspace. **Do not create a second customer VNet for this demo.**
Azure already created required system private endpoints for Blob, File, ACR, and the
workspace. The Blob system rule is Spark-enabled; the remaining gap is provisioning the
Spark network plane and granting Storage `Contributor` to the workspace UAMI.

The legacy `single-workspace` deployment reported:

```text
managedNetwork.isolationMode = AllowOnlyApprovedOutbound
managedNetwork.status.status = Active
managedNetwork.status.sparkReady = false
```

Verify the live value with the command in [Verify readiness](#6-verify-readiness)
before setting the submission switch to `true`.

## Infrastructure required before running

Deploy and validate [`infra/spark-workspace/`](../../../infra/spark-workspace/README.md).
Do not manually patch the legacy `single-workspace` deployment.

### 1. Terraform provisions the Spark network

The replacement calls the AML ARM `provisionManagedNetwork` action directly with
Terraform `azapi_resource_action` and `includeSpark=true`. No Azure CLI provisioner is
used. Do **not** add a second Blob rule; Azure rejects duplicate destinations.

After deployment, list all rules:

```powershell
az ml workspace outbound-rule list `
  --subscription $env:AZURE_SUBSCRIPTION_ID `
  --resource-group $env:AZURE_RESOURCE_GROUP `
  --workspace-name $env:AZUREML_WORKSPACE_NAME `
  --query "[?type=='PrivateEndpoint' && destination.subresource_target=='blob']"
```

For this workspace, Azure created a required rule whose name starts with
`__SYS_PE_stsinglecc01_blob_`. It must show `spark_enabled: true` and `status: Active`.
If a different workspace lacks such a rule, update the existing Blob destination with
`az ml workspace outbound-rule set`; never create a duplicate destination in Terraform.

### 2. Terraform grants the Storage management-plane role

The replacement grants both `Storage Blob Data Contributor` and `Contributor` to the
workspace UAMI in
[`identity-rbac.tf`](../../../infra/spark-workspace/modules/aml-managed-umi/identity-rbac.tf).

```hcl
resource "azurerm_role_assignment" "workspace_storage_contributor_for_spark" {
  name                 = uuidv5(
    "dns",
    "${module.storage_account_default.id}${azurerm_user_assigned_identity.workspace_identity.principal_id}sparkcontributor"
  )
  scope                = module.storage_account_default.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.workspace_identity.principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [time_sleep.wait_workspace_identity]
}
```

Add this assignment to the role-propagation wait that runs before workspace-dependent
operations.

### 3. AzAPI performs the Spark action

Microsoft requires an explicit managed-network provisioning action with Spark included.
The replacement codifies it in Terraform:

```hcl
resource "azapi_resource_action" "spark_network_provisioning" {
  type        = "Microsoft.MachineLearningServices/workspaces@2025-06-01"
  resource_id = azapi_resource.aml_workspace.id
  action      = "provisionManagedNetwork"
  method      = "POST"
  body = {
    includeSpark = true
  }
  timeouts {
    create = "3h"
  }
}
```

An AzAPI PATCH action restores selected-IP workspace access after the Spark action
completes. Compute creation depends on that restoration.

### 4. Compute depends on Spark network readiness

The serverless Spark job does not run on the AML compute cluster. Terraform still
creates cluster/instance compute only after the Spark action and selected-IP ACL action
succeed.

### 5. Validate and apply

From the repository root:

```powershell
terraform -chdir=infra\spark-workspace fmt -check -recursive
terraform -chdir=infra\spark-workspace validate
terraform -chdir=infra\spark-workspace plan -out=tfplan
```

Review the saved plan. It should add one Storage-scoped role assignment and run the
Spark provisioning barrier. It must not add a duplicate Blob rule, customer VNet,
subnet, customer private endpoint, or registry.

After the usual deployment-risk review:

```powershell
terraform -chdir=infra\spark-workspace apply tfplan
```

### 6. Verify readiness

```powershell
az rest `
  --method get `
  --uri "https://management.azure.com/subscriptions/$env:AZURE_SUBSCRIPTION_ID/resourceGroups/$env:AZURE_RESOURCE_GROUP/providers/Microsoft.MachineLearningServices/workspaces/$env:AZUREML_WORKSPACE_NAME?api-version=2025-06-01" `
  --query "{isolationMode:properties.managedNetwork.isolationMode,status:properties.managedNetwork.status.status,sparkReady:properties.managedNetwork.status.sparkReady}" `
  --output json
```

Expected:

```json
{
  "isolationMode": "AllowOnlyApprovedOutbound",
  "status": "Active",
  "sparkReady": true
}
```

Also verify the rule:

```powershell
az ml workspace outbound-rule show `
  --subscription $env:AZURE_SUBSCRIPTION_ID `
  --resource-group $env:AZURE_RESOURCE_GROUP `
  --workspace-name $env:AZUREML_WORKSPACE_NAME `
  --rule __SYS_PE_stsinglecc01_blob_34193aab
```

## Workshop configuration

Set these values in the ignored `workshop/.env`:

```dotenv
RUN_SERVERLESS_SPARK_JOB=false
AZUREML_OUTPUT_DATASTORE=workspaceblobstore
```

Keep `RUN_SERVERLESS_SPARK_JOB=false` while reviewing the checked-in YAML. Set it to
`true` only for the submission cell, and return it to `false` afterward.

The Spark runtime and instance type now live in
[`serverless-spark-managed-identity.yml`](./serverless-spark-managed-identity.yml), so
the YAML remains the single source of truth for the job.

## Run the notebook

Use the `azureml-workshop` kernel on the Azure ML compute instance:

```text
01_submit_serverless_spark_job.ipynb
```

The pinned 60 KB Titanic CSV is checked in under [`data/titanic.csv`](./data/titanic.csv)
so `load_job` can upload the complete YAML-defined job package.

## Cost and networking notes

- Serverless Spark provisions ephemeral Spark resources and is billed while the job
  runs.
- `Standard_E4S_V3` is the default from Microsoft's sample. Confirm quota and regional
  availability before submission.
- Spark runtime `3.4.0` is used by the SDK example. Do not use retired 3.3 examples.
- Under `AllowOnlyApprovedOutbound`, Spark session Conda installation isn't supported,
  and FQDN rules don't make it work. Package custom dependencies as self-contained
  wheels, store them behind an approved private endpoint, and pass them through
  `py_files`.
- This demo uses only libraries available in the built-in Spark runtime.
- The notebook must run from an environment with private access to workspace Storage;
  the Azure ML compute instance satisfies that requirement.

## Troubleshooting

### `sparkReady` remains false

- Confirm the required `__SYS_PE_*_blob_*` rule has `spark_enabled: true`.
- Run `az ml workspace provision-network --include-spark`.
- Wait for managed-network status to return `Active`.
- Confirm the workspace ACL restoration step ran after provisioning.

### Authorization failure on input or output

- If the traceback fails inside `_upload_to_datastore` or `check_blob_exists`, the
  notebook is running outside the private Storage network path. Run it on
  `aml-instance-single-cc01`; adding more user RBAC does not bypass
  `publicNetworkAccess = Disabled`.
- Confirm the job uses the workspace UAMI.
- Confirm that UAMI has `Contributor` and `Storage Blob Data Contributor` on the
  workspace Storage account.
- Confirm the managed private endpoint connection is approved. Because Storage and the
  workspace are in the same resource group here, approval should be automatic.

### Package installation failure

Do not add more FQDN rules. Under approved-only outbound, use a self-contained wheel in
approved Storage and pass it with `py_files`.
