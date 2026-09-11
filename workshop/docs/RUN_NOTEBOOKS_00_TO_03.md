# Run Workshop Notebooks 00 Through 03

This is a living runbook. Each notebook is documented only after it has been run successfully on an Azure Machine Learning compute instance.

## Tested Baseline

Verified on September 11, 2026:

- Conda environment: `azureml-workshop`
- Python: `3.12.14`
- OpenJDK: `17.0.18`
- Jupyter kernel: `Azure ML Workshop`
- Azure ML SDK: `azure-ai-ml==1.28.1`
- Azure Identity: `azure-identity==1.24.0b1`
- H2O: `3.46.0.12`
- Dependency check: no broken requirements

The preinstalled environments did not meet the full workshop contract. They used Python 3.10 or 3.13, did not contain the pinned H2O package, and the host provided Java 11. A dedicated Conda environment was selected as the reproducible baseline.

## Create the Environment

From the cloned repository:

```bash
cd /home/azureuser/cloudfiles/code/MLOPs-AzureML/workshop

conda create \
  --name azureml-workshop \
  --override-channels \
  --channel conda-forge \
  --yes \
  python=3.12 openjdk=17 pip

conda activate azureml-workshop
python -m pip install --requirement requirements.txt
python -m pip check
python -m ipykernel install \
  --user \
  --name azureml-workshop \
  --display-name "Azure ML Workshop"
```

`--override-channels --channel conda-forge` avoids requiring acceptance of Anaconda default-channel terms and supplies both Python 3.12 and OpenJDK 17.

Verify the active terminal environment:

```bash
printf 'CONDA_DEFAULT_ENV=%s\n' "$CONDA_DEFAULT_ENV"
command -v python
python --version
command -v java
java -version
```

Expected executable paths begin with `/anaconda/envs/azureml-workshop/`.

Select the **Azure ML Workshop** kernel in every workshop notebook.

## Identity Model

The compute instance and compute cluster use different user-assigned managed identities.

Complete the scoped role assignments in [RBAC.md](RBAC.md) from an administrator environment before running mutation notebooks. Do not run those role-assignment commands while authenticated as a workshop managed identity.

### Compute-instance UMI

The compute-instance UMI authenticates commands and notebook control-plane calls made on the compute instance.

Azure ML exposes its client ID through:

```bash
printf '%s\n' "$DEFAULT_IDENTITY_CLIENT_ID"
```

Confirm that this is the client ID of the UMI attached to the compute instance:

```text
<COMPUTE_INSTANCE_UMI_CLIENT_ID>
```

Authenticate Azure CLI as this identity:

```bash
az login --identity --client-id "$DEFAULT_IDENTITY_CLIENT_ID"
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
```

The notebooks use `AzureCliCredential`. Notebook `00` verifies that the Azure CLI token's client ID matches `DEFAULT_IDENTITY_CLIENT_ID`.

The compute-instance UMI needs an Azure ML role such as **AzureML Data Scientist** on the target workspace for the workshop's control-plane operations.

### Compute-cluster UMI

The cluster UMI authenticates jobs that execute on the configured Azure ML compute cluster.

Record the cluster identity values supplied by the Azure administrator:

```text
Name: <COMPUTE_CLUSTER_UMI_NAME>
Client ID: <COMPUTE_CLUSTER_UMI_CLIENT_ID>
Principal ID: <COMPUTE_CLUSTER_UMI_PRINCIPAL_ID>
```

Notebook `00` retrieves the target cluster and verifies that this client ID is attached. Job-submission notebooks use this value when constructing `ManagedIdentityConfiguration`.

Do not compare the instance and cluster client IDs for equality. They represent separate responsibilities.

## Configure `.env`

Create the ignored runtime configuration:

```bash
cp .env.example .env
```

Set the target environment values in `.env`; retain the required H2O version:

```dotenv
H2O_VERSION=3.46.0.12
```

Keep every mutation switch `false` while running notebook `00`. The file must contain identifiers and switches only, never passwords, keys, secrets, or access tokens.

## Notebook 00: Validate the Workshop

Notebook:

```text
notebooks/00_setup/00_validate_workshop.ipynb
```

Before running it:

1. Activate `azureml-workshop` in the terminal.
2. Select the **Azure ML Workshop** notebook kernel.
3. Complete `workshop/.env`.
4. Run `az login --identity --client-id "$DEFAULT_IDENTITY_CLIENT_ID"`.
5. Confirm the compute-instance UMI has workspace RBAC.

Run the notebook cells in order:

1. Cell 2 imports the SDK and utility packages.
2. Cell 3 loads `.env`, validates required settings, obtains an Azure CLI token, and proves the token belongs to the compute-instance UMI.
3. Cell 4 defines the local preflight helper functions.
4. Cell 5 reads the workspace and cluster, verifies the cluster UMI separately, checks local commands, and displays representative Azure ML assets.
5. Cell 6 runs the final assertions.

### Verified Result

All notebook `00` code cells passed after the identity and workspace checks.


`uv=False` is expected for this tested Conda-based setup and does not fail the notebook.

If repeated execution prints OpenTelemetry messages such as `Attempting to instrument while already instrumented`, restart the kernel and run the notebook once from the top. These are SDK telemetry reuse warnings, not managed-identity failures.

## Foundation Notebook 03: Register an Environment

Notebook:

```text
notebooks/01_foundations/03_register_environment.ipynb
```

Set `REGISTER_FOUNDATION_ENVIRONMENT=true` only while registering the environment. Run Cell 2 and then Cell 3.

The original base image was invalid:

```text
mcr.microsoft.com/azureml/minimal-py310-inference:latest
```

The Microsoft Container Registry manifest endpoint returned HTTP `404`, which later caused `ImageNotFound` even though the SDK had registered and retrieved the environment asset. Retrieving an environment asset does not prove that Azure ML can build its serving image.

The notebook now uses the base image shown in Microsoft's current Azure ML environment documentation:

```text
mcr.microsoft.com/azureml/openmpi4.1.0-ubuntu20.04:latest
```

Its MCR manifest returned HTTP `200`. Cell 3 now checks that manifest before registration and verifies the image recorded on the returned environment asset.

Environment image and Conda properties are immutable. Because version `1` already contained the invalid image in the tested workspace, `.env` was advanced to:

```dotenv
WORKSHOP_ENVIRONMENT_VERSION=2
```

Fresh workspaces can register the corrected definition as version `1`.

### Verified Result

```text
Verified base image manifest: mcr.microsoft.com/azureml/openmpi4.1.0-ubuntu20.04:latest
Registered environment asset: workshop-taxi-environment:2
```

The registered asset was independently retrieved through `MLClient`, and its image matched the corrected MCR reference. Azure ML builds the final serving image lazily when the environment is first used. Notebook `06` is therefore the final environment-build validation.

After registration, set `REGISTER_FOUNDATION_ENVIRONMENT=false`.

## Foundation Notebook 06: Deploy an Online Endpoint

Notebook:

```text
notebooks/01_foundations/06_deploy_online_endpoint.ipynb
```

This notebook uses three distinct identities:

1. The compute-instance UMI authenticates `MLClient` and creates the endpoint and deployment.
2. The configured endpoint UMI is attached to the endpoint and used by the serving runtime.
3. The workspace identity participates in environment image build and workspace dependency access.

Before running Cell 3, an administrator must verify the assignments in [RBAC.md](RBAC.md). In particular, the compute-instance UMI needs `Managed Identity Operator` on the individual endpoint UMI resource.

If endpoint creation reports `LinkedAuthorizationFailed` for `userAssignedIdentities/assign/action`, run the scoped `Managed Identity Operator` command in [RBAC.md](RBAC.md) from the administrator environment.

The endpoint UMI itself also needs `AcrPull` on the workspace ACR and `Storage Blob Data Reader` on workspace storage before deployment. This repository additionally grants it `AzureML Metrics Writer (preview)` on the workspace.

After role propagation, return to the compute instance:

```bash
az login --identity --client-id "$DEFAULT_IDENTITY_CLIENT_ID"
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
```

Then rerun Cells 2-3. Endpoint identity is immutable after creation, so verify `AZUREML_ONLINE_ENDPOINT_IDENTITY_ID` before rerunning.

Notebook `06` is not yet marked successful. The endpoint was not created during the failed attempt.

## Foundation Notebook 05: Submit a Command Job

Notebook:

```text
notebooks/01_foundations/05_submit_command_job.ipynb
```

Prerequisites:

1. Complete notebook `00` successfully.
2. Select the **Azure ML Workshop** kernel.
3. Authenticate Azure CLI with the compute-instance UMI.
4. Confirm `.env` identifies the target cluster and its UMI client ID.
5. Set only `SUBMIT_FOUNDATION_JOB=true`; keep unrelated mutation switches `false`.

Run the notebook cells in order:

1. Cell 2 loads `.env`, creates `MLClient` with the compute-instance UMI's Azure CLI session, and reads the target cluster and cluster UMI settings.
2. Cell 3 constructs the command job, assigns the cluster UMI, submits the job, streams logs, verifies `Completed`, downloads the named output, and verifies `summary.json`.

### Compute target syntax

When constructing a job with the Python SDK `command()` function, pass the bare compute name:

```python
compute=COMPUTE_NAME
```

Do not use `compute=f"azureml:{COMPUTE_NAME}"` in this SDK object. The prefixed value is treated as the literal compute name and fails with:

```text
Unknown compute target 'azureml:<COMPUTE_CLUSTER_NAME>'.
```

The `azureml:<name>` form remains valid in Azure ML YAML references; this distinction applies to the Python SDK field used by this notebook.

### Output retrieval

In `azure-ai-ml==1.28.1`, the completed job's named output is returned as a `NodeOutput`, and its `.path` can be `None`. The notebook therefore uses the supported download API:

```python
ml_client.jobs.download(
  final_job.name,
  output_name="output_data",
  download_path=download_dir,
)
```

The cloud output follows this URI form:

```text
azureml://datastores/<datastore>/paths/azureml/<job-name>/output_data/
```

The downloaded file is stored under:

```text
outputs/foundation_command_job/<job-name>/named-outputs/output_data/summary.json
```

### Verified Result

The command job completed with the configured cluster UMI, processed 5,000 rows and 22 columns, and produced a verified `summary.json`.

The downloaded `summary.json` was found and validated.

These messages were observed but did not fail the job:

```text
pathOnCompute is not a known attribute ... and will be ignored
/azureml-envs/sklearn-1.0/lib/libtinfo.so.6: no version information available
```

The first is an SDK/service response compatibility warning. The second comes from the curated job image's shell library. The job completed and produced the expected artifact despite both messages.

After the exercise, set `SUBMIT_FOUNDATION_JOB=false` to prevent accidental resubmission.

## Jobs Notebook 01: Submit the Single-Step Merge

Notebook:

```text
notebooks/02_jobs_and_pipelines/01_submit_single_step_merge.ipynb
```

Prerequisites:

1. Complete notebook `00` successfully.
2. Select the **Azure ML Workshop** kernel.
3. Authenticate Azure CLI with the compute-instance UMI.
4. Confirm `.env` identifies the target cluster and its UMI client ID.
5. Set only `RUN_SINGLE_STEP_JOB=true`; keep unrelated mutation switches `false`.

Run Cell 2 and then Cell 3. Cell 3 loads the command-job YAML, replaces its placeholder compute, assigns the cluster UMI, submits and streams the job, downloads `merged_data`, and verifies the expected CSV exists.

### Compute target syntax

After `load_job()`, assign the bare compute name in the Python SDK object:

```python
job.compute = COMPUTE_NAME
```

Do not assign `f"azureml:{COMPUTE_NAME}"`. The prefix is valid in the source YAML, but assigning that string through this Python SDK path sends it as a literal compute target and fails with:

```text
Unknown compute target 'azureml:<COMPUTE_CLUSTER_NAME>'.
```

### Output retrieval

The completed job returns `merged_data` as a `NodeOutput`, whose `.path` is `None` with the tested SDK. The notebook uses:

```python
ml_client.jobs.download(
  final_job.name,
  output_name="merged_data",
  download_path=download_dir,
)
```

It then verifies:

```text
outputs/single_step_merge/<job-name>/named-outputs/merged_data/merged_taxi_data.csv
```

### Verified Result

The merge job completed with the configured cluster UMI and produced a verified CSV containing 10,000 rows and 11 columns.

The downloaded CSV had the expected columns:

```text
cost,distance,dropoff_datetime,dropoff_latitude,dropoff_longitude,
passengers,pickup_datetime,pickup_latitude,pickup_longitude,store_forward,vendor
```

The `pathOnCompute` and `libtinfo.so.6` messages are nonfatal SDK/container warnings. The job completed and the output was verified.

After the exercise, set `RUN_SINGLE_STEP_JOB=false` to prevent accidental resubmission.

## Remaining Notebooks

Not documented yet. Continue one notebook at a time.
