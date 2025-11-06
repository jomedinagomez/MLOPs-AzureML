# Integration Branch ML CI/CD Plan

## Goals
- Standardize end-to-end CI/CD for the Azure ML project with explicit integration branch validation.
- Ensure only model improvements (measured by the taxi fare comparison step) move forward to the dev registry and ultimately to production.
- Run unit tests and ML pipeline validation automatically for all changes that touch the `src/` folder.
- Maintain clear separation of environments: Dev workspace (experimentation), Dev external registry (model promotion), Prod workspace (serving).

## Branching Strategy
| Branch | Purpose | Notes |
|--------|---------|-------|
| `feature/*` | Individual feature work | Developers branch from latest `integration`. |
| `integration` | Shared validation branch | All merges land here after validation. Mirrors gatekeepers for prod promotion. |
| `main` | Production-ready | Only updated when prod deployment succeeds using validated artifacts. |

### Merge Policy
- Pull Requests (PRs) and direct commits destined for `integration` must pass the integration pipeline.
- Only `src/` changes trigger the ML pipeline stages; other changes run unit tests only.
- Successful integration runs automatically promote models to the Dev registry.

## Pipeline Overview

### Trigger Conditions
- **CI**: On PR to `integration` or direct commit into `integration` (protected to require checks).
- Scope includes file filters:
  - `src/**`, `pipelines/**`, `.github/workflows/**` → full ML validation and unit tests.
  - Other paths → unit tests only (optional).

### High-Level Stages
1. **Checkout & Setup**
   - Pull repo, install dependencies (pip/conda) pinned via `environment/train/conda.yaml` as needed.
2. **Static Checks / Unit Tests**
   - Execute Python unit tests located under `src/**` (e.g., `pytest src/tests`).
   - Fail fast on lint/test errors.
3. **Azure Login & Context**
  - Use the dedicated service principal (client secret stored in GitHub Secrets) to log into Azure.
  - CI runners use Python 3.13 for unit tests and CLI tooling; keep dependency pins compatible with that runtime.
   - Select Dev workspace (`mlwdevcc01`) and Dev external registry (`mlrdevcc01`).
4. **Run ML Pipeline (Partial)**
   - Execute pipeline defined in `pipelines/dev-e2e-pipeline.yaml` but **stop after `compare_job`** (CompareTaxiFare stage).
   - Use Dev workspace compute (`aml-cluster-dev-cc01`).
5. **Model Evaluation**
   - Confirm `compare_job` output indicates the new model outperforms the baseline.
   - Parse metrics artifact (e.g., JSON) and fail pipeline if performance does not improve.
6. **Model Promotion**
   - On success, register/promote model to Dev external registry (`mlrdevcc01`).
   - Tag artifact with `integration` metadata (commit SHA, comparison metrics).
7. **PR Status Update**
   - For PRs: post status (success/failure) and hold merge until success.
   - For direct commits: pipeline must pass before branch protection allows push completion (if forcing direct commit policy).

## Detailed Stage Design

### Setup
- Use pipeline templates to share logic across PR and CI runs.
- Cache dependency installs (pip cache) to improve repeat runs.

### Unit Testing Strategy
- Command: `pytest src --maxfail=1 --disable-warnings -q`.
- Coverage reporting optional but recommended for metrics.
- Fail pipeline when tests fail.

### ML Pipeline Execution
- Command (CLI v2):
  ```bash
  az ml job create \
    --file pipelines/dev-e2e-pipeline.yaml \
    --set settings.default_compute="azureml:aml-cluster-dev-cc01" \
    --set jobs.compare_job.outputs.compare_output=azureml://datastores/workspaceblobstore/paths/pipeline/${{Build.SourceVersion}}
  ```
- Use `--set` overrides only if needed to direct outputs per run.
- Use `az ml job show` to poll status, fail step if job ends in non-success state.

### Performance Gate (CompareTaxiFare)
- Inspect the `compare_job` generated report:
  - Example JSON metric: `metrics/comparison.json` containing `improved: true/false`.
  - Add script to evaluate result (e.g., `python tools/validate_compare.py <artifact_path>`).
  - Pipeline fails when improvements are not observed.

### Promotion Logic
- Upon successful comparison:
  - Use CLI or SDK to register latest model: `az ml model create --name taxi-class-dev --path <trained_model_output> --registry-name mlrdevcc01`.
  - Add tags: `branch=integration`, `commit=<SHA>`, `comparison_run=<job_id>`.
- Optionally update workspace model as well for dev testing.

- Retrieve the newly promoted model from the Dev registry and deploy to the Dev workspace endpoint in blue/green mode.
- When an existing deployment already serves traffic, provision a new slot, route 30% of traffic to it, and validate using automated tests (latency, accuracy, health probes).
- The pipeline now wraps the traffic update logic in conditional jobs: `traffic_job` promotes traffic only after tests succeed, while `rollback_job` executes on failure to restore 100% of the prior distribution and delete the failed slot when a previous deployment exists.
- Slot names default to `blue` in Dev and `green` in Prod; override the `deployment_name` input (or the workflow variables) when you need to flip traffic to the alternate slot.
- If validation fails and no prior deployment existed, keep the endpoint online but surface the failure to the workflow for manual follow-up.
- `src/deploy/deploy.py` now preserves the prior traffic distribution in metadata, while `src/traffic/update_traffic.py` promotes or rolls back allocations so Dev and Prod share the same traffic orchestration primitives.

### PR / Commit Handling
- Configure branch protections on `integration`:
  - Require successful pipeline run (status check). 
  - Disallow direct pushes unless necessary, or require pipeline check even for direct pushes (enforced via Git server).
- For PR flows:
  - Pipeline runs on PR head commits; statuses reported via DevOps/GitHub integration.
  - Once pipeline succeeds, PR can be merged.

## Environment Usage
| Environment | Purpose | Responsibilities |
|-------------|---------|------------------|
| Dev Workspace (`mlwdevcc01`) | Execution sandbox for CI runs | Run unit tests, execute partial pipeline through CompareTaxiFare, host short-lived endpoints, persist run/evaluation artifacts for audit |
| Dev External Registry (`mlrdevcc01`) | Promotion gate for validated models | Receive only models that passed CompareTaxiFare, capture tags (`branch`, `commit`, `run_id`), serve as the hand-off source for prod release |
| Prod Workspace (`mlwprodcc01`) | Production serving environment | Consume vetted models from the Dev registry via the prod release pipeline; no training or manual experimentation; uses blue/green deployments with rollback parity to Dev |

## GitHub Configuration Prerequisites
- **Secrets (service principal authentication for CI/CD workflows)**
  - `AZURE_CLIENT_ID`
  - `AZURE_CLIENT_SECRET`
  - `AZURE_TENANT_ID`
  - `AZURE_SUBSCRIPTION_ID`
- **Repository Variables (used by `.github/workflows/integration-ml-ci.yml` and `.github/workflows/prod-ml-release.yml`)**
  - Dev: `AML_DEV_RESOURCE_GROUP`, `AML_DEV_WORKSPACE`, `AML_DEV_COMPUTE`, `AML_DEV_REGISTRY`, `AML_DEV_DEPLOYMENT_NAME` (optional, defaults to `blue`), `AML_DEV_TRAFFIC_PERCENT` (optional, defaults to `30`)
  - Prod: `AML_PROD_RESOURCE_GROUP`, `AML_PROD_WORKSPACE`
  - Optional convenience: `AML_MODEL_BASE` (defaults to `taxi-class` when absent)
- The integration workflow now captures and reuses the exact model version produced by `pipelines/integration-compare-pipeline.yaml`; these secrets/variables must be in place before the workflow runs or the deployment guard will fail.

## Security Considerations
- Use a dedicated Azure AD service principal for the GitHub Actions workflows so credentials are scoped and rotated independently of runtime managed identities.
- Scope access narrowly to the Dev workspace and Dev registry for integration runs; the prod release pipeline uses a separate identity limited to the Prod workspace.
- Keep sensitive configuration values in Key Vault linked to the Dev workspace when needed and mirror prod secrets in prod-controlled vaults only.

## Artifact Flow and Traceability
- Integration pipeline records the `az ml job` run ID and surfaces CompareTaxiFare metrics in logs and artifacts.
- Successful runs promote the model to the Dev registry with tags for `integration`, commit SHA, and pipeline run ID.
- Post-promotion validation records Dev deployment job IDs and traffic allocation decisions so Operators can trace blue/green rollout steps.
- Prod release pipeline references those tags/run IDs when retrieving the model, creating an auditable chain from code change to production deployment.

## Prod Release Pipeline Overview
1. Triggered manually or automatically after integration pipeline success (e.g., when merging `integration` to `main`).
2. Pulls the vetted model version from the Dev registry based on tags or an approval list.
3. Deploys the model into the Prod workspace using blue/green strategy (30% traffic to the new slot when a prior deployment exists) and runs smoke or health checks that mirror the Dev validation.
4. Posts deployment status back to source control and records the production run ID for traceability.
5. If all checks pass, finalizes the merge into `main` (or other prod branch) and updates release notes.
6. On failure, restore 100% traffic to the previous deployment (or tear down the new endpoint if it was the first attempt) using the stored `deployment_state.json` metadata and the `update_traffic` component before surfacing the failure signal to block the merge.

## Branch and Policy Alignment
- Protect `integration` with required status checks from the integration pipeline and enforce PR review.
- Require prod release pipeline success (status check or manual approval) before merging into `main`; when prod deployment fails, ensure rollback run completes before re-opening the merge attempt.
- Document rollback procedures tied to both the Dev registry version and the Prod workspace deployment history.

- `.github/workflows/integration-ml-ci.yml` runs on PRs and pushes targeting `integration` with changes in `src/**` or the integration pipeline definition. Jobs cover unit tests, the `pipelines/integration-compare-pipeline.yaml` submission, and (for pushes) `pipelines/dev-deploy-validation.yaml` to stage, test, and promote the model inside the Dev workspace before the next merge.
- The same workflow now exposes a `workflow_dispatch` trigger so operators can manually kick off the compare pipeline from feature branches; optional inputs control the artifact suffix and whether to execute the Dev deployment validation stage during the manual run.
- `.github/workflows/prod-ml-release.yml` is a manual release workflow that submits `pipelines/prod-deploy-pipeline.yaml` to the Prod workspace, pulling the approved model from the Dev registry and orchestrating blue/green traffic updates once validation succeeds.
- Repository secrets required: `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (service principal credentials for the CI/CD identity).
- Repository variables recommended: `AML_DEV_RESOURCE_GROUP`, `AML_DEV_WORKSPACE`, `AML_DEV_COMPUTE`, `AML_DEV_REGISTRY`, `AML_DEV_DEPLOYMENT_NAME`, `AML_DEV_TRAFFIC_PERCENT`, `AML_PROD_RESOURCE_GROUP`, `AML_PROD_WORKSPACE`.
- New pipeline definitions `pipelines/integration-compare-pipeline.yaml`, `pipelines/dev-deploy-validation.yaml`, and `pipelines/prod-deploy-pipeline.yaml` stage validation, Dev deployment tests, and Prod blue/green rollouts respectively without retraining steps.

## Observability
- Emit run IDs for ML jobs to pipeline logs for traceability.
- Upload `compare_job` reports as pipeline artifacts for review.
- Consider adding Application Insights logging for pipeline steps.

## Next Steps
1. Draft the CI pipeline YAML (Azure DevOps/GitHub Actions) that mirrors these integration stages and reuses existing command components under `components/` and scripts in `src/`.
2. Confirm the existing entry points (`src/compare/compare.py`, `src/register/register.py`, etc.) expose the parameters the pipeline needs; add lightweight wrappers only if argument reshaping is required.
3. Wire up Azure authentication for the CI runner using the service principal credentials stored in GitHub Secrets and validate that the scripts work with those permissions.
4. Configure branch protections and required status checks on `integration` and `main`, adding manual approval gates for the prod release pipeline.
5. Author the prod release pipeline YAML that pulls the promoted model from the Dev registry, deploys to the Prod workspace, runs smoke tests, and references the existing deployment scripts in `src/`.
6. Document and dry-run the rollback automation added to both deployment pipelines, ensuring the `rollback_job` cleans up traffic and slots as expected.
7. Populate repo variables (`AML_DEV_DEPLOYMENT_NAME`, `AML_DEV_TRAFFIC_PERCENT`, `AML_PROD_DEPLOYMENT_NAME`, `AML_PROD_TRAFFIC_PERCENT`) to steer default slot names and traffic percentages where overrides are still required, or rely on the automatic selector when unset.
8. Extend observability to capture rollback events (traffic deltas, deleted deployments) from the stored metadata so operators can audit each promotion attempt.
9. Adopt `scripts/run-aml-pipelines.ps1` for end-to-end pipeline testing; wire it into documentation or internal runbooks so platform teams can execute integration → dev validation → prod rollout sequences on demand.

## Operator Runbook

### 1. Feature Branch Self-Validation
- **When**: Developer wants early signal before opening a PR.
- **Actions**:
  - Run unit tests locally (`pytest src`).
  - Optionally trigger `integration-ml-ci` via `workflow_dispatch` targeting their branch to execute the compare pipeline without registering models or touching shared endpoints.
- **Artifacts to Inspect**: GitHub Actions logs, `compare_job` report in run artifacts.
- **Cleanup**: None. No shared deployments created.

### 2. Integration Pipeline – No Prior Dev Deployment
- **When**: First successful merge to `integration` or dev endpoint was manually removed.
- **Actions**:
  - Monitor `integration-ml-ci.yaml` run: expect job submission for `pipelines/dev-deploy-validation.yaml`.
  - Confirm endpoint creation and validation logs under `test_job` (CLI: `az ml job show` with job name from logs).
- **Artifacts to Inspect**: `deployment_status` output for slot metadata, `test_job` report for invoke results.
- **Post-Run Cleanup**: Remove the dev deployment when testing completes using `azureml online-endpoint delete --name <endpoint> --resource-group ... --workspace ...` or the equivalent script. **Do not delete models automatically**; model versions stay in the workspace/registry unless operators manually run the cleanup script.

### 3. Integration Pipeline – Existing Dev Deployment
- **When**: Endpoint already serving traffic (blue/green) and new model deploys to existing slot.
- **Actions**:
  - Verify `deploy_job` preserved previous traffic distribution (check `deployment_state.json`).
  - Review `traffic_job` logs to ensure the configured percentage moved to the validated slot.
- **Artifacts to Inspect**: `deployment_state.json`, `test_job` report, Azure ML endpoint metrics.
- **Post-Run Cleanup**: Once manual/UAT testing completes, delete the dev deployment slot or the entire endpoint to return to a clean state. Leave model versions untouched unless performing deliberate cleanup.

### 4. Integration Pipeline Failure
- **When**: `test_job` fails (validation error) or earlier job errors.
- **Actions**:
  - Pull logs with `az ml job download --name <test_job_id> --all`.
  - If deployment was created, confirm `rollback_job` restored prior traffic.
  - Diagnose data/payload issues using the downloaded artifacts.
- **Artifacts to Inspect**: `test_job` stdout, `rollback_job` logs, Azure ML endpoint invocation traces.
- **Cleanup**: Delete any failed deployment slot that remains; models remain registered for later analysis.

### 5. Prod Release Pipeline
- **When**: Manual run of `.github/workflows/prod-ml-release.yml` after integration validation.
- **Actions**:
  - Confirm model version pulled from registry matches approved tags.
  - Monitor blue/green rollout through `deploy_job`, `test_job`, and `traffic_job` outputs.
- **Artifacts to Inspect**: GH Actions logs, Prod workspace job outputs, endpoint health metrics.
- **Post-Run Cleanup**: Prod deployments remain; no model deletions performed automatically. Rollback script handles traffic only if validation fails.

### 6. Manual Model Cleanup (Optional)
- **When**: Operators need a clean registry/workspace for ad-hoc testing or to reclaim storage.
- **Actions**:
  - Execute `python src/cleanup_models/cleanup_models.py --model_name <name> --registry <registry> --retain_versions 1 --dry_run` to preview.
  - Re-run without `--dry_run` when satisfied. **This script is manual only; CI/CD workflows do not delete models.**
- **Artifacts to Inspect**: `cleanup_report.json` (if `--output_folder` supplied), console output listing deletions.
- **Cleanup**: None beyond script execution.
