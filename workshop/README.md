# Azure Machine Learning and H2O Workshop

This folder is a portable two-day workshop for one customer operator and team using their own Azure Machine Learning workspace and compute instance. It covers Azure ML assets, jobs, pipelines, managed online endpoints, H2O model onboarding, and a CMK-compatible offline-scoring pipeline suitable for Airflow orchestration.

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

### Jobs and Pipelines

1. `notebooks/02_jobs_and_pipelines/01_submit_single_step_merge.ipynb`
2. `notebooks/02_jobs_and_pipelines/02_submit_integration_compare.ipynb`

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

### Cleanup

1. `notebooks/99_cleanup/cleanup_workshop_assets.ipynb`

## Jobs and Pipelines

- `pipelines/single-step-merge-job.yaml` remains the source-controlled command-job definition.
- `pipelines/integration-compare-pipeline.yaml` and `src/components/*.yaml` remain the source-controlled five-stage integration definition.
- Each H2O online-deployment notebook generates its own scoring script and request.
- Each H2O offline-scoring notebook generates its own scorer, component YAML, environment binding, and pipeline YAML.

Airflow should consume an approved copy of the notebook-generated H2O pipeline and remain the only production scheduler. See [AIRFLOW.md](docs/AIRFLOW.md).

## Safety and Cleanup

- Workshop notebooks never delete infrastructure.
- Endpoint traffic promotion requires an explicit switch.
- Cleanup requires `CLEANUP_WORKSHOP_ASSETS=true`, deletes only the configured endpoints, and archives only the configured asset versions.
- Private customer model files and generated outputs are ignored by Git; only the safe bundled demo is tracked.

## Sources

Workshop code is adapted from this repository, [AzureML-deep-dive-L200](https://github.com/jomedinagomez/AzureML-deep-dive-L200), and [Azure/azureml-examples](https://github.com/Azure/azureml-examples). The bundled customer MOJO comes from [H2O-3](https://github.com/h2oai/h2o-3) under Apache-2.0. See [SOURCES.md](SOURCES.md) for exact paths, revisions, adaptations, and retained notices.

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