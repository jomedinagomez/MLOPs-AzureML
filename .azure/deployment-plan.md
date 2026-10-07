# Azure Deployment Plan

> **Status:** Completed

Generated: 2026-10-05

---

## Standalone Serverless Model Consumption Notebook (2026-10-06)

- Added `04_consume_registered_model_serverless_spark.ipynb` and standalone Spark
  job definition `titanic-serverless-model-consumption.yaml`; no pipeline wrapper,
  endpoint operations, local Spark, or infrastructure change.
- Reused checksum-verified registered model staging and shared output/runtime
  validation. Original inference notebook results and model version 1 retained.
- Verified job `titanic-model-consumption-b239a7b8fb48`, `Completed`, type `spark`,
  `_azureml.ComputeTargetType=amlspark`, E4s v3 resources, runtime 3.5.
- Manifest: actual Spark `3.5.5.5.4.20260824.232707473`, master `yarn`, application
  `application_1791321422909_0001`; registered asset ID, original URI and content
  SHA-256 matched selected model version 1.
- 891 unique predictions, valid binary classes and finite probabilities;
  parity passed against the completed inference pipeline's CSV.
- Canonical notebook has actual executed cells and prediction tables saved.
- Ignored configuration has submission disabled and the successful standalone
  job name set for reuse. Read-only attachment snapshots were not edited.
- Final focused regression suite: 27 passed. Four canonical notebook code cells
  executed successfully; prediction tables and runtime/parity evidence persisted.
  Temporary execution runner removed. Existing inference pipeline and endpoint
  default retained; AML compute cluster remains at current/target nodes `0/0`.

## Serverless Spark Inference Pipeline (2026-10-06)

**Goal:** Submit a plain Azure ML serverless Spark 3.5 inference pipeline and stop
the batch endpoint migration, as requested by the user.

**Scope:**

- Reuse `mlwpublicncus04` in North Central US and registered model
  `workshop-titanic-spark-model:1`; do not retrain or replace it.
- Replace notebook 03's endpoint workflow with
  `03_run_titanic_spark_inference_pipeline.ipynb`.
- Submit `titanic-spark-inference-pipeline.yaml` with the Python jobs SDK.
- Run exactly one `spark_score` child using managed Spark 3.5, user identity,
  serverless E4s v3 resources, and direct URI input/output.
- Resolve the immutable registered model artifact and use a unique ADLS prediction
  directory for each run.
- Save real notebook outputs and verify runtime, model ID, all 891 PassengerIds,
  finite probabilities, binary classes, and parity against the existing reference.
- Do not create, invoke, promote, update, or delete endpoints. Existing
  `titanic-spark-batch-ncus04` deployments and its `sparkml-v1` default are retained.
- No Terraform, persistent compute, storage, environment, or datastore creation is
  needed. Reset the abandoned batch switches immediately.

**Verification:**

- [x] Replace the active YAML/component and notebook endpoint flow.
- [x] Reuse native scoring and strict output/runtime verification.
- [x] Disable abandoned batch mutation switches.
- [x] Pass focused schema, notebook, runtime, and prediction tests.
- [x] Run and complete the serverless inference pipeline.
- [x] Verify actual `amlspark`/`Serverless` execution, model, counts, and parity.
- [x] Persist execution evidence, reset submission switch, and clean temporary files.

Preflight: all eight direct-inference tests passed, including the actual SDK
pipeline job schema, input proxy updates, and serialized Spark `direct` output.
The six existing training and legacy artifact checks also passed. Registered model
loading and output parity remain gated on the live managed Spark run.

First direct run `titanic-spark-inference-304bf0ba98e6` reached managed serverless
Spark, then failed reading the registered model through `stpublicncus04`'s DFS
endpoint (409: BlobStorageEvents/SoftDelete unsupported). The workspace is healthy
(`Succeeded`, North Central US). Preserve storage protections and copy the exact
registered artifact with the identity-authenticated Blob SDK into existing Spark
ADLS. Use content-addressed, checksum-verified files and a provenance manifest;
do not read the mutable training folder or modify infrastructure.

Model-copy preflight: 18 focused tests pass. Tests confirm identity-based Blob
reads without retrieving datastore secrets, content-addressed copies, no overwrite
on reuse, checksum mismatch rejection, unsafe-path rejection, saved Spark metadata,
and original registered URI/content checksum validation in the runtime manifest.

### Verified direct inference result

- Pipeline: `titanic-spark-inference-07036a90579b`, `Completed`.
- Child: `48fc24eb-61e1-4f0f-9026-c4d083d985ff`, `Completed`,
  `compute=Serverless`, `_azureml.ComputeTargetType=amlspark`.
- Actual Spark: `3.5.5.5.4.20260824.232707473`; master: `yarn`;
  application: `application_1791317656690_0001`.
- Registered model: `workshop-titanic-spark-model:1`; original artifact URI and
  model asset ID exactly match the runtime manifest.
- Verified copy SHA-256:
  `095a67b25284b45b93f3205d5c517dc4f5818a76cc87348baf6355d054e0e877`.
- Input/output: 891 rows, exact unique PassengerIds, binary classes, finite
  probabilities, and reference parity at tolerance `1e-9`.
- ADLS output:
  `abfss://spark@stpublicdlncus04.dfs.core.windows.net/pipelines/titanic-inference/titanic-spark-inference-07036a90579b/`.
- Local CSV:
  `workshop/outputs/titanic_spark_inference/titanic-spark-inference-07036a90579b/predictions.csv`.
- All four canonical notebook code cells executed; actual outputs are saved.
- Submission disabled; ignored configuration retains the successful job name for
  readback without duplicate submission. Abandoned batch switches remain disabled.
- Final focused suite: 19 passed; canonical notebook has four executed cells and
  no error outputs. Temporary runner and VS Code task removed; no runner remains.
- Registered model version 1 and existing endpoint default `sparkml-v1` unchanged.
  AML cluster stayed idle: current/target nodes `0/0`, allocation `Steady`.

## Previous Native Spark Batch Extension (superseded 2026-10-06)

This migration was abandoned at the user's request. Deployment `native-spark-v1`
and component versions 1 and 2 were created, but their first submitted pipeline
`pipelinejob-2b430a64-715f-4bde-bc27-bf8bb7a81837` failed in its native Spark child.
No default promotion occurred. The checks and contracts below are historical,
not pending work for the direct inference request.

**Goal:** Make batch endpoint `titanic-spark-batch-ncus04` invoke a managed
serverless Spark 3.5 inference job rather than a model batch worker with local
PySpark.

**Scope:**

- Reuse `mlwpublicncus04` in North Central US and registered model
  `workshop-titanic-spark-model:1`.
- Define the inference pipeline/component in checked-in YAML.
- Update the canonical batch notebook to deploy/invoke a pipeline-component batch
  deployment.
- Do not retrain or replace the registered model.
- Keep the existing `sparkml-v1` deployment until the new native Spark path has
  passed output validation.
- Verify the invoked child job is actually `type: spark`, uses runtime 3.5 and
  serverless ESv3 resources, and does not target the FSv2 AML cluster.
- Save real execution outputs in the existing notebook.

**Preparation and verification:**

- [x] Verify Spark pipeline-component support and identity/input/output contracts.
- [x] Implement YAML, native inference entry point, notebook changes, and tests.
- [x] Validate schemas, prediction contract, quota, and RBAC before deployment.
  Native model loading will be verified by the actual managed Spark invocation.
- [x] Complete Azure validation before deployment.
- [ ] Create a separate native Spark deployment and invoke it.
- [ ] Verify runtime, model provenance, output rows, and prediction parity.
- [ ] Promote the verified deployment to the endpoint default.
- [ ] Reset mutation switches and record proof.

### Native execution contract

| Setting | Value |
|---|---|
| Recipe | Existing Python SDK notebook + checked-in pipeline component YAML |
| Endpoint | `titanic-spark-batch-ncus04` (reuse) |
| New deployment | `native-spark-v1` |
| Pipeline component | `titanic_native_spark_inference:1` |
| Component YAML | `batch/titanic-spark-inference-pipeline.yaml` |
| Child job | `spark_score`, type `spark` |
| Managed runtime | Spark 3.5 |
| Serverless size | `standard_e4s_v3` |
| Spark topology | One driver and two executors |
| Model | Resolve immutable artifact URI from `workshop-titanic-spark-model:1` |
| Input | `abfss://spark@stpublicdlncus04.dfs.core.windows.net/data/titanic.csv` |
| Outputs | Unique ADLS directory per invocation: predictions CSV + runtime manifest |
| Identity | Invoking user's identity; verified Blob access to both Storage accounts |
| Promotion | Explicit switch; only after completed Spark run and output checks |
| Rollback | Existing `sparkml-v1` retained; no destructive operations |

### Native provisioning preflight

- North Central US Compute ESv3: limit 100, usage 0.
- Azure ML ESv3 limit: 1,000; total dedicated usage: 8 before this request.
- The three E4s v3 nodes require 12 VM vCPUs, within current capacity.
- Existing AML compute cluster is idle and is not the Spark job's compute target.
- Input and model pointers use explicit direct-mode bindings.
- Pipeline-component YAML loaded successfully with the installed SDK as a Spark 3.5
  serverless child with no AML compute assignment.
- The caller has Storage Blob Data Contributor on registered-model Storage and
  Storage Blob Data Owner on Spark ADLS.
- Managed Spark provides its runtime and JVM; no custom conda image build or
  `master("local[...]")` is required.

### Native validation evidence

- Focused tests: 17 passed, including Azure ML component loading and deployment
  serialization, native job-marker
  checks, Spark runtime/model manifest checks, strict prediction validation, and
  PassengerId-keyed parity.
- Python scorer/helpers and every notebook code cell parse successfully.
- The native pipeline YAML has exactly one `spark` child with runtime 3.5,
  `standard_e4s_v3`, direct URI IO, user identity, and no AML cluster assignment.
- Existing model version and legacy deployment are unchanged.
- First deployment succeeded; invocation was prevented by an SDK 1.28 readback
  class mismatch. The notebook now checks the REST-derived
  `deployment_configuration_type=PipelineComponent` property. No inference job was
  launched by the failed guard, and the legacy default remained unchanged.
- The next invocation was stopped locally because SDK 1.28 treated a raw
  `abfss://` input as an asset ID. Use a credentialless datastore reference to
  the existing Spark ADLS filesystem and its supported Azure ML input URI.
  No new storage, compute, or secrets are introduced.
- Batch API validation rejects output delivery mode `direct`; it accepts
  `upload` or `rw_mount`. Component version 2 explicitly keeps the Spark child's
  output in `direct` mode while the batch API uses `upload`. The previous component
  version remains immutable and no inference job had started before this rejection.

### Native validation checklist

- [x] Confirm subscription, workspace, region, endpoint, and model version.
- [x] Verify ESv3 quota and existing data-plane permissions.
- [x] Validate YAML and SDK pipeline-component deployment serialization.
- [x] Parse every new Python source and notebook code cell.
- [x] Pass focused native runtime/output and existing training tests.
- [x] Scan active native path for secrets and forbidden local Spark master settings.
- [x] Confirm existing endpoint default and deployment remain unchanged.
- [x] Complete the official Azure validation workflow.
- [ ] Deploy/invoke, verify native runtime and model loading, and promote after parity.

---

## Previous Batch Extension Request (2026-10-06)

**Goal:** Clarify the Titanic Spark training graph and add a managed Azure ML batch
deployment for registered model `workshop-titanic-spark-model:1`.

**Approved architecture pending user confirmation:**

- Rename pipeline job `evaluate_model` to `score_test_data`; keep
  `validate_model` as the only explicit registration gate.
- Add one SDK-only notebook that creates/reuses a batch endpoint and batch deployment,
  invokes the deployment with Titanic input data, streams the batch job, downloads
  predictions, and verifies the output.
- Use existing workspace `mlwpublicncus04`, compute cluster
  `aml-cluster-public-ncus04`, registered model version 1, UAMI-based Azure resources,
  and North Central US.
- Keep endpoint/deployment creation and invocation behind separate false-by-default
  switches in `.env.example`.

### Batch resource names and settings

| Resource / setting | Value |
|---|---|
| Batch endpoint | `titanic-spark-batch-ncus04` |
| Batch deployment | `sparkml-v1` |
| Environment | `workshop-titanic-spark-batch:2` |
| Registered model | `workshop-titanic-spark-model:1` |
| Compute | `aml-cluster-public-ncus04` |
| Batch instances | 1 |
| Max concurrency | 1 |
| Mini-batch size | 1 input file |
| Output action | Append rows to `predictions.csv` |
| Input | Local workshop `data/titanic.csv`, uploaded as URI folder |
| Scoring runtime | Python 3.10, OpenJDK 17, PySpark 3.5.8 |

### Scoring and verification contract

- `init()` discovers and loads the registered native Spark ML pipeline from
  `AZUREML_MODEL_DIR`.
- `run(mini_batch)` reads Titanic CSV files, reproduces the training feature schema,
  generates class/probability rows, and returns a pandas DataFrame.
- The notebook creates/reuses the endpoint, named environment, and deployment.
- The notebook sets the deployment as the endpoint default, invokes a batch job,
  streams it, downloads the `score` output, and verifies row count, PassengerId
  uniqueness, prediction domain, and probability bounds.
- The compute instance is not used. The existing cluster remains minimum zero and
  uses one `Standard_F8s_v2` node only while the batch job runs.

### Provisioning limits

| Resource | Current | Planned | Limit / capacity | Result |
|---|---:|---:|---:|---|
| Batch endpoints in workspace | 0 | 1 | No blocking quota exposed | PASS |
| Batch deployments | 0 | 1 | No blocking quota exposed | PASS |
| FSv2 vCPUs during invocation | 0 | 8 | 100 | PASS |
| Total regional vCPUs during invocation | 0 | 8 | 100 | PASS |
| Registered model versions | 1 | Reuse version 1 | Existing asset | PASS |

**Blocking extension steps:**

- [x] Confirm supported Azure ML batch deployment contract for a native Spark ML
  custom model.
- [x] Define scoring environment, scoring contract, endpoint/deployment names, and
  batch input/output behavior.
- [x] Add tests before implementation.
- [x] Implement notebook, scoring source, environment, configuration, and docs.
- [x] Validate locally and through Azure ML SDK schemas.
- [x] Obtain approval for Azure batch endpoint/deployment creation.
- [x] Invoke Azure validation and deployment workflows.
- [x] Verify endpoint, deployment, invocation job, predictions, and cost controls.

### Batch extension validation proof

| Check | Result |
|---|---|
| Focused tests | PASS: 8 |
| Spark graph | PASS: `prepare_data`, `train_model`, `score_test_data`, `validate_model` |
| Validation-node uniqueness | PASS: exactly one `validate_model` job |
| Scoring script syntax | PASS |
| Conda environment schema | PASS |
| Notebook Python syntax | PASS |
| Azure ML SDK entities | PASS: environment, endpoint, deployment |
| Registered model | PASS: `workshop-titanic-spark-model:1` |
| Existing compute | PASS: `aml-cluster-public-ncus04`, `Standard_F8s_v2` |
| Compute capacity | PASS: 8 planned vCPUs, 100 available |
| Existing endpoints | PASS: zero batch endpoints before deployment |
| Security | AAD endpoint auth, AzureCliCredential, managed compute identity, no secrets |

**Batch compute role verification:** `public-mi-compute` has AzureML Data Scientist
and workspace Contributor, Storage Blob/File/Queue/Table data roles, Key Vault
Secrets User, ACR Pull/Push, resource-group Reader, and Managed Identity Operator.
The batch extension introduces no new identity or role assignment.

### Batch extension validation checklist

- [x] Deployment plan loaded and Azure context confirmed.
- [x] Focused tests pass.
- [x] Python, notebook, YAML, and conda syntax checks pass.
- [x] Azure ML SDK endpoint/deployment/environment entities construct successfully.
- [x] Registered model version 1 exists and is validated.
- [x] Existing compute is healthy and has sufficient quota.
- [x] Endpoint/deployment names do not conflict with existing resources.
- [x] Endpoint uses AAD authentication.
- [x] Endpoint, deployment, and environment include `SecurityControl=Ignore`.
- [x] No passwords, keys, connection strings, or client secrets are embedded.
- [x] Compute UAMI live roles include workspace, Storage, Key Vault, and ACR access.
- [x] Azure batch deployment and invocation complete successfully.
- [x] Predictions contract passes and cluster returns to zero nodes.

---

## 1. Project Overview

**Goal:** Deploy a new open/public Azure Machine Learning single-workspace stack in
North Central US.

**Path:** Modify and reuse the existing `infra/single-workspace` Terraform root.

The new deployment is intentionally isolated from the retained Canada Central
resources and state. It will use purpose `public`, region code `ncus`, suffix `04`,
and a new local state lineage.

---

## 2. Requirements

| Attribute | Value |
|---|---|
| Classification | POC / development |
| Scale | Small |
| Budget | Cost-optimized: cluster minimum 0, maximum 4 |
| Subscription | `{subscription-name}` (`{subscription-id}`) |
| Location | North Central US (`northcentralus`) |
| Network profile | Public/open; AML managed-network isolation disabled |
| Encryption | Azure ML workspace and default Storage use CMK |
| Registry | No Azure ML registry |
| Required tag | `SecurityControl=Ignore` |
| State | Local Terraform workspace `public-ncus` at `infra/single-workspace/terraform.tfstate.d/public-ncus/terraform.tfstate` |
| Terraform data | Isolated `infra/single-workspace/.terraform-public-ncus` |
| Variables | Local `public.ncus.tfvars`; tracked example `public.ncus.tfvars.example` |
| Plan | `infra/single-workspace/public-ncus.tfplan` |

### Non-destructive boundary

- Do not modify or destroy resources in `rg-aml-ws-public-cc-03`.
- Do not use `terraform.public.tfstate`, `terraform.tfstate`, or the default Terraform
  workspace.
- The deployment plan must contain zero delete or replacement actions.
- Create a new North Central US resource group and globally unique linked resources.

---

## 3. Components Detected

| Component | Type | Technology | Path |
|---|---|---|---|
| Single-workspace root | Infrastructure | Terraform / AzureRM / AzAPI | `infra/single-workspace` |
| Azure ML module | Infrastructure | Terraform / AzAPI | `infra/single-workspace/modules/aml-managed-umi` |
| Default Storage module | Infrastructure | Terraform / AzureRM | `infra/single-workspace/modules/storage-account` |
| Container Registry module | Infrastructure | Terraform / AzureRM | `infra/single-workspace/modules/container-registry` |
| Workspace Key Vault module | Infrastructure | Terraform / AzureRM | `infra/single-workspace/modules/key-vault` |
| Spark data lake | Infrastructure | Terraform / ADLS Gen2 | `infra/single-workspace/spark-data-lake.tf` |
| Plan validator | Validation | PowerShell | `infra/single-workspace/scripts/validate-plan.ps1` |
| Deployment validator | Validation | PowerShell | `infra/single-workspace/scripts/validate-deployment.ps1` |

---

## 4. Recipe Selection

**Selected:** Terraform.

**Rationale:** The repository already contains the required public workspace
architecture, CMK, UAMIs, RBAC, compute, monitoring, and ADLS Gen2 resources. Reusing
the root avoids introducing a second infrastructure implementation.

### Required preparation changes

1. Allow the existing root to accept the validated
   `northcentralus` / `ncus` region pair and a two-digit suffix while retaining the
   existing Canada Central values.
2. Use an isolated Terraform data directory and local Terraform workspace, add
   `public.ncus.tfvars.example`, and create an ignored local
   `public.ncus.tfvars`.
3. Parameterize the plan validator for the expected public profile, location, region
   code, suffix, names, public access, compute creation, and isolated state.
4. Parameterize or extend deployment validation for the new public stack.
5. Update the single-workspace README with state-isolation and North Central US
   commands.

---

## 5. Architecture

### Planned resource names

| Resource | Name |
|---|---|
| Resource group | `rg-aml-ws-public-ncus-04` |
| Azure ML workspace | `mlwpublicncus04` |
| Default Storage | `stpublicncus04` |
| Spark ADLS Gen2 | `stpublicdlncus04` |
| Container Registry | `acrpublicncus04` |
| Workspace Key Vault | `kvpublicncus04` |
| CMK Key Vault | `kvcmkpublicncus04` |
| Log Analytics | `log-aml-public-ncus04` |
| Application Insights | `mlwinpublicncus04` |
| Workspace UAMI | `public-mi-workspace` |
| Cluster UAMI | `public-mi-compute` |
| Compute-instance UAMI | `public-mi-compute-instance` |
| Endpoint UAMI | `public-mi-online-endpoint` |
| Compute cluster | `aml-cluster-public-ncus04` |
| Compute instance | `ci-public-ncus04` |

All globally scoped names above were checked and are available.

### Service mapping

| Component | Azure service / SKU |
|---|---|
| ML control plane | Azure Machine Learning workspace |
| Cluster | AML Compute, `Standard_F8s_v2`, min 0, max 4 |
| Interactive compute | Compute Instance, `Standard_F8s_v2` |
| Workspace artifacts | StorageV2 Standard LRS |
| Spark data | StorageV2 Standard LRS, HNS enabled |
| Images | Azure Container Registry Premium |
| Secrets | Key Vault Premium |
| CMK | Separate purge-protected Key Vault and RSA key |
| Monitoring | Log Analytics PerGB2018 + Application Insights |
| Identity | Four user-assigned managed identities |

### Network and security

- Workspace `publicNetworkAccess=Enabled`.
- AML managed-network `isolationMode=Disabled`.
- Default Storage, Spark ADLS, ACR, and Key Vault public endpoints enabled.
- Blob public access and shared-key Storage authentication remain disabled.
- Compute nodes use public IPs because this open profile has no workspace private
  endpoint; remote login and SSH remain disabled.
- Workspace and default Storage use customer-managed encryption.
- Terraform caller and managed identities receive scoped RBAC.
- Every taggable managed resource includes `SecurityControl=Ignore`.

---

## 6. Provisioning Limit Checklist

### Resource inventory and verified capacity

| Resource type | Number to deploy | Total after deployment | Limit / quota | Validation source |
|---|---:|---:|---:|---|
| Resource groups | 1 | 20 | 980/subscription | ARG current count + Azure ARM limit |
| AML workspaces | 1 | 1 in region | No blocking workspace-count quota reported | Azure quota CLI/provider registration |
| AML compute clusters | 1 | 1 | 200 | `azure-quotas` `TotalClusters` |
| AML dedicated cores | Max 40 | 40 | 1,000 | `azure-quotas` `TotalDedicatedCores` |
| AML FSv2-family cores | Max 40 | 40 | 100 | `azure-quotas` `standardFSv2Family` |
| Compute regional vCPUs | Max 40 | 40 | 100 | `az vm list-usage` |
| Compute FSv2-family vCPUs | Max 40 | 40 | 100 | `az vm list-usage` |
| Storage accounts | 2 | 2 | 250 | `azure-quotas` `StorageAccounts` |
| Container registries | 1 | 2 | 100/region | ARG current count + Microsoft ACR limit |
| Key Vaults | 2 | 2 | No separate vault-count quota | ARG current count + Microsoft Key Vault limits |
| User-assigned identities | 4 | 4 | 1,000/region | ARG current count + Microsoft managed-identity limit |
| Role assignments | 45 | 282 | 5,000/subscription | ARG current count + Microsoft RBAC limit |

`Standard_F8s_v2` is available in North Central US with no subscription restriction.
The stack uses at most 40% of the Compute and AML FSv2-family limits.

**Status:** All planned resources are within limits.

---

## 7. Validation Proof

| Check | Command / source | Result |
|---|---|---|
| Terraform installed | `terraform -version` | PASS: Terraform 1.10.5 |
| Azure CLI installed and authenticated | `az account show` | PASS: confirmed subscription |
| Required providers registered | `az provider show` | PASS: AML, Storage, Key Vault, ACR |
| Terraform initialization | `terraform init -input=false` | PASS |
| Terraform formatting | `terraform fmt -check -recursive` | PASS |
| Terraform syntax | `terraform validate` | PASS |
| PowerShell validators | PowerShell parser API | PASS |
| Isolated pre-apply state | `Test-Path terraform.tfstate.d/public-ncus/terraform.tfstate` | PASS: absent |
| Saved plan | `terraform plan ... -out=public-ncus.tfplan` | PASS: 91 add, 0 change, 0 destroy; SHA-256 `4BFBD02800C80260C996863A062AD50E50680B69D8683ED52BDF83A1C18C4F57` |
| Plan invariants | `scripts/validate-plan.ps1` with public/NCUS parameters | PASS: all invariants |
| Template-variable scan | `{{ .Env.* }}` scan | PASS: no unresolved values |
| tfvars JSON gate | `main.tfvars.json` check | PASS: file not present |
| Compute quota | Azure quota CLI and `az vm list-usage` | PASS: 100 FSv2 and regional vCPUs; max 40 planned |
| Azure ML quota | Azure quota CLI | PASS: 100 FSv2, 1,000 dedicated cores, 200 clusters |
| Storage quota | Azure quota CLI | PASS: 250 available; 2 planned |
| Global names | Storage, ACR, Key Vault name checks | PASS: all available |
| SKU availability | `az vm list-skus` | PASS: `Standard_F8s_v2` unrestricted |
| Static RBAC review | Terraform and saved-plan review | PASS |
| Azure Policy | Azure MCP Policy + policy-definition review | PASS: no planned type, location, or SKU conflicts |
| Apply recovery | Replan after transient ARM connection reset | PASS: 34 creates, one approved ADLS firewall convergence update, zero deletes; SHA-256 `0D3055BFE6CB6D8522AC034E3A7F4ED00741FDABC3310C87C4550BDF60212A61` |
| Compute-name recovery | Replan after Azure ML name-length validation | PASS: 13 creates, one approved ADLS firewall convergence update, zero deletes; `ci-public-ncus04`; SHA-256 `51EFCA578432AE59B47F44C7E9B5092AD76ED97232135689B84DD8CB7DF6E30A` |
| Batch extension tests | `pytest tests/test_titanic_spark_training_pipeline.py tests/test_titanic_batch_endpoint.py` | PASS: 8 |
| Batch SDK schemas | Python AST, YAML/conda parsing, Azure ML SDK entity construction | PASS |
| Batch prerequisites | Model, compute, quota, endpoint conflict, secret scan | PASS |
| Batch compute RBAC | Live role assignment review for `public-mi-compute` | PASS |
| Native Spark tests (2026-10-06) | `pytest test_native_titanic_spark_batch.py test_titanic_batch_endpoint.py test_titanic_spark_training_pipeline.py` | PASS: 17, including batch datastore URI resolution and named input/output serialization |
| Native endpoint contract | SDK component load and pipeline-component REST serialization | PASS: `PipelineComponent`, Spark child runtime 3.5, no AML compute |
| Native runtime preflight | ESv3 quota CLI, immutable model URI, direct-mode inputs/outputs, Synapse registration, user Blob roles | PASS |
| Native policy preflight | Subscription assignments and inherited governance SKU-deny initiative | PASS: no E4s v3 denial |
| Notebook execution kernel | `mlops-azureml` kernelspec | PASS: exact repository `.venv` interpreter |
| Batch environment recovery | Environment v1 failed before scoring because NumPy 1.26 conflicted with `azureml-dataset-runtime`; v2 pins NumPy 1.23.5 | Corrected |

The official `validate-terraform.ps1` wrapper passed tool discovery,
subscription selection, Azure authentication, and template scanning. Its Terraform
subcommands returned Terraform help because the wrapper parameter named `$Args`
collides with PowerShell's automatic `$Args` variable. The same required commands
were run directly against the isolated state and saved plan and all passed.

The first apply lost its ARM connection while creating the workspace UAMI Reader
assignment. Azure did not create that assignment, while Terraform persisted every
resource that completed. The recovery plan contains only the remaining creates plus
an in-place ADLS firewall representation convergence from Azure's implicit open
default to Terraform's explicit `Allow`/`AzureServices` configuration.

The next recovery apply created the workspace and remaining RBAC but Azure rejected
the default compute-instance name because it exceeded the service's 24-character
limit. The invalid compute instance was not created. The approved replacement name is
`ci-public-ncus04`.

After deployment, the convergence check found only a representation loop on the
public Spark ADLS firewall: Azure omits an explicit firewall block for open access.
The Terraform root now emits `network_rules` only for the managed profile, preserving
the same public behavior without perpetual drift.

---

## 8. Execution Checklist

### Phase 1: Planning

- [x] Analyze workspace and retained Azure resources.
- [x] Gather deployment requirements.
- [x] Scan Terraform modules and validators.
- [x] Select the existing Terraform recipe.
- [x] Define isolated North Central US architecture and names.
- [x] Validate quotas and SKU availability.
- [x] Confirm subscription and location from the explicit deployment request.
- [x] User approves this plan.

### Phase 2: Preparation

- [x] Generalize region/suffix validation without changing existing defaults.
- [x] Add isolated Terraform data directory/workspace handling, North Central public
  tfvars example, and ignored local tfvars.
- [x] Parameterize plan and deployment validators.
- [x] Update directly related infrastructure documentation.
- [x] Run `terraform fmt -recursive`.
- [x] Run `terraform init -input=false`.
- [x] Run `terraform validate`.
- [x] Initialize/select the isolated `public-ncus` Terraform workspace and regenerate
  the saved plan after correcting legacy `-state` handling.
- [x] Prove plan is create-only, public, CMK-enabled, one workspace, no registry.
- [x] Set plan status to `Ready for Validation`.

### Phase 3: Validation and deployment

- [x] All validation checks pass
  - [x] Terraform is installed.
  - [x] Azure CLI is installed.
  - [x] Azure CLI is authenticated to the confirmed subscription.
  - [x] Terraform initialization succeeds.
  - [x] Terraform formatting check succeeds.
  - [x] Terraform configuration validation succeeds.
  - [x] Terraform saved plan succeeds.
  - [x] Terraform state check confirms the new state lineage is empty before apply.
  - [x] No unresolved Go-style environment templates exist.
  - [x] No invalid `main.tfvars.json` file exists.
  - [x] Azure Policy preflight permits the planned resources and required tags.
  - [x] Terraform plan invariants pass with 91 creates, zero changes, and zero destroys.
  - [x] Required deployment roles are present.
- [x] Invoke `azure-validate`.
- [x] Invoke `azure-deploy`.
- [x] Apply the saved plan in a visible VS Code terminal.
- [x] Verify exact names, North Central US locations, tags, UAMIs, CMK, linked
  resources, public networking, compute security, and ADLS Gen2.
- [x] Confirm cluster min nodes is zero and stop the compute instance after smoke
  validation to control cost.
- [x] Set plan status to `Deployed`.

---

## 9. Rollback

If deployment validation fails, do not touch retained Canada Central resources.
Destroy only the new North Central state lineage:

```powershell
terraform -chdir=infra\single-workspace destroy `
  -var-file=public.ncus.tfvars
```

Destruction requires separate explicit approval.

---

## 10. Role Assignment Verification

- **Status:** Verified.
- **Workspace UAMI:** Resource-group Reader, Azure AI Administrator, Azure AI
  Enterprise Network Connection Approver; Key Vault management/secrets roles;
  default-Storage Contributor plus Blob, File, Queue, and Table data roles; CMK
  Crypto User; Spark ADLS Contributor and Blob Data Contributor.
- **Cluster UAMI:** Workspace AzureML Data Scientist/Contributor; resource-group
  Reader; default-Storage Blob, File, Queue, and Table data roles; Key Vault Secrets
  User; ACR Pull and Push.
- **Compute-instance UAMI:** Workspace AzureML Data Scientist; default-Storage Blob
  and File data roles; Key Vault Secrets User; ACR Pull.
- **Online-endpoint UAMI:** ACR Pull, Storage Blob Data Reader, AzureML Metrics
  Writer; Managed Identity Operator is scoped to the compute identities for approved
  deployer principals.
- **Terraform caller:** Resource-group Reader; workspace AzureML Data Scientist,
  Azure AI Developer, and Compute Operator; Key Vault Administrator; default-Storage
  Blob, File, Queue, and Table data roles; Spark ADLS Blob Data Owner.
- **Scope review:** Data roles are scoped to their Storage, Key Vault, ACR, workspace,
  or identity resources. Resource-group roles are management-plane roles needed for
  Azure ML resource discovery and network approval.
- **Issues:** None found. Generic Reader/Contributor roles are not relied upon for
  Storage data access; explicit data-plane roles are present.

---

## 11. Deployment Results

- **Status:** Deployed and verified.
- **Terraform workspace:** `public-ncus`.
- **Terraform state:** `terraform.tfstate.d/public-ncus/terraform.tfstate`.
- **State resources:** 97.
- **Convergence:** `terraform plan -detailed-exitcode` returned no changes.
- **Azure resources:** 12 top-level resources, all in North Central US.
- **Azure ML workspace:** `mlwpublicncus04`.
- **Networking:** Public access enabled; AML managed-network isolation disabled.
- **Compute cluster:** `aml-cluster-public-ncus04`, `Standard_F8s_v2`, minimum zero,
  zero allocated nodes after validation.
- **Compute instance:** `ci-public-ncus04`, `Standard_F8s_v2`, stopped after
  validation.
- **Smoke job:** `affable_hamster_bsfgjj9527`, status `Completed`.
- **Serverless Spark job:** `icy_monkey_yv1fnc1hwf`, status `Completed`,
  `standard_e4s_v3`, Spark runtime 3.4.
- **Upgraded serverless Spark job:** `bright_market_x0hn88s7ls`, status
  `Completed`, `standard_e4s_v3`, Spark runtime 3.5, with no runtime-version
  deprecation warning.
- **Spark output:** 889 rows, 12 expected Titanic columns, no missing `Age`
  values, written to
  `abfss://spark@stpublicdlncus04.dfs.core.windows.net/output/titanic/`.
- **Titanic training pipeline:** `musing_date_ws9pfpkm52`, status `Completed`.
- **Pipeline stages:** `prepare_data`, `train_model`, `evaluate_model`, and
  `validate_model`, all Spark 3.5 and all `Completed`.
- **Model validation:** accuracy `0.8482758621`, F1 `0.8456727519`, area under ROC
  `0.9112131649`, threshold `0.70`, `validated=true`.
- **Registered model:** `workshop-titanic-spark-model:1`, custom Spark ML model.
- **Batch endpoint:** `titanic-spark-batch-ncus04`, AAD auth, provisioning succeeded.
- **Batch deployment:** `sparkml-v1`, environment
  `workshop-titanic-spark-batch:2`, model version 1, existing FSv2 cluster.
- **Batch scoring job:** `batchjob-a1db9a6c-865f-4091-b233-7ea6f0b5877b`,
  status `Completed`.
- **Batch predictions:** 891 rows; unique PassengerIds; binary prediction classes;
  probabilities in `[0, 1]`.
- **Batch compute cost control:** cluster returned to zero allocated nodes.
- **CMK:** Workspace encryption enabled; CMK Key Vault purge protection enabled.
- **Storage:** Shared-key access disabled on default Storage and Spark ADLS; Spark
  account has hierarchical namespace enabled.

### Live role verification

| Identity | Expected roles checked | Live assignments | Result |
|---|---:|---:|---|
| Workspace UAMI | 12 | 14 | PASS |
| Cluster UAMI | 10 | 11 | PASS |
| Compute-instance UAMI | 5 | 6 | PASS |
| Online-endpoint UAMI | 3 | 3 | PASS |
| Terraform caller | 9 | 67 including inherited | PASS |

### Links

- Azure ML Studio:
  `https://ml.azure.com/?wsid=/subscriptions/{subscription-id}/resourcegroups/rg-aml-ws-public-ncus-04/workspaces/mlwpublicncus04&tid={tenant-id}`
- Smoke job:
  `https://ml.azure.com/runs/affable_hamster_bsfgjj9527?wsid=/subscriptions/{subscription-id}/resourcegroups/rg-aml-ws-public-ncus-04/workspaces/mlwpublicncus04&tid={tenant-id}`
- Spark 3.5 job:
  `https://ml.azure.com/runs/bright_market_x0hn88s7ls?wsid=/subscriptions/{subscription-id}/resourcegroups/rg-aml-ws-public-ncus-04/workspaces/mlwpublicncus04&tid={tenant-id}`
- Titanic Spark training pipeline:
  `https://ml.azure.com/runs/musing_date_ws9pfpkm52?wsid=/subscriptions/{subscription-id}/resourcegroups/rg-aml-ws-public-ncus-04/workspaces/mlwpublicncus04&tid={tenant-id}`
- Titanic batch scoring job:
  `https://ml.azure.com/runs/batchjob-a1db9a6c-865f-4091-b233-7ea6f0b5877b?wsid=/subscriptions/{subscription-id}/resourcegroups/rg-aml-ws-public-ncus-04/workspaces/mlwpublicncus04&tid={tenant-id}`
- Titanic batch scoring URI:
  `https://titanic-spark-batch-ncus04.northcentralus.inference.ml.azure.com/jobs`
- Azure portal resource group:
  `https://portal.azure.com/#@{tenant-id}/resource/subscriptions/{subscription-id}/resourceGroups/rg-aml-ws-public-ncus-04/overview`
