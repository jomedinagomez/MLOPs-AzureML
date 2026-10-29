# Azure Machine Learning and H2O Workshop

This folder is a portable two-day workshop for one customer operator and team using their own Azure Machine Learning workspace and compute instance. It covers Azure ML assets, jobs, pipelines, managed online endpoints, H2O model onboarding, a CMK-compatible offline-scoring pipeline suitable for Airflow orchestration, an optional managed-identity serverless Spark exercise, and a managed feature store demo run from local Windows.

> The reference exercise uses a native H2O binary model. The customer BYOM exercise accepts either a native H2O binary or a portable H2O-3 MOJO ZIP.

## Start Here

1. Complete [PREWORK.md](docs/PREWORK.md).
2. Review the [two-day agenda](AGENDA.md).
3. Clone the repository on the Azure ML compute instance.
4. Create the workshop environment and kernel.
5. Copy `.env.example` to `.env` and enter the target workspace values.
6. Run the notebooks in the order below.

## Compute-Instance Setup

From the repository root:

```bash
cd workshop
uv venv .venv --python 3.12
source .venv/bin/activate
uv pip install -r requirements.txt
python -m ipykernel install --user --name azureml-workshop --display-name "Azure ML Workshop"
cp .env.example .env
az login --tenant <TENANT_ID>
az account set --subscription <SUBSCRIPTION_ID>
```

Confirm OpenJDK 17 before running H2O notebooks:

```bash
java -version
```

## One Configuration File

Every notebook reads `workshop/.env` with `python-dotenv`. The file contains identifiers and behavior switches only. Never store passwords, access keys, client secrets, or tokens in it.

All mutation switches default to `false`. Enable only the operation currently being demonstrated, then return it to `false` when appropriate.

## Notebook-Generated Runtime Files

Foundation and H2O notebooks generate their own command scripts, scoring functions, Conda files, H2O component/pipeline YAML, and request fixtures under:

```text
outputs/generated/<workflow>/
```

The notebook displays and validates these files before it submits anything to Azure. Generated runtime files are ignored by Git and can be deleted and recreated by rerunning the owning notebook. Checked-in files under `data/` are immutable teaching inputs, not executable deployment definitions.

The two notebooks in `notebooks/02_jobs_and_pipelines/` intentionally remain YAML-first. They submit the checked-in job, component, pipeline, code, and environment files as originally designed.

## Notebook Order

### Setup and Foundations

1. `notebooks/00_setup/00_validate_workshop.ipynb`
2. `notebooks/01_foundations/01_workspace_and_compute.ipynb`
3. `notebooks/01_foundations/02_register_data_asset.ipynb`
4. `notebooks/01_foundations/03_register_environment.ipynb`
5. `notebooks/01_foundations/04_register_model.ipynb`
6. `notebooks/01_foundations/05_submit_command_job.ipynb`
7. `notebooks/01_foundations/06_deploy_online_endpoint.ipynb`
8. [08_register_assets_to_registry.ipynb](notebooks/01_foundations/08_register_assets_to_registry.ipynb) (optional external registry)

The registry notebook adapts the repository's asset-sharing example to existing
workshop models, environments, and data assets. Set `AZUREML_REGISTRY_NAME` in
`.env`, preview the exact source/destination versions, and opt in with
`SHARE_FOUNDATION_ASSETS=true`. It uses managed identity on compute when available
and Azure CLI credentials for privately connected development. Run it from a
machine that can reach the private registry and its backing Storage/ACR.
The [AzureMLManagedVnet stack](../infra/AzureMLManagedVnet/README.md) deploys
private workspace/registry access, but deliberately does not enable the
source-storage public-access exception required for native asset sharing.
Keep `SHARE_FOUNDATION_ASSETS=false` with that stack until a supported sharing
path is approved and verified. Private endpoints alone do not enable this
service-side sharing operation.

### Jobs and Pipelines

1. `notebooks/02_jobs_and_pipelines/01_submit_single_step_merge.ipynb`
2. `notebooks/02_jobs_and_pipelines/02_submit_integration_compare.ipynb`

The integration pipeline includes a sixth `register_job` after training and
comparison. Set `AZUREML_REGISTRY_NAME` before submission. The registration node
uses the cluster UAMI selected by `AZUREML_COMPUTE_IDENTITY_CLIENT_ID`, which needs
**AzureML Registry User** on the destination and network access to its private
registry and backing Storage/ACR. It uploads the MLflow artifact from the mounted
training output, rather than sharing a registered workspace asset, and writes
the verified model ID/version to the `register_metadata` pipeline output as
`registration.json`. Registration runs only with a newly submitted pipeline;
previously completed runs are unchanged. Each execution assigns a new model
version and is not reused from the pipeline cache.

### Reference H2O Flow

1. `notebooks/03_h2o_reference/01_create_reference_binary_model.ipynb`
2. `notebooks/03_h2o_reference/02_validate_reference_bundle.ipynb`
3. `notebooks/03_h2o_reference/03_test_local_endpoint.ipynb`
4. `notebooks/03_h2o_reference/04_deploy_reference_endpoint.ipynb`
5. `notebooks/03_h2o_reference/05_submit_reference_scoring_pipeline.ipynb`

### Customer H2O Flow

The checked-in [customer bundle demo](data/h2o/customer_bundle/README.md) uses an Apache-licensed prostate GBM MOJO published by H2O-3, so it is independent of the locally trained taxi reference model. For the real exercise, the customer may supply a native binary or MOJO ZIP plus its producer and target-runtime contract. Golden fixtures are optional. Put proprietary artifacts under the ignored `data/h2o/customer_bundle/private/<bundle-id>/` path and replace the complete `H2O_CUSTOMER_*` contract in `.env`.

1. `notebooks/04_h2o_customer/01_package_and_validate_model.ipynb`
2. `notebooks/04_h2o_customer/02_register_model.ipynb`
3. `notebooks/04_h2o_customer/03_create_environment.ipynb`
4. `notebooks/04_h2o_customer/04_deploy_online_endpoint.ipynb`
5. `notebooks/04_h2o_customer/05_submit_scoring_pipeline.ipynb`

### Custom Joblib Model

1. `notebooks/05_custom_model/01_deploy_joblib_model.ipynb`

This self-contained example loads `model/customer_model.joblib`, scores `input.csv` locally, and can deploy the same model and rows to a managed online endpoint. It does not use the workshop `.env` file.

### Serverless Spark Jobs and Pipelines

1. `notebooks/06_spark_jobs_pipelines/01_submit_serverless_spark_job.ipynb`
2. `notebooks/06_spark_jobs_pipelines/02_submit_titanic_training_pipeline.ipynb`
3. [03_run_titanic_spark_inference_pipeline.ipynb](notebooks/06_spark_jobs_pipelines/03_run_titanic_spark_inference_pipeline.ipynb)
4. [04_consume_registered_model_serverless_spark.ipynb](notebooks/06_spark_jobs_pipelines/04_consume_registered_model_serverless_spark.ipynb)

Complete the infrastructure and RBAC steps in
[`notebooks/06_spark_jobs_pipelines/README.md`](notebooks/06_spark_jobs_pipelines/README.md)
before enabling submission. The exercise uses Azure ML serverless Spark, not the
workspace AML compute cluster. The second notebook runs prepare, train, score, and
validate Spark 3.5 jobs from a checked-in pipeline YAML and registers the model only
after validation passes. The third notebook submits the YAML-defined serverless
Spark 3.5 inference pipeline directly, loads the registered model, and saves and
validates ADLS predictions. No batch endpoint or deployment is needed.
The fourth notebook consumes the same registered model through a standalone
serverless Spark job, displays predictions, and verifies runtime/provenance without
a pipeline wrapper or local Spark session.

### Managed Feature Store from Local Windows

Follow
[`notebooks/07_feature_store/README.md`](notebooks/07_feature_store/README.md)
and the slide-ready talk track in
[`FEATURE_STORE_TALK_TRACK.md`](notebooks/07_feature_store/FEATURE_STORE_TALK_TRACK.md).
The notebooks run the official Microsoft `featurestore_sample` code from a local Windows
checkout. They use local Spark for feature development, submit materialization and feature
retrieval to Azure ML serverless Spark, and cover offline and online materialization,
training, batch inference, and an online endpoint.

1. `notebooks/07_feature_store/00_prepare_sample_data.ipynb`
2. `notebooks/07_feature_store/01_develop_feature_set_and_register.ipynb`
3. `notebooks/07_feature_store/02_experiment_and_train_models.ipynb`
4. `notebooks/07_feature_store/03_recurrent_materialization_batch_inference.ipynb`
5. `notebooks/07_feature_store/04_online_store_and_online_inference.ipynb`

These notebooks create Azure resources, including a recurrent materialization schedule, Azure
Managed Redis, and a managed online endpoint. See the module README for costs and cleanup.

### Cleanup

1. `notebooks/99_cleanup/cleanup_workshop_assets.ipynb`

## Jobs and Pipelines

- `pipelines/single-step-merge-job.yaml` remains the source-controlled command-job definition.
- `pipelines/integration-compare-pipeline.yaml` and `src/components/*.yaml` define the six-stage integration flow, including external-registry registration.
- `notebooks/06_spark_jobs_pipelines/` contains the notebook-driven serverless Spark
  exercises, a checked-in multi-stage pipeline YAML, and PySpark entry points.
- `notebooks/07_feature_store/` contains the managed feature store demo based on the
  official `featurestore_sample` notebooks, its talk track, and the extracted Learn content.
- Each H2O online-deployment notebook generates its own scoring script and request.
- Each H2O offline-scoring notebook generates its own scorer, component YAML, environment binding, and pipeline YAML.

Airflow should consume an approved copy of the notebook-generated H2O pipeline and remain the only production scheduler. See [AIRFLOW.md](docs/AIRFLOW.md).

## Safety and Cleanup

- Workshop notebooks never delete infrastructure.
- Endpoint traffic promotion requires an explicit switch.
- Cleanup requires `CLEANUP_WORKSHOP_ASSETS=true`, deletes only the configured endpoints, and archives only the configured asset versions.
- Private customer model files and generated outputs are ignored by Git; only the safe bundled demo is tracked.

## Sources

Workshop code is adapted from this repository, [AzureML-deep-dive-L200](https://github.com/jomedinagomez/AzureML-deep-dive-L200), and [Azure/azureml-examples](https://github.com/Azure/azureml-examples). The managed feature store module is anchored to the official `featurestore_sample` SDK-only track. The bundled customer MOJO comes from [H2O-3](https://github.com/h2oai/h2o-3) under Apache-2.0. See [SOURCES.md](SOURCES.md) for exact paths, revisions, adaptations, and retained notices.

## Folder Map

```text
workshop/
  docs/                 Prework, Airflow, and next steps
  licenses/              Retained source licenses
  notebooks/             Ordered hands-on exercises
  pipelines/             Checked-in YAML for notebooks/02_jobs_and_pipelines
  src/                   YAML-first job code/components and bundle validation
  environment/train/     Checked-in environment used only by the YAML-first pipeline
  scripts/               Notebook validation utilities
  data/                  Safe samples and customer intake contract
  outputs/generated/     Ignored notebook-generated runtime artifacts
  .env.example           Single configuration template
  requirements.txt       Compute-instance notebook dependencies
```