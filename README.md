# Azure ML Platform & MLOps Workflow

End‑to‑end Azure Machine Learning platform (dev + prod) with an opinionated MLOps workflow: reproducible pipelines, model governance & promotion, private‑only networking, and centralized AML/Core Private DNS.

## Documentation Guide
- **This README** - Quick start, MLOps workflow overview, and developer guidance
- **[DeploymentStrategy.md](DeploymentStrategy.md)** - Comprehensive infrastructure architecture, design decisions, troubleshooting, and operational guidance (108KB)
- **[integration-ml-cicd-plan.md](integration-ml-cicd-plan.md)** - Detailed CI/CD pipeline implementation and branching strategy
- **[infra/README.md](infra/README.md)** - Terraform deployment guide with step-by-step instructions

## Platform Snapshot
| Aspect | Implementation | Notes |
|--------|----------------|-------|
| Network | Flat dev/prod VNets + Bastion jumpbox | Bastion‑only access; no VPN/SSH; peering only for admin VM reachability
| DNS | Central shared Private DNS zones for AML and core services | api.azureml.ms, notebooks.azure.net, instances.azureml.ms, blob/file/queue/table/vaultcore/azurecr
| Workspaces | Dev & Prod (managed VNet, allowOnlyApprovedOutbound) | Private endpoints only; publicNetworkAccess disabled
| Registries | Dev & Prod (for promotion demo; single registry viable) | System‑assigned MI; private‑only
| Identities | UAMI per workspace + UAMI per compute | Workspace UAMI for connectivity; compute UAMI for data/registry
| Security | RBAC + private endpoints (no public ingress) | Least privilege; management‑ vs data‑plane separation
| IaC | Terraform modules (`infra/`) | Single service principal orchestrates
| Data | Sample taxi dataset (`data/`) | Expandable pattern

Deterministic naming: names derive from `prefix`, `purpose`, `location_code`, `naming_suffix`; no random postfixes. Last Updated: 2025‑08‑09.

## Quick Infrastructure Deploy
```bash
cd infra
terraform init
terraform plan
terraform apply
```
Configure `infra/terraform.tfvars` (purpose, location, address spaces, tags). See “Architecture & Security” below for full details.

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
infra/                Architecture, security, DNS, RBAC (consolidated here)
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
## Asset Promotion Strategy & Cross‑Environment Access
This repo intentionally uses two registries (dev, prod) to demonstrate promotion; most prod deployments can use a single org registry.

RBAC essentials:
- Dev compute UAMI: full access in dev (Workspace Data Scientist, Storage Blob/File Contributor, KV Secrets User, AcrPull/AcrPush, Registry User on dev registry); no prod access.
- Prod compute UAMI: prod access (same roles at prod scopes) plus read‑only AzureML Registry User on the dev registry for consuming promoted assets.
- Workspace UAMIs: do not get AzureML Registry User. They are connectivity actors only and require Azure AI Enterprise Network Connection Approver at the registry scope to enable managed private endpoints via outbound rules.

Network essentials:
- Workspaces run in managed VNets with isolationMode “AllowOnlyApprovedOutbound”.
- Outbound rules to registries must set destination.subresourceTarget = "amlregistry".
- Azure ML auto‑creates managed private endpoints in the managed VNet; no manual PE or DNS steps.

Promotion outline:
1. Dev pipeline registers model version in the Dev registry.
2. Governance (compare.py + manual gate) approves.
3. Promote to Prod registry (copy/reference) for consumption.
4. Prod consumes explicit version or approved tag.

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
| Deployment SP | Env + Shared DNS RGs | [Contributor](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#contributor), [User Access Administrator](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#user-access-administrator), [Network Contributor](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/networking#network-contributor) |
| Workspace UAMI | Workspace RG + Registries | [Azure AI Administrator](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/ai-machine-learning#azure-ai-administrator), [Azure AI Enterprise Network Connection Approver](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/ai-machine-learning#azure-ai-enterprise-network-connection-approver), [Storage Blob Data Owner](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/storage#storage-blob-data-owner), [Key Vault Reader](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/security#key-vault-reader)/[Secrets User](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/security#key-vault-secrets-user) |
| Compute UAMI | Workspace + Data + Registries | [AzureML Data Scientist](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/ai-machine-learning#azureml-data-scientist), [Storage Blob Data Contributor](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/storage#storage-blob-data-contributor)/[Storage File Data Privileged Contributor](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/storage#storage-file-data-privileged-contributor), [Key Vault Secrets User](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/security#key-vault-secrets-user), [AzureML Registry User](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/ai-machine-learning#azureml-registry-user) |

Notes:
- Workspace UAMI also needs Key Vault Reader (management plane) and Key Vault Secrets User (data plane) on the workspace Key Vault to avoid 403 vaults/read during provisioning.
- Compute UAMI handles data and registry access; Workspace UAMI handles connectivity and approvals only.

---
## Central AML & Core Service Private DNS
Centralize these zones in a shared DNS RG and link both dev and prod VNets:
- AML: privatelink.api.azureml.ms, privatelink.notebooks.azure.net, instances.azureml.ms
- Core: privatelink.blob.core.windows.net, privatelink.file.core.windows.net, privatelink.queue.core.windows.net, privatelink.table.core.windows.net, privatelink.vaultcore.azure.net, privatelink.azurecr.io

Record coexistence: Dev and Prod records are prefixed by resource names and do not collide. Keep prevent_destroy on shared zones if you want protection.

Validation examples (from Bastion‑connected jumpbox):
```bash
nslookup <dev-workspace>.<region>.api.azureml.ms
nslookup <prod-workspace>.<region>.api.azureml.ms
nslookup <dev-workspace>.<region>.notebooks.azure.net
```

## Network Security & Outbound Rules
- Public network access is disabled for workspaces, registries, storage, key vaults, and ACR.
- Workspaces use managed VNet (approved outbound only) with user‑defined outbound rules for registries.
- Required shape (azapi): destination.serviceResourceId = registry ID and destination.subresourceTarget = "amlregistry".
- Create rules after assigning the Workspace UAMI the Azure AI Enterprise Network Connection Approver at the target registry scope; wait ~90–150s for RBAC propagation.

Note on registry pre‑authorization workaround: To prevent permission errors when Azure ML creates the managed private endpoint to a registry in private‑only setups, the registry is configured with `properties.managedResourceGroupSettings.assignedIdentities` to include the deployment principal’s objectId. This effectively grants Azure AI Administrator permissions over the registry’s Microsoft‑managed resource group so the platform can read needed metadata. See `infra/README.md` for verification commands.

Troubleshooting summary:
- 403 vaults/read during workspace create → add Key Vault Reader to Workspace UAMI.
- 409 FailedIdentityOperation after delete → add 150s slot wait before re‑create.
- 400 ValidationError on outbound rule → ensure subresourceTarget = "amlregistry".

## Verify After Apply (CLI)
PowerShell examples (Windows Bastion jumpbox). Expect:
1) Registry managed RG pre‑authorization shows your deployment SP in managedResourceGroupSettings.assignedIdentities[].
2) Outbound rules exist on dev and prod workspaces (including prod→dev).
3) Managed private endpoints exist in workspace managed RGs targeting registries with subresource "amlregistry".
4) Private‑only posture for Storage, Key Vault, ACR.
5) RBAC at registry scopes: Workspace UAMI (Approver) and Compute UAMI (Registry User).
See `infra/README.md` for exact commands.

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
Key recent changes: Key Vault RBAC fix (add Reader + Secrets User), outbound rule shape requires subresourceTarget, centralized AML/Core DNS.

## Platform limitations and constraints
- Managed virtual network limitations impact asset operations:
	- Components cannot be shared from workspace to registry; recreate from version control in target workspace.
	- Private registries cannot build environments directly when ACR public access is disabled. Use one of:
		- Reference environments from the dev registry in production via azureml://registries/<dev-reg>/environments/...
		- Recreate environments in the prod workspace using the same image URI from the dev environment metadata.
	- Azure ML Studio shows only MODEL assets under network isolation; use CLI/SDK for other asset types.
	- For secure workspace→registry sharing, the workspace storage must allow Selected networks and include the registry under Resource instances (this repo configures it automatically).

## Environment promotion behavior (images and components)
- Docker environments shared to a registry build an image that lives in the source registry’s ACR; promoting to another workspace reuses the same image URI. The image is not copied to the prod registry ACR.
- Components are not shareable across workspaces/registries; store their YAML in version control and recreate in the target workspace.
- Practical guidance and code examples are available in `notebooks/asset_sharing/sharing_assets_registries_workspaces.ipynb`.

## License
MIT