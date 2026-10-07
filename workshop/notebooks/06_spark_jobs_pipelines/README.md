# Azure ML Native Serverless Spark Workshop

Run these notebooks from the repository `.venv` using the signed-in Azure CLI
identity. They use the Python SDK for Azure operations and preserve their execution
outputs. Use one canonical notebook tab and reload configuration before starting a
new kernel; do not create alternate notebook paths.

## Notebook order

1. [01_submit_serverless_spark_job.ipynb](./01_submit_serverless_spark_job.ipynb)
   submits the Spark 3.5 Titanic wrangling job.
2. [02_submit_titanic_training_pipeline.ipynb](./02_submit_titanic_training_pipeline.ipynb)
   submits the training pipeline, verifies its validation report, and registers the
   native Spark ML model.
3. [03_run_titanic_spark_inference_pipeline.ipynb](./03_run_titanic_spark_inference_pipeline.ipynb)
   submits the inference pipeline directly, runs managed serverless Spark 3.5 with
   the registered model, and downloads and verifies predictions/runtime evidence.
   It does not create, invoke, update, or delete any endpoint.
4. [04_consume_registered_model_serverless_spark.ipynb](./04_consume_registered_model_serverless_spark.ipynb)
   consumes the registered model in a standalone native serverless Spark 3.5 job
   and displays validated predictions. There is no pipeline wrapper.

## Definitions and code

| Artifact | Purpose |
|---|---|
| [serverless-spark-managed-identity.yml](./serverless-spark-managed-identity.yml) | Standalone Spark 3.5 job; the current public profile uses user identity |
| [titanic-spark-training-pipeline.yml](./titanic-spark-training-pipeline.yml) | Prepare, train, score test data, and validate model |
| [src/pipeline/](./src/pipeline/) | Training pipeline entry points |
| [titanic-spark-inference-pipeline.yaml](./titanic-spark-inference-pipeline.yaml) | Direct serverless Spark inference pipeline job |
| [titanic-serverless-model-consumption.yaml](./titanic-serverless-model-consumption.yaml) | Standalone serverless Spark model-consumption job |
| [src/inference/spark_inference.py](./src/inference/spark_inference.py) | Distributed Spark inference entry point |
| [src/inference_verification.py](./src/inference_verification.py) | Runtime, prediction, and parity checks |
| [src/registered_model_artifacts.py](./src/registered_model_artifacts.py) | Identity-based, checksum-verified registered model copy for Spark ADLS |
| [data/titanic.csv](./data/titanic.csv) | Pinned workshop Titanic sample |

The historical [batch/score.py](./batch/score.py) and
[batch/conda.yml](./batch/conda.yml) belong to the previous model deployment
`sparkml-v1`. That deployment runs local PySpark inside an AML compute worker.
They are retained as historical artifacts, not used by the serverless inference
pipeline. Existing Azure batch deployments are left unchanged.

## Current infrastructure

The public stack is defined by
[infra/single-workspace](../../../infra/single-workspace/README.md):

- Workspace `mlwpublicncus04` in North Central US.
- Public connectivity enabled; AML managed-network isolation disabled.
- Workspace and default Storage CMK enabled.
- Spark ADLS Gen2 account `stpublicdlncus04`, filesystem `spark`.
- Storage shared-key and anonymous Blob access disabled.
- Native jobs use the built-in managed Spark runtime and serverless
  `standard_e4s_v3` resources.

The AML compute cluster `aml-cluster-public-ncus04` is not the native Spark target.
It can remain at zero nodes during Spark inference. No custom batch conda image
build or local JVM setup is required to submit the native job from the notebook.

For the optional managed-network profile, provision the managed network through
[configure-spark-network.ps1](../../../infra/single-workspace/scripts/configure-spark-network.ps1)
with Spark included, approve Storage connections, and require `Active` /
`sparkReady=true` before submission. Those checks do not apply to the current
public profile with isolation disabled.

## Training and registration gate

The training YAML has four distinct nodes:

1. `prepare_data`: clean/cast raw data and create train/test Parquet.
2. `train_model`: fit a native Spark ML Random Forest pipeline.
3. `score_test_data`: calculate held-out accuracy, F1, and AUC.
4. `validate_model`: enforce the registration threshold and emit
   `validated=true`.

Only `validate_model` is the registration gate. Registration is performed by
notebook 02 after the entire pipeline completes and the validation report passes.

## Serverless inference architecture

```text
Python SDK notebook
  -> YAML pipeline job submitted with MLClient.jobs.create_or_update
     -> spark_score (managed Spark 3.5, serverless E4s v3)
        -> immutable registered model artifact
        -> unique ADLS output per run
```

The notebook resolves the model artifact URI through
`ml_client.models.get(name, version)`. It does not load the training pipeline's
mutable output folder. The model asset ID is recorded in the runtime manifest.
The YAML leaves `model_input.path` unset; the notebook supplies the registered
model ID and a verified ADLS artifact copy before submitting it. Run through
notebook 03 rather than submitting the unparameterized YAML.

The registered model is in the workspace's non-HNS Blob account. Its DFS endpoint
is incompatible with that account's soft-delete settings, so native Spark cannot
read the original Azure ML URI directly. The notebook reads the exact registered
artifact through the identity-authenticated Blob SDK and stages a content-addressed
copy on existing Spark ADLS. Every copied file is SHA-256 checked, existing bytes
are never overwritten, and a provenance manifest records the registered asset ID,
original URI, and content checksum. No storage protection is disabled or model
version replaced.

Inputs are named `titanic_data`, `model_input`, and `model_asset_id`. URI bindings
explicitly use direct mode. Predictions are written as headered CSV parts under
`csv/`, and a runtime manifest is written under `runtime/`. The notebook creates a
consolidated local `predictions.csv` after downloading and validating those outputs.

All pipeline and Spark URI bindings use `direct` mode. No batch API, component
registration, custom environment, persistent compute, or new datastore is needed.

The verification checks:

- The executed child has `_azureml.ComputeTargetType=amlspark` and serverless compute.
- The manifest reports Spark 3.5 and a non-local Spark master.
- The selected registered model asset ID matches exactly.
- The original registered artifact URI and verified copy checksum are recorded.
- Output row count and PassengerIds match the input.
- Prediction classes are exactly 0 or 1; probabilities are finite and in `[0, 1]`.
- Optional reference comparison agrees by PassengerId, independent of row order.

The sample returns 891 rows. `Survived` is optional for native inference; no labels
are required to score new data.

## Configuration and safe reruns

Configure the ignored [workshop/.env](../../.env.example):

```dotenv
TITANIC_SPARK_MODEL_NAME=workshop-titanic-spark-model
TITANIC_SPARK_MODEL_VERSION=1
RUN_TITANIC_SPARK_INFERENCE_PIPELINE=false
TITANIC_SPARK_INFERENCE_OUTPUT_PATH=pipelines/titanic-inference
TITANIC_SPARK_INFERENCE_JOB_NAME=
TITANIC_SPARK_INFERENCE_REFERENCE_PREDICTIONS_PATH=
```

Set the run switch to `true` to submit inference, then reset it to `false`.
Predictions are saved under `workshop/outputs/titanic_spark_inference/<job-name>/`.
Use the repository interpreter; the notebook's `mlops-azureml` kernelspec points to
it in this checkout. If needed, register that kernel from the repository root:

```powershell
.\.venv\Scripts\python.exe -m ipykernel install --user --name mlops-azureml --display-name "Python (MLOPs-AzureML)"
```

Set `TITANIC_SPARK_INFERENCE_JOB_NAME` to a completed inference pipeline to re-check
its runtime and download output without submitting another job. A legacy AML
compute job fails the serverless Spark check. A nonempty reference path must point
to the previous whitespace-delimited predictions; missing files fail explicitly.
Azure ML can return a generic job object for a Spark child, so runtime verification
uses its `amlspark` marker, serverless compute, and the actual runtime manifest.

### Standalone model consumption (notebook 04)

This notebook runs the same registered-model loader and distributed `transform`
on native managed Spark, without wrapping it in a pipeline. The local Python
kernel coordinates the job and displays the results; it is not an interactive
remote Spark kernel and never creates a local Spark session.

```dotenv
RUN_TITANIC_SPARK_MODEL_CONSUMPTION=false
TITANIC_SPARK_MODEL_CONSUMPTION_OUTPUT_PATH=model-consumption/titanic
TITANIC_SPARK_MODEL_CONSUMPTION_JOB_NAME=
TITANIC_SPARK_MODEL_CONSUMPTION_REFERENCE_PREDICTIONS_PATH=
```

Turn on the run switch to submit and reset it afterwards. Set the job name to
reuse a successful standalone Spark run. The optional reference is the headered
`predictions.csv` downloaded by notebook 03. Local results are saved under
`workshop/outputs/titanic_model_consumption/<job-name>/`.

Standalone Spark accepts URI inputs, so the notebook binds the registered model
ID into the argument placeholder before submission. Both model URI and model ID
must be resolved through notebook 04; do not submit the unparameterized YAML.
SDK readback may expose `compute=None` for standalone serverless Spark. Verification
requires its native `amlspark` marker, Spark job type, serverless VM resource
configuration, and actual Spark/runtime/model evidence.

Notebook 04 was verified with standalone job `titanic-model-consumption-b239a7b8fb48`.
It completed on managed Spark 3.5 / YARN, produced 891 validated predictions, and
matched notebook 03's results. Prediction tables and runtime evidence are saved in
the notebook. Submission is disabled and the successful job can be reused.

## Identity, networking, and cost

- The invoking user needs Blob data access to both registered-model Storage and
  Spark ADLS.
- Storage authentication remains identity-based. Do not add account keys or SAS
  tokens to the notebook configuration.
- Confirm ESv3 quota and SKU eligibility in the workspace region before submitting.
- The sample uses one driver and two executors on E4s v3 serverless resources.
- Spark resources are ephemeral and billed while the job runs.
- In `AllowOnlyApprovedOutbound` environments, FQDN rules do not propagate into
  serverless Spark. Package custom dependencies behind approved Storage endpoints
  instead of relying on runtime internet installation.
- Reset mutation switches to `false` after execution. Keep the saved notebook
  outputs as execution evidence.

## Verified inference run

Pipeline `titanic-spark-inference-07036a90579b`
completed with one `Serverless` / `amlspark` child. Its actual runtime reports
Spark `3.5.5.5.4.20260824.232707473` and master `yarn`. Registered model version 1
produced 891 validated predictions with reference parity. Notebook 03 retains the
real outputs; submission is disabled after verification.

## Sources

- [Microsoft's pinned standalone Spark example](https://github.com/Azure/azureml-examples/tree/86d53a35d2ecc33ff40c669cc1389b06899e5a4b/cli/jobs/spark)
- [Spark component YAML schema](https://learn.microsoft.com/azure/machine-learning/reference-yaml-component-spark?view=azureml-api-2)
- [Submit Spark jobs](https://learn.microsoft.com/azure/machine-learning/how-to-submit-spark-jobs?view=azureml-api-2)
- [Pipeline job YAML schema](https://learn.microsoft.com/azure/machine-learning/reference-yaml-job-pipeline?view=azureml-api-2)
- [Standalone Spark job YAML schema](https://learn.microsoft.com/azure/machine-learning/reference-yaml-job-spark?view=azureml-api-2)
