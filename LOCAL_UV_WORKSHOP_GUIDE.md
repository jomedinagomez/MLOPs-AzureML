# Local Workshop Guide with uv

This guide explains how to run the Azure ML pipelines and H2O notebooks from a local Windows computer using `uv` to manage Python. Commands use PowerShell and assume the repository is on the `workshop` branch.

The local `uv` environment runs the interactive notebooks and local validation code. Azure ML pipeline steps run remotely on the compute target with the environments declared in their YAML job or component definitions.

Do not store passwords, client secrets, access tokens, storage keys, or connection strings in `.env`, notebook cells, or shell history.

## 1. Prerequisites

Install or confirm these tools:

- Git
- `uv`
- Azure CLI
- JDK 17 for H2O
- Visual Studio Code with the Python and Jupyter extensions, or JupyterLab

Check what is already installed:

```powershell
git --version
uv --version
az version
java -version
```

### Install uv

With WinGet:

```powershell
winget install --id astral-sh.uv --exact
```

Alternatively, use the official PowerShell installer:

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex"
```

Close and reopen PowerShell if `uv` is not immediately found, then run:

```powershell
uv --version
```

### Install Azure CLI

Install Azure CLI only if `az` is unavailable:

```powershell
winget install --id Microsoft.AzureCLI --exact
```

Close and reopen PowerShell after installation.

The Azure CLI `ml` extension is separate from the Python packages managed by `uv`. Check it first:

```powershell
az extension show --name ml --query "{name:name,version:version}" --output table
```

Install it only if the check reports that it is missing:

```powershell
az extension add --name ml --yes
```

### Install JDK 17

H2O requires Java. Install Microsoft OpenJDK 17 if `java -version` is unavailable or reports an incompatible version:

```powershell
winget install --id Microsoft.OpenJDK.17 --exact
```

Close and reopen PowerShell, then verify:

```powershell
java -version
```

## 2. Clone or Update the Repository

For a new clone:

```powershell
git clone --branch workshop <REPOSITORY_URL>
Set-Location MLOPs-AzureML
```

For an existing clone:

```powershell
Set-Location <REPOSITORY_DIRECTORY>
git fetch origin
git switch workshop
git pull --ff-only origin workshop
```

Run the remaining commands from the repository root.

## 3. Create the uv Environment

Install a managed Python 3.12 interpreter:

```powershell
uv python install 3.12
uv python list
```

Create a repository-local virtual environment:

```powershell
uv venv --python 3.12 .venv
```

Install the tested notebook dependencies from the existing requirements file:

```powershell
uv pip install `
  --python .\.venv\Scripts\python.exe `
  --requirement .\notebooks\requirements.txt

uv pip check --python .\.venv\Scripts\python.exe
```

The requirements include:

- `h2o==3.46.0.12`
- `azureml-inference-server-http==1.4.1`
- `azure-ai-ml==1.28.1`
- `azure-identity==1.24.0b1`
- `azureml-mlflow==1.60.0.post1`
- `mlflow==2.22.1`
- `python-dotenv==1.1.1`
- JupyterLab, IPykernel, NumPy, pandas, scikit-learn, SciPy, and PyArrow

Activate the environment when working interactively in PowerShell:

```powershell
& .\.venv\Scripts\Activate.ps1
python --version
```

Activation is optional. Every command in this guide can instead call `.venv\Scripts\python.exe` directly.

## 4. Verify the Python Dependencies

Run this verification from the repository root:

```powershell
$verify = @'
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
'@

$verify | & .\.venv\Scripts\python.exe -
```

The H2O and local inference-server versions must match exactly because H2O binary models are version-specific.

## 5. Register the Notebook Kernel

Register the `uv` environment once:

```powershell
& .\.venv\Scripts\python.exe -m ipykernel install --user `
  --name mlops-azureml-workshop `
  --display-name "Python (uv - Azure ML workshop)"

& .\.venv\Scripts\python.exe -m jupyter kernelspec list
```

In VS Code:

1. Open a notebook under `notebooks/h2o_mojo/`.
2. Select **Kernel**.
3. Select **Python Environments** or **Jupyter Kernel**.
4. Choose **Python (uv - Azure ML workshop)**.

To use JupyterLab instead:

```powershell
& .\.venv\Scripts\python.exe -m jupyter lab
```

## 6. Configure .env

Create the private local configuration file without overwriting an existing one:

```powershell
if (-not (Test-Path .env)) {
    Copy-Item .env.example .env
}

notepad .env
```

At minimum, provide the target Azure identifiers and compute cluster:

```dotenv
AZURE_SUBSCRIPTION_ID=<SUBSCRIPTION_ID>
AZURE_TENANT_ID=<TENANT_ID>
AZURE_RESOURCE_GROUP=<RESOURCE_GROUP_NAME>
AZUREML_WORKSPACE_NAME=<AZURE_ML_WORKSPACE_NAME>
AZUREML_COMPUTE_NAME=<AML_COMPUTE_CLUSTER_NAME>
```

Use `.env.example` as the complete reference for Notebooks 04 and 05.

Keep all mutation switches disabled during initial validation:

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

The notebooks load `.env` through `python-dotenv`. Existing process environment variables take precedence.

Confirm that Git ignores the populated file:

```powershell
git check-ignore .env
```

## 7. Authenticate and Check Network Access

Sign in to the customer's tenant without adding an Azure ML resource scope:

```powershell
az login --tenant "<TENANT_ID>"
az account set --subscription "<SUBSCRIPTION_ID>"
az account show --query "{subscription:name,tenantId:tenantId}" --output table
```

Use device-code authentication if a browser cannot be launched:

```powershell
az login --tenant "<TENANT_ID>" --use-device-code
```

Verify workspace and compute access:

```powershell
az ml workspace show `
  --subscription "<SUBSCRIPTION_ID>" `
  --resource-group "<RESOURCE_GROUP_NAME>" `
  --name "<AZURE_ML_WORKSPACE_NAME>" `
  --query "{name:name,location:location}" `
  --output table

az ml compute show `
  --subscription "<SUBSCRIPTION_ID>" `
  --resource-group "<RESOURCE_GROUP_NAME>" `
  --workspace-name "<AZURE_ML_WORKSPACE_NAME>" `
  --name "<AML_COMPUTE_CLUSTER_NAME>" `
  --query "{name:name,state:provisioning_state}" `
  --output table
```

### Public IP or private network requirement

A local computer must satisfy the workspace and storage network rules. Find the current public IPv4 address:

```powershell
$publicIp = (Invoke-RestMethod -Uri "https://api.ipify.org").Trim()
Write-Host "Current public IP: $publicIp"
```

If the workspace uses selected public IPs, an administrator must allow this address on the workspace and any storage account used for local uploads.

If the workspace notebook or API hostname resolves to a private address such as `10.x.x.x`, the local computer needs VPN, ExpressRoute, or another routed connection to the Azure virtual network. Test DNS and TCP connectivity with:

```powershell
Resolve-DnsName "<AZURE_ML_HOSTNAME>"
Test-NetConnection "<AZURE_ML_HOSTNAME>" -Port 443
```

Being able to open the Azure portal does not prove that the local computer can reach private Azure ML or storage endpoints.

## 8. Load .env into PowerShell for CLI Commands

The Azure CLI does not load `.env` automatically. Use `python-dotenv` from the `uv` environment to parse it safely into the current PowerShell process:

```powershell
$settingsJson = & .\.venv\Scripts\python.exe -c `
  'from dotenv import dotenv_values; import json; print(json.dumps(dotenv_values(".env")))'

$settings = $settingsJson | ConvertFrom-Json
$settings.PSObject.Properties | ForEach-Object {
    if ($null -ne $_.Value) {
        Set-Item -Path "Env:$($_.Name)" -Value ([string]$_.Value)
    }
}
```

Verify only the non-sensitive resource names needed by the CLI:

```powershell
[pscustomobject]@{
    ResourceGroup = $env:AZURE_RESOURCE_GROUP
    Workspace     = $env:AZUREML_WORKSPACE_NAME
    Compute       = $env:AZUREML_COMPUTE_NAME
} | Format-Table
```

## 9. Run the Azure ML Pipelines

### Single-Step Merge Smoke Test

Submit the job from the repository root and override the sample compute name in the YAML:

```powershell
$jobName = az ml job create `
  --file .\pipelines\single-step-merge-job.yaml `
  --subscription $env:AZURE_SUBSCRIPTION_ID `
  --resource-group $env:AZURE_RESOURCE_GROUP `
  --workspace-name $env:AZUREML_WORKSPACE_NAME `
  --set compute="azureml:$env:AZUREML_COMPUTE_NAME" `
  --query name `
  --output tsv

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($jobName)) {
    throw "Azure ML job submission failed."
}

$jobName = $jobName.Trim()
Write-Host "Submitted job: $jobName"
```

Stream and inspect that same job:

```powershell
az ml job stream `
  --name $jobName `
  --subscription $env:AZURE_SUBSCRIPTION_ID `
  --resource-group $env:AZURE_RESOURCE_GROUP `
  --workspace-name $env:AZUREML_WORKSPACE_NAME

az ml job show `
  --name $jobName `
  --subscription $env:AZURE_SUBSCRIPTION_ID `
  --resource-group $env:AZURE_RESOURCE_GROUP `
  --workspace-name $env:AZUREML_WORKSPACE_NAME `
  --query "{name:name,status:status}" `
  --output table
```

Download the merged output if needed:

```powershell
az ml job download `
  --name $jobName `
  --subscription $env:AZURE_SUBSCRIPTION_ID `
  --resource-group $env:AZURE_RESOURCE_GROUP `
  --workspace-name $env:AZUREML_WORKSPACE_NAME `
  --output-name merged_data `
  --download-path .\job-output
```

### Integration Compare Pipeline

The customer version runs:

```text
merge -> transform -> train -> predict -> compare
```

The external registry registration step is disabled.

Validate before submitting:

```powershell
az ml job validate `
  --file .\pipelines\integration-compare-pipeline.yaml `
  --subscription $env:AZURE_SUBSCRIPTION_ID `
  --resource-group $env:AZURE_RESOURCE_GROUP `
  --workspace-name $env:AZUREML_WORKSPACE_NAME `
  --set settings.default_compute="azureml:$env:AZUREML_COMPUTE_NAME" `
  --set inputs.automl_compute="$env:AZUREML_COMPUTE_NAME"
```

Submit once and capture the pipeline run name:

```powershell
$pipelineJobName = az ml job create `
  --file .\pipelines\integration-compare-pipeline.yaml `
  --subscription $env:AZURE_SUBSCRIPTION_ID `
  --resource-group $env:AZURE_RESOURCE_GROUP `
  --workspace-name $env:AZUREML_WORKSPACE_NAME `
  --set settings.default_compute="azureml:$env:AZUREML_COMPUTE_NAME" `
  --set inputs.automl_compute="$env:AZUREML_COMPUTE_NAME" `
  --query name `
  --output tsv

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($pipelineJobName)) {
    throw "Azure ML pipeline submission failed."
}

$pipelineJobName = $pipelineJobName.Trim()
Write-Host "Submitted pipeline: $pipelineJobName"
```

Monitor the same run without resubmitting it:

```powershell
az ml job stream `
  --name $pipelineJobName `
  --subscription $env:AZURE_SUBSCRIPTION_ID `
  --resource-group $env:AZURE_RESOURCE_GROUP `
  --workspace-name $env:AZUREML_WORKSPACE_NAME

az ml job list `
  --subscription $env:AZURE_SUBSCRIPTION_ID `
  --resource-group $env:AZURE_RESOURCE_GROUP `
  --workspace-name $env:AZUREML_WORKSPACE_NAME `
  --parent-job-name $pipelineJobName `
  --query "[].{component:display_name,status:status}" `
  --output table
```

## 10. Run the H2O Notebooks

Open `notebooks/h2o_mojo/` in VS Code or JupyterLab, select **Python (uv - Azure ML workshop)**, and run the notebooks in numeric order.

| Notebook | Purpose | Azure mutation control |
|----------|---------|------------------------|
| `01_create_reference_mojo.ipynb` | Train, save, reload, and verify the H2O binary model | Keep `REGISTER_IN_AZURE=false` for local preparation |
| `02_onboard_customer_mojo.ipynb` | Validate the binary bundle and optionally register it | Set `REGISTER_IN_AZURE=true` only when registration is intended |
| `03_test_local_online_endpoint.ipynb` | Test the scoring script with the local Azure ML inference server | No Azure resources are created |
| `04_deploy_managed_online_endpoint.ipynb` | Create and validate a managed online endpoint | Controlled by `DEPLOY_TO_AZURE`, `PROMOTE_TRAFFIC_AFTER_VALIDATION`, and `DELETE_ENDPOINT_AFTER_TEST` |
| `05_build_and_schedule_scoring_pipeline.ipynb` | Build, submit, and optionally schedule batch scoring | Controlled by `SUBMIT_TO_AZURE`, `CREATE_TEST_SCHEDULE`, `DISABLE_SCHEDULE_AFTER_TEST`, and `DELETE_SCHEDULE_AFTER_TEST` |

Important dependencies between notebooks:

1. Notebook 01 writes the H2O binary model and golden fixtures under `tmp/h2o_binary/taxi_fare/`.
2. Notebook 02 validates those files and can register the model.
3. Notebook 03 consumes the local model bundle and requires ports `5001` and `54321`.
4. Notebook 04 expects the model to be registered in the configured Azure ML workspace.
5. Notebook 05 expects the registered model, compute identity, and ADLS Gen2 output datastore configured in `.env`.

Start with all Azure mutation switches disabled. Change a switch in `.env`, then rerun the notebook's configuration cell before running the corresponding Azure section.

Managed online endpoints, compute jobs, and schedules can incur Azure charges.

## 11. Clear Notebook Outputs Before Sharing

Notebook outputs can contain usernames, absolute paths, subscription IDs, workspace names, storage URLs, and run URLs. Clear them before committing or sharing:

```powershell
& .\.venv\Scripts\python.exe -m jupyter nbconvert --clear-output --inplace `
  .\notebooks\h2o_mojo\01_create_reference_mojo.ipynb `
  .\notebooks\h2o_mojo\02_onboard_customer_mojo.ipynb `
  .\notebooks\h2o_mojo\03_test_local_online_endpoint.ipynb `
  .\notebooks\h2o_mojo\04_deploy_managed_online_endpoint.ipynb `
  .\notebooks\h2o_mojo\05_build_and_schedule_scoring_pipeline.ipynb
```

Verify that the private configuration and generated artifacts are not staged:

```powershell
git status --short
git check-ignore .env
git check-ignore tmp\h2o_binary\taxi_fare\model_manifest.json
```

Never commit `.env`, downloaded job outputs, generated model bundles, or temporary scoring packages.

## 12. Update or Rebuild the Environment

Reapply the checked-in requirements after pulling dependency changes:

```powershell
uv pip install `
  --python .\.venv\Scripts\python.exe `
  --requirement .\notebooks\requirements.txt

uv pip check --python .\.venv\Scripts\python.exe
```

To rebuild from scratch:

```powershell
Remove-Item -Recurse -Force .venv
uv venv --python 3.12 .venv
uv pip install `
  --python .\.venv\Scripts\python.exe `
  --requirement .\notebooks\requirements.txt
```

Register the kernel again after rebuilding:

```powershell
& .\.venv\Scripts\python.exe -m ipykernel install --user `
  --name mlops-azureml-workshop `
  --display-name "Python (uv - Azure ML workshop)"
```

## 13. Troubleshooting

### uv reports `invalid peer certificate: UnknownIssuer`

This usually means a corporate proxy or TLS-inspection service presents a certificate signed by an internal CA. Windows trusts that CA, but `uv` uses its bundled Mozilla roots by default. Tell `uv` to use the Windows certificate store without disabling verification:

```powershell
$env:UV_SYSTEM_CERTS = "true"

uv pip install `
  --python .\.venv\Scripts\python.exe `
  --requirement .\notebooks\requirements.txt
```

To persist this for your user account:

```powershell
[Environment]::SetEnvironmentVariable("UV_SYSTEM_CERTS", "true", "User")
```

Open a new terminal after setting it persistently. If system certificates still fail, ask IT for the approved PEM CA bundle and set `SSL_CERT_FILE` to that file or pass `--cert <CA_BUNDLE_PATH>` to `uv pip install`.

If `uv pip install --help` shows `--native-tls` instead of `--system-certs`, use `$env:UV_NATIVE_TLS = "true"`; it is the name used by older `uv` releases.

Do not use `--allow-insecure-host` for PyPI; it disables certificate verification.

### PowerShell blocks environment activation

Activation is optional. Run the environment's Python directly:

```powershell
& .\.venv\Scripts\python.exe --version
```

For the current process only, activation can also be enabled with:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
& .\.venv\Scripts\Activate.ps1
```

### The notebook uses the wrong Python

Run this in a notebook cell:

```python
import sys
print(sys.executable)
```

It should end with `.venv\Scripts\python.exe`. Otherwise, select **Python (uv - Azure ML workshop)** again.

### H2O cannot start

Verify Java and the exact H2O version:

```powershell
java -version
& .\.venv\Scripts\python.exe -c "import h2o; print(h2o.__version__)"
```

The expected H2O version is `3.46.0.12`.

### `az ml job create` reports `AuthorizationFailure`

The CLI uploads local code and data to workspace storage before scheduling the job. Check:

- Azure login, tenant, and subscription selection.
- Workspace job-submission RBAC.
- Data-plane RBAC on workspace storage.
- Workspace and storage network rules for the local public IP.
- Private endpoint DNS and routing when the workspace is private.

### The browser opens Azure ML Studio but notebooks or files fail

Portal access does not guarantee data-plane access. Verify the local computer can reach the workspace notebook endpoint and workspace storage. If DNS resolves to private IP addresses, connect to the required VPN or private network first.

### Notebook 03 reports busy ports

Check and stop stale processes using ports `5001` or `54321`:

```powershell
Get-NetTCPConnection -LocalPort 5001,54321 -ErrorAction SilentlyContinue
```

Restarting VS Code or the local computer also clears orphaned local inference processes.
