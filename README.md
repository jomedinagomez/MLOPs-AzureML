# Azure ML Platform & MLOps Workflow

End‑to‑end Azure Machine Learning platform (dev + prod) plus opinionated MLOps workflow: reproducible componentized pipelines, model governance & promotion, private networking, and centralized AML DNS. Infrastructure rationale & deep architectural decisions are in `DeploymentStrategy.md`; this README focuses on how practitioners build, run, promote, and operate ML assets on top of the platform.

## Platform Snapshot
| Aspect | Implementation | Notes |
|--------|----------------|-------|
| Network | Flat dev/prod VNets + Bastion jumpbox | Bastion-only; private‑only access
| DNS | Central shared AML zones (api/notebooks/instances) | Revision 3 migration complete (validation pending)
| Workspaces | Dev & Prod (managed VNet, approved outbound) | Private endpoints only
| Registries | Dev & Prod (showcase pattern) | System‑assigned MI; promotion demo
| Identities | UAMI per workspace + UAMI per compute | Separation of network vs data roles
| Security | RBAC + private endpoints (no public ingress) | Principle of least privilege
| IaC | Terraform modules (`infra/`) | Single service principal orchestrates
| Data | Sample taxi dataset (`data/`) | Expandable pattern

## Quick Infrastructure Deploy
```bash
cd infra
terraform init
terraform plan
terraform apply
```
Configure `infra/terraform.tfvars` (purpose, location, address spaces, tags). Full infra detail: `DeploymentStrategy.md`.

---
## Repository Layout (High-Level)
```
infra/                Terraform root & modules
src/                  Component source code (Python)
	transform/          Feature engineering
	train/              Model training
	compare/            Champion vs candidate evaluation
	register/           Conditional model registration
	score/              Batch scoring / evaluation
	deploy/             (Future) Endpoint deployment logic
	predict/            Ad‑hoc / real-time inference sample
	components/*.yaml   Component specs (command, IO, env)
pipelines/            Pipeline job YAML definitions
environment/          Conda / requirements for train + score
notebooks/            Exploration & asset sharing demos
data/                 Sample taxi CSV + metadata YAML
DeploymentStrategy.md Architecture + security + DNS
```

---
## MLOps Lifecycle
| Phase | Goal | Source | Outputs | Automation |
|-------|------|--------|---------|------------|
| Ingest & Profile | Land raw data | `data/raw` | Cleaned dataset | External / manual (future ingestion pipeline)
| Feature Engineering | Deterministic features | `transform.py` | Transformed asset | Pipeline step
| Training | Train new model | `train.py` | Model artifact + metrics | Pipeline step
| Evaluation | Compare vs baseline | `compare.py` | Pass/Fail + champion flag | Pipeline gating
| Registration | Persist approved model | `register.py` | Model version (registry/workspace) | Conditional
| Scoring | Batch / evaluation run | `score.py` | Scored outputs + eval metrics | On demand / scheduled
| Promotion | Make model consumable across envs | Registry versions | Manual / governed
| Deployment | Serve model (future) | Endpoint / batch job | CD (future)
| Monitoring | Detect drift / decay | Metrics store | Retrain trigger | Scheduled (future)

---
## Components Overview (`src/components/*.yaml`)
| Component | Purpose | Key Outputs |
|-----------|---------|-------------|
| transform | Clean & feature engineer raw taxi data | transformed asset path |
| train | Train model & log metrics | model artifact (e.g. pkl), metrics JSON |
| compare | Compare candidate vs production baseline | decision flag (register? yes/no) |
| register | Register model + metadata | model version in registry/workspace |
| score | Batch score / evaluate model | scored dataset, eval metrics |
| deploy | (Future) Build + push for endpoint | deployment asset |
| predict | Simple inference script | predictions |

Design principles: Single responsibility, composable, environment‑agnostic (environment pinned in YAML), minimal side effects, deterministic outputs.

---
## Pipelines (`pipelines/*.yaml`)
| File | Flow | Notes |
|------|------|-------|
| `taxi-fare-train-pipeline.yaml` | transform → train → compare → conditional register | Core training & governance pipeline |
| `single-step-merge-job.yaml` | Simple component validation | Useful for quick registry tests |

Submit (dev workspace example):
```bash
az ml job create \
	--resource-group <rg-dev-ws> \
	--workspace-name <dev-workspace> \
	--file pipelines/taxi-fare-train-pipeline.yaml
```

Promotion gating implemented inside `compare.py` (add thresholds / metric logic). Registration only occurs when the compare step signals improvement or policy compliance.

---
## Environments
| Path | Purpose | Usage |
|------|---------|-------|
| `environment/train/conda.yaml` | Build & train runtime | transform / train / compare / register |
| `environment/train/additional_req.txt` | Extra pip deps | Merged at image build |
| `environment/score/conda.yaml` | Lean inference runtime | score / predict |
| `notebooks/conda.yaml` | Interactive dev kernel | Local experimentation |

Recommendation: Promote curated environments into registry for reproducibility (future enhancement: environment registration pipeline + version tagging).

---
## Notebooks (`notebooks/`)
* Exploration & debugging (e.g., registry sharing demo)
* Prototype logic before extracting to component code
* Use consistent environment spec for reproducibility

Workflow: Prototype → Hardening (src/*) → Component YAML → Pipeline → Registry asset.

---
## Asset Promotion Pattern
1. Dev pipeline registers model version in DEV registry.
2. Governance (automated compare + manual approval) decides promotion.
3. Copy/reference model into PROD registry (current design uses two registries for illustration; single shared registry is viable).
4. Prod pipeline / deployment consumes explicit version (strong pin) or approved tag.

Enhancements (future): tagging (`staging`, `prod`), automated rollback, multi-metric policy, bias/fairness checks.

---
## CI/CD (Recommended Outline)
| Stage | Trigger | Action |
|-------|---------|--------|
| Infra | Manual / tagged release | Terraform plan/apply
| Lint/Test | PR | Pytest + static analysis (add ruff/mypy)
| Component Build (optional) | Merge to main | Pre-build environment images
| Train Pipeline | Schedule + on-demand | Submit training job (dev)
| Promotion | Manual approval | Registry copy/tag
| Deploy | After promotion | Endpoint / batch job creation (future)

Sample (conceptual) GitHub Action step:
```yaml
- name: Submit training pipeline
	run: az ml job create --file pipelines/taxi-fare-train-pipeline.yaml \
			 --resource-group ${{ env.RG_DEV }} --workspace-name ${{ env.WS_DEV }}
```

---
## Developer Inner Loop
```bash
git pull
conda env create -f environment/train/conda.yaml -n aml-train || conda env update -f environment/train/conda.yaml -n aml-train
conda activate aml-train
python src/train/train.py --help  # local dry-run (mock input paths)
az ml job create --file pipelines/taxi-fare-train-pipeline.yaml ...
az ml job show --name <job-id>
```

---
## Source Code Highlights
| Script | Role |
|--------|------|
| `src/transform/transform.py` | Cleans & engineers taxi features |
| `src/train/train.py` | Trains model + logs metrics |
| `src/compare/compare.py` | Evaluates candidate vs baseline & sets register decision |
| `src/register/register.py` | Registers model (metadata, version) |
| `src/score/score.py` | Batch scoring / evaluation |
| `src/deploy/deploy.py` | Placeholder for future endpoint deployment |
| `src/predict/predict.py` | Lightweight inference utility |

---
## RBAC Snapshot (Operational)
| Principal | Scope | Roles (selected) |
|-----------|-------|------------------|
| Deployment SP | Env + Shared DNS RGs | Contributor, User Access Admin, Network Contributor |
| Workspace UAMI | Workspace RG + Registries | Azure AI Admin, Network Connection Approver, Storage Blob Data Owner, Key Vault Reader/Secrets User |
| Compute UAMI | Workspace + Data + Registries | AzureML Data Scientist, Storage Blob/File, Key Vault Secrets User, AzureML Registry User |

Full matrices & nuances (e.g., why workspace UAMI has no Registry User) are in `DeploymentStrategy.md`.

---
## Central AML DNS Migration (Status)
| Step | Description | State |
|------|-------------|-------|
| 1 | Shared zones created & spoke linked, per-env disabled | COMPLETE |
| 2 | Workspace PE zone groups repointed (api/notebooks/instances) | COMPLETE |
| 3 | DNS validation (checklist in DeploymentStrategy) | PENDING |
| 4 | Remove `prevent_destroy` & decide on toggle retention | PENDING |

Validation examples (from Bastion-connected jumpbox):
```bash
nslookup <dev-workspace>.<region>.api.azureml.ms
nslookup <prod-workspace>.<region>.api.azureml.ms
nslookup <dev-workspace>.<region>.notebooks.azure.net
```

---
## Roadmap (Suggested Next Enhancements)
* Environment artifact registration & reuse
* Automated drift detection + retrain trigger
* Endpoint deployment (blue/green or canary) automation
* Quality gates (test + lint) in CI
* Model tags & approval workflow
* Security scanning (supply chain / dependencies)

---
## Changelog Pointer
See `DeploymentStrategy.md` revision history (Key Vault RBAC fix, outbound rule shape, centralized AML DNS, etc.).

## License
MIT

## Quick Deploy
```bash
cd infra
terraform init
terraform plan
terraform apply
```
Configure `infra/terraform.tfvars` (purpose, location, address spaces, tags).

## Modules
| Module | Purpose | Key Outputs |
|--------|---------|-------------|
| aml-managed-umi | Workspace, storage, Key Vault, ACR, compute, private endpoints | workspace_id |
| aml-registry-smi | Registry (system MI), diagnostics, private endpoint | registry_id |

Private DNS for AML (api/notebooks/instances) is centralized in a shared DNS RG and linked to both VNets.

## Asset Promotion (High-Level)
1. Dev workspace registers assets → dev registry
2. Prod workspace outbound rule creates managed PE to dev registry
3. Prod compute (Registry User role) consumes assets
4. Workspace UAMIs only approve network (no registry data role)

## RBAC Snapshot
| Principal | Scope | Roles (examples) |
|-----------|-------|------------------|
| Deployment SP | Env & Shared DNS RGs | Contributor, User Access Admin, Network Contributor |
| Workspace UAMI | Workspace RG & registries | Azure AI Admin, Network Connection Approver, Storage Blob Data Owner, Key Vault Reader/Secrets User |
| Compute UAMI | Workspace + Storage + KV + Registries | AzureML Data Scientist, Storage Blob/File, Key Vault Secrets User, AzureML Registry User |

## AML DNS Migration Status
| Step | Description | State |
|------|-------------|-------|
| 1 | Create shared zones + spoke links; disable per-env zones | COMPLETE |
| 2 | Repoint workspace PE zone groups (api/notebooks/instances) | COMPLETE |
| 3 | DNS validation (see DeploymentStrategy) | PENDING |
| 4 | Remove `prevent_destroy` & optional toggle | PENDING |

## Repo Layout
```
infra/        Terraform root & modules
src/          ML components & scripts
pipelines/    Pipeline YAML
notebooks/    Sample notebooks
DeploymentStrategy.md
```

## License
MIT