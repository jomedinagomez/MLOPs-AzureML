# Azure ML Compute Instance Workshop Guide

This guide explains how to run the Azure ML pipelines and H2O notebooks from an Azure Machine Learning compute instance. Commands are written for the Linux Bash terminal available in Azure ML Studio.

The guide uses placeholders and the repository-root `.env` file. Do not place passwords, client secrets, access tokens, storage keys, or connection strings in `.env` or in notebook cells.

The primary workflow uses an existing Python/Conda environment installed on the compute instance. If that environment already provides the Azure ML SDK and CLI support, do not reinstall them. Verify the environment first and install only missing H2O workshop dependencies.

## What You Will Run

The customer workshop has two independent entry points:

1. Azure ML CLI jobs under `pipelines/`.
2. H2O binary-model notebooks under `notebooks/h2o_mojo/`.

The pipeline smoke tests do not depend on the H2O notebook artifacts. The H2O notebooks must be run in numeric order because later notebooks consume artifacts created by earlier notebooks.

## Required Azure Resources

Before starting, confirm that the target environment has:

- An Azure subscription and resource group.
- An Azure ML workspace.
- A running Azure ML compute instance for interactive work.
- An Azure ML compute cluster for submitted jobs.
- The workspace default blob datastore.
- For Notebook 04, a user-assigned managed identity for the online endpoint.
- For Notebook 05, a compute managed identity and an ADLS Gen2 output datastore.

Common access requirements include:

- Permission to read the workspace and submit Azure ML jobs, commonly through the `AzureML Data Scientist` role.
- Data-plane access to the workspace storage used for local code and data uploads.
- Permission to create or update models, environments, endpoints, deployments, jobs, and schedules when the corresponding notebook switches are enabled.
- Data-plane access for the endpoint and compute identities to read model artifacts and write pipeline outputs.

The exact role assignments and network rules depend on the customer's Azure design. The compute instance must be able to reach the Azure ML control plane, workspace storage, container registry, and any configured output datastore.

## 1. Open the Compute Instance Terminal

1. Open Azure ML Studio.
2. Select **Compute** and confirm the compute instance is running.
3. Open **Notebooks** and then open a terminal attached to that compute instance.
4. Clone or open the repository on the compute instance.

```bash
git clone --branch workshop <REPOSITORY_URL>
cd MLOPs-AzureML
```

For an existing clone:

```bash
cd <REPOSITORY_DIRECTORY>
git fetch origin
git switch workshop
git pull --ff-only origin workshop
```

All commands in this guide run from the repository root unless stated otherwise.

## 2. Verify System Dependencies

The workshop expects:

- Git.
- Azure CLI with the Azure ML v2 `ml` extension.
- A Python environment installed on the compute instance.
- JDK 17 for H2O.

```bash
git --version
az version
conda env list
java -version
```

The Azure CLI `ml` extension is installed at the Azure CLI level; it is separate from Python packages in a Conda environment. Check it before installing anything:

```bash
az extension show --name ml \
  --query '{name:name,version:version}' \
  --output table
```

Only if that command reports that the extension is missing, install it:

```bash
az extension add --name ml --yes
```

If JDK 17 is unavailable and the compute image permits package installation:

```bash
sudo apt-get update
sudo apt-get install -y openjdk-17-jre-headless
java -version
```

If the compute image does not provide a compatible Python environment or permit JDK installation, use a compute image that includes these dependencies or ask the workspace administrator to install them.

## 3. Activate the Existing Azure ML Environment

In this guide, an existing environment means a Conda/Python environment installed on the compute instance and visible in `conda env list` or the notebook kernel picker. An Azure ML environment asset referenced by a job as `azureml:<ENVIRONMENT_NAME>:<VERSION>` runs submitted jobs but cannot be activated in the compute-instance terminal unless it is also installed there.

The activated compute-instance environment controls terminal commands and interactive notebook execution. Submitted pipeline steps run on the target compute cluster with the environments declared by their YAML job or component definitions.

Initialize Conda in the terminal if needed, then activate the existing environment that contains the Azure ML SDK dependencies:

```bash
source "$(conda info --base)/etc/profile.d/conda.sh"
conda env list
conda activate <COMPUTE_INSTANCE_ENV_NAME>

which python
python --version
```

Verify the required Python packages from that activated environment:

```bash
python - <<'PY'
from importlib.metadata import PackageNotFoundError, version

packages = (
  "h2o",
  "azureml-inference-server-http",
  "azure-ai-ml",
  "azure-identity",
  "azureml-mlflow",
  "mlflow",
  "python-dotenv",
  "pandas",
  "numpy",
  "ipykernel",
)

missing = []
for package in packages:
  try:
    print(f"{package}: {version(package)}")
  except PackageNotFoundError:
    missing.append(package)

if missing:
  raise SystemExit("Missing packages: " + ", ".join(missing))

required_versions = {
  "h2o": "3.46.0.12",
  "azureml-inference-server-http": "1.4.1",
}
incorrect = [
  f"{package}=={version(package)} (expected {expected})"
  for package, expected in required_versions.items()
  if version(package) != expected
]
if incorrect:
  raise SystemExit("Version mismatch: " + "; ".join(incorrect))
PY
```

If this check succeeds, no Python installation is needed. The requirements file documents the complete tested dependency set, including:

- `h2o==3.46.0.12`
- `azureml-inference-server-http==1.4.1`
- `azure-ai-ml==1.28.1`
- `azure-identity==1.24.0b1`
- `azureml-mlflow==1.60.0.post1`
- `mlflow==2.22.1`
- `python-dotenv==1.1.1`
- NumPy, pandas, scikit-learn, PyArrow, JupyterLab, and IPython

If only the H2O workshop packages are missing, install those packages into the active environment:

```bash
python -m pip install \
  h2o==3.46.0.12 \
  azureml-inference-server-http==1.4.1 \
  python-dotenv==1.1.1
```

If the existing environment is missing most dependencies, either install the complete tested set or use a separate environment rather than modifying a shared environment:

```bash
python -m pip install -r notebooks/requirements.txt
```

The existing environment may already appear in the Azure ML notebook kernel picker. If it does not, register the active environment once:

```bash
ENV_NAME="$(basename "$CONDA_PREFIX")"
python -m ipykernel install --user \
  --name "$ENV_NAME" \
  --display-name "Python ($ENV_NAME)"
```

Optional isolation fallback: create a repository-local virtual environment only when no suitable compute-instance environment exists:

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip setuptools wheel
python -m pip install -r notebooks/requirements.txt
```

## 4. Configure `.env`

Create the private environment file:

```bash
cp .env.example .env
chmod 600 .env
```

Edit `.env` with the customer's Azure resource identifiers:

```bash
nano .env
```

Required shared values:

```dotenv
AZURE_SUBSCRIPTION_ID=<SUBSCRIPTION_ID>
AZURE_TENANT_ID=<TENANT_ID>
AZURE_RESOURCE_GROUP=<RESOURCE_GROUP_NAME>
AZUREML_WORKSPACE_NAME=<AZURE_ML_WORKSPACE_NAME>
AZUREML_COMPUTE_NAME=<AML_COMPUTE_CLUSTER_NAME>
```

Additional values are required by Notebooks 04 and 05. Use `.env.example` as the complete reference.

Safety switches are disabled in the committed template:

```dotenv
REGISTER_IN_AZURE=false
DEPLOY_TO_AZURE=false
PROMOTE_TRAFFIC_AFTER_VALIDATION=false
DELETE_ENDPOINT_AFTER_TEST=false
SUBMIT_TO_AZURE=false
CREATE_TEST_SCHEDULE=false
DISABLE_SCHEDULE_AFTER_TEST=true
DELETE_SCHEDULE_AFTER_TEST=false
```

The notebooks load `.env` with `python-dotenv`. Existing process environment variables take precedence. The Azure CLI does not automatically load `.env`; the pipeline commands below export it explicitly.

`.env` is ignored by Git. Confirm before continuing:

```bash
git check-ignore .env
```

Do not add credentials to `.env`. Authentication is handled separately.

## 5. Authenticate to Azure

A compute instance may use either its managed identity or an interactive Azure CLI session.

Use managed identity when it has the required workspace permissions:

```bash
az login --identity
```

Otherwise use interactive sign-in:

```bash
az login --tenant "<TENANT_ID>" --use-device-code
```

Select and verify the subscription:

```bash
az account set --subscription "<SUBSCRIPTION_ID>"
az account show --query '{subscription:name,tenantId:tenantId}' --output table
```

Confirm workspace and compute access:

```bash
az ml workspace show \
  --subscription "<SUBSCRIPTION_ID>" \
  --resource-group "<RESOURCE_GROUP_NAME>" \
  --name "<AZURE_ML_WORKSPACE_NAME>" \
  --query '{name:name,location:location}' \
  --output table

az ml compute show \
  --subscription "<SUBSCRIPTION_ID>" \
  --resource-group "<RESOURCE_GROUP_NAME>" \
  --workspace-name "<AZURE_ML_WORKSPACE_NAME>" \
  --name "<AML_COMPUTE_CLUSTER_NAME>" \
  --query '{name:name,state:provisioning_state}' \
  --output table
```

## 6. Run the Azure ML Pipelines

Load the non-secret resource identifiers from `.env` into the current terminal:

```bash
set -a
source .env
set +a
```

### Single-Step Merge Smoke Test

The YAML contains a sample compute name, so override it with the customer's compute cluster:

```bash
JOB_NAME=$(az ml job create \
  --file pipelines/single-step-merge-job.yaml \
  --subscription "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --workspace-name "$AZUREML_WORKSPACE_NAME" \
  --set compute="azureml:$AZUREML_COMPUTE_NAME" \
  --query name \
  --output tsv)

echo "Submitted job: $JOB_NAME"
```

Stream the logs and check the final status:

```bash
az ml job stream \
  --name "$JOB_NAME" \
  --subscription "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --workspace-name "$AZUREML_WORKSPACE_NAME"

az ml job show \
  --name "$JOB_NAME" \
  --subscription "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --workspace-name "$AZUREML_WORKSPACE_NAME" \
  --query '{name:name,status:status}' \
  --output table
```

Download the merged output when needed:

```bash
az ml job download \
  --name "$JOB_NAME" \
  --subscription "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --workspace-name "$AZUREML_WORKSPACE_NAME" \
  --output-name merged_data \
  --download-path ./job-output
```

### Integration Compare Pipeline

The customer version runs:

```text
merge -> transform -> train -> predict -> compare
```

The external registry registration step is disabled.

Validate the pipeline before submission:

```bash
az ml job validate \
  --file pipelines/integration-compare-pipeline.yaml \
  --subscription "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --workspace-name "$AZUREML_WORKSPACE_NAME" \
  --set settings.default_compute="azureml:$AZUREML_COMPUTE_NAME" \
  --set inputs.automl_compute="$AZUREML_COMPUTE_NAME"
```

Submit and capture one pipeline run name:

```bash
PIPELINE_JOB_NAME=$(az ml job create \
  --file pipelines/integration-compare-pipeline.yaml \
  --subscription "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --workspace-name "$AZUREML_WORKSPACE_NAME" \
  --set settings.default_compute="azureml:$AZUREML_COMPUTE_NAME" \
  --set inputs.automl_compute="$AZUREML_COMPUTE_NAME" \
  --query name \
  --output tsv)

echo "Submitted pipeline: $PIPELINE_JOB_NAME"
```

Monitor the same run without resubmitting it:

```bash
az ml job stream \
  --name "$PIPELINE_JOB_NAME" \
  --subscription "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --workspace-name "$AZUREML_WORKSPACE_NAME"

az ml job list \
  --subscription "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --workspace-name "$AZUREML_WORKSPACE_NAME" \
  --parent-job-name "$PIPELINE_JOB_NAME" \
  --query '[].{component:display_name,status:status}' \
  --output table
```

## 7. Run the H2O Notebooks

In Azure ML Studio, browse to `notebooks/h2o_mojo/`, open each notebook, attach the compute instance, and select the same existing environment activated in the terminal. If you registered it in Section 3, the kernel is displayed as:

```text
Python (<COMPUTE_INSTANCE_ENV_NAME>)
```

Run the notebooks in order. Do not skip ahead unless the required model and data assets already exist.

### Notebook 01: Create the Reference Binary Model

File: `01_create_reference_mojo.ipynb`

Purpose:

- Train a small H2O GBM model.
- Save the version-specific H2O binary model.
- Create golden input and expected prediction files.
- Verify save/load prediction parity.

Keep `REGISTER_IN_AZURE=false` for the normal local preparation flow. Outputs are written below `tmp/h2o_binary/taxi_fare/`.

### Notebook 02: Validate and Register the Customer Model

File: `02_onboard_customer_mojo.ipynb`

Purpose:

- Validate the manifest and SHA-256 checksums.
- Load the H2O binary model with the matching H2O version.
- Confirm golden prediction parity.
- Optionally register the model as an Azure ML custom model.

For local validation only:

```dotenv
REGISTER_IN_AZURE=false
```

To register the validated model, set the following in `.env`, rerun the configuration cell, and then run the registration cell:

```dotenv
REGISTER_IN_AZURE=true
```

### Notebook 03: Test the Local Inference Server

File: `03_test_local_online_endpoint.ipynb`

Purpose:

- Generate the Azure ML scoring script.
- Start `azureml-inference-server-http` locally.
- Start a loopback H2O server.
- Verify health, valid scoring, invalid-input rejection, and cleanup.

This notebook does not create Azure resources. Ports `5001` and `54321` must be available on the compute instance.

### Notebook 04: Deploy a Managed Online Endpoint

File: `04_deploy_managed_online_endpoint.ipynb`

Complete the Notebook 04 values in `.env`, especially:

```dotenv
AZUREML_ONLINE_ENDPOINT_NAME=<UNIQUE_ENDPOINT_NAME>
AZUREML_ONLINE_DEPLOYMENT_NAME=blue
AZUREML_ONLINE_ENDPOINT_IDENTITY_ID=<USER_ASSIGNED_IDENTITY_RESOURCE_ID>
AZUREML_ONLINE_INSTANCE_TYPE=Standard_DS3_v2
```

Recommended staged execution:

1. Start with `DEPLOY_TO_AZURE=false` and run the configuration/package cells.
2. Set `DEPLOY_TO_AZURE=true` and keep `PROMOTE_TRAFFIC_AFTER_VALIDATION=false`.
3. Rerun the configuration cell, then create and directly validate the deployment.
4. After validation, set `PROMOTE_TRAFFIC_AFTER_VALIDATION=true`, rerun the configuration cell, and run the traffic-promotion section.
5. Set `DELETE_ENDPOINT_AFTER_TEST=true` only when the endpoint should be removed.

Managed online endpoints incur charges while deployed.

### Notebook 05: Build and Schedule the Batch Scoring Pipeline

File: `05_build_and_schedule_scoring_pipeline.ipynb`

Complete these `.env` values:

```dotenv
AZUREML_COMPUTE_NAME=<AML_COMPUTE_CLUSTER_NAME>
AZUREML_COMPUTE_IDENTITY_CLIENT_ID=<COMPUTE_MANAGED_IDENTITY_CLIENT_ID>
AZUREML_OUTPUT_DATASTORE=<ADLS_GEN2_DATASTORE_NAME>
AZUREML_BATCH_EXPERIMENT_NAME=h2o-binary-batch-scoring
AZUREML_BATCH_SCHEDULE_NAME=h2o-taxi-batch-test-schedule
```

Recommended staged execution:

1. Keep `SUBMIT_TO_AZURE=false` and run the local scoring validation.
2. Set `SUBMIT_TO_AZURE=true`, rerun the configuration cell, and submit one manual pipeline job.
3. Verify the manual job and its outputs.
4. Set `CREATE_TEST_SCHEDULE=true` only when testing the schedule.
5. Keep `DISABLE_SCHEDULE_AFTER_TEST=true` so the test schedule is disabled after its first observed run.
6. Set `DELETE_SCHEDULE_AFTER_TEST=true` only when the schedule should be deleted.

Scheduled jobs and active endpoints can create ongoing Azure charges.

## 8. Clear Outputs Before Sharing or Committing

Azure SDK logs, H2O startup logs, and exception messages can contain usernames, absolute paths, subscription IDs, resource-group names, workspace names, storage URLs, and run URLs.

Clear all outputs before sharing the notebooks:

```bash
# Run from the same activated compute-instance environment used for the notebooks.
python -m jupyter nbconvert --clear-output --inplace \
  notebooks/h2o_mojo/01_create_reference_mojo.ipynb \
  notebooks/h2o_mojo/02_onboard_customer_mojo.ipynb \
  notebooks/h2o_mojo/03_test_local_online_endpoint.ipynb \
  notebooks/h2o_mojo/04_deploy_managed_online_endpoint.ipynb \
  notebooks/h2o_mojo/05_build_and_schedule_scoring_pipeline.ipynb
```

Verify that `.env` is not staged:

```bash
git status --short
git check-ignore .env
```

Never commit `.env`, downloaded job outputs, generated model bundles, or temporary scoring packages.

## 9. Troubleshooting

### `uv` reports `invalid peer certificate: UnknownIssuer`

This usually means a corporate proxy or TLS-inspection service presents a certificate signed by an internal CA. The operating system trusts that CA, but `uv` uses its bundled Mozilla roots by default. Use the operating system certificate store without disabling verification:

```bash
export UV_SYSTEM_CERTS=true
uv pip install \
  --python "$(which python)" \
  --requirement notebooks/requirements.txt
```

If `uv pip install --help` shows `--native-tls` instead of `--system-certs`, use `export UV_NATIVE_TLS=true`; it is the name used by older `uv` releases.

If the environment is not activated, replace `$(which python)` with its actual interpreter path. If system certificates still fail, ask the administrator for the approved PEM CA bundle and use `SSL_CERT_FILE=/path/to/company-ca-bundle.pem` or `uv pip install --cert /path/to/company-ca-bundle.pem ...`.

Do not use `--allow-insecure-host` for PyPI; it disables certificate verification.

### `az ml job create` reports `AuthorizationFailure`

The CLI uploads local code and CSV files to workspace storage before scheduling the job. Check:

- The signed-in identity has workspace job-submission permission.
- The identity has required data-plane access to workspace storage.
- Workspace and storage network rules allow the compute instance.
- The selected subscription, resource group, and workspace are correct.

### Compute target not found

Override both integration pipeline compute references:

```bash
--set settings.default_compute="azureml:$AZUREML_COMPUTE_NAME" \
--set inputs.automl_compute="$AZUREML_COMPUTE_NAME"
```

For the single-step command job, use:

```bash
--set compute="azureml:$AZUREML_COMPUTE_NAME"
```

### H2O binary model cannot be loaded

Binary H2O models are version-specific. Confirm:

```bash
python -c 'import h2o; print(h2o.__version__)'
```

The expected version is `3.46.0.12`.

### Notebook kernel is missing

Register it again:

```bash
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate <COMPUTE_INSTANCE_ENV_NAME>
ENV_NAME="$(basename "$CONDA_PREFIX")"
python -m ipykernel install --user \
  --name "$ENV_NAME" \
  --display-name "Python ($ENV_NAME)"
```

Then refresh the Azure ML Studio browser page and reselect the compute instance and kernel.

### Local inference server ports are busy

Notebook 03 requires ports `5001` and `54321`. Stop the old process or restart the compute instance before rerunning the notebook.

### Package imports fail after installation

Confirm that the notebook is attached to the same activated compute-instance environment. First run `which python` in the terminal, then run this in a notebook cell:

```python
import sys
print(sys.executable)
```

The notebook path should identify the same Conda environment shown by the terminal. If it does not, reselect the kernel in Azure ML Studio.
