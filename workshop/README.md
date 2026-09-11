# Azure Machine Learning and H2O Workshop

This folder is a portable two-day workshop for one customer operator and team using their own Azure Machine Learning workspace and compute instance. It covers Azure ML assets, jobs, pipelines, managed online endpoints, H2O binary-model onboarding, and a CMK-compatible offline-scoring pipeline suitable for Airflow orchestration.

> The H2O exercises use version-specific H2O binary models created with `h2o.save_model()` and loaded with `h2o.load_model()`. They are not portable MOJO zip artifacts.

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

1. `notebooks/04_h2o_customer/01_package_and_validate_model.ipynb`
2. `notebooks/04_h2o_customer/02_register_model.ipynb`
3. `notebooks/04_h2o_customer/03_create_environment.ipynb`
4. `notebooks/04_h2o_customer/04_deploy_online_endpoint.ipynb`
5. `notebooks/04_h2o_customer/05_submit_scoring_pipeline.ipynb`

### Cleanup

1. `notebooks/99_cleanup/cleanup_workshop_assets.ipynb`

## Pipelines

- `pipelines/single-step-merge-job.yaml`: one command job that merges green and yellow taxi files.
- `pipelines/integration-compare-pipeline.yaml`: merge, transform, train, predict, and compare.
- `pipelines/h2o-customer-scoring-pipeline.yaml`: CMK-compatible command pipeline for offline H2O scoring.

Airflow should submit the static H2O pipeline and remain the only production scheduler. See [AIRFLOW.md](docs/AIRFLOW.md).

## Safety and Cleanup

- Workshop notebooks never delete infrastructure.
- Endpoint traffic promotion requires an explicit switch.
- Cleanup requires `CLEANUP_WORKSHOP_ASSETS=true`, deletes only the configured endpoints, and archives only the configured asset versions.
- Customer model files and generated outputs are ignored by Git.

## Sources

Workshop code is adapted from this repository, [AzureML-deep-dive-L200](https://github.com/jomedinagomez/AzureML-deep-dive-L200), and [Azure/azureml-examples](https://github.com/Azure/azureml-examples). See [SOURCES.md](SOURCES.md) for exact paths, revisions, adaptations, and retained MIT notices.

## Folder Map

```text
workshop/
  docs/                 Prework, Airflow, and next steps
  licenses/              Retained source licenses
  notebooks/             Ordered hands-on exercises
  pipelines/             Static Azure ML job definitions
  src/                   Job components and scoring code
  environment/           Version-pinned runtimes
  data/                  Safe samples and customer intake contract
  outputs/               Ignored generated artifacts
  .env.example           Single configuration template
  requirements.txt       Compute-instance notebook dependencies
```