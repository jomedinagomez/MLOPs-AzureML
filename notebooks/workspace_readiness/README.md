# Workspace Readiness

Validate a deployed Azure ML workspace from discovery through assets, jobs,
private endpoints, and registry sharing. Each notebook contains its own Python
setup, configuration loading, and required helpers; no shared Python module is
imported. These are adapted copies of the
[workshop foundations](../../workshop/notebooks/01_foundations) and
[job notebooks](../../workshop/notebooks/02_jobs_and_pipelines); the originals
remain available separately.

For a step-by-step setup and notebook execution guide, see [RUNNING.md](RUNNING.md).

## Configure once

Use the existing repository Python environment, or install
[requirements.txt](requirements.txt) into your own notebook environment. Select
that environment's kernel. Set `USE_MANAGED_IDENTITY=true` on an Azure compute
instance or cluster, or `false` locally after `az login`. The flag selects
`ManagedIdentityCredential` or `AzureCliCredential` explicitly; invalid values
are errors, and an omitted flag defaults to `true`.

Setup reads the environment file directly with `dotenv_values` and constructs
`MLClient` directly. The command/pipeline and active endpoint notebooks keep
setup concise and leave resource validation to Azure ML.

Copy [.env.example](.env.example) to a local `.env`. Four deployment coordinates
are required for registry operations. Command-job notebook 05 and both pipeline
notebooks require an explicit compute name and the cluster identity's Client ID:

```dotenv
AZURE_SUBSCRIPTION_ID=<subscription>
AZURE_RESOURCE_GROUP=<workspace-resource-group>
AZUREML_WORKSPACE_NAME=<workspace-name>
AZUREML_REGISTRY_NAME=<existing-registry-name>
AZUREML_COMPUTE_NAME=<compute-cluster-name>
AZUREML_COMPUTE_IDENTITY_CLIENT_ID=<cluster-managed-identity-client-id>
USE_MANAGED_IDENTITY=true
```

Use coordinates from the Azure environment you intend to validate.

Each notebook reads **only this suite's `.env`**, without modifying process
environment variables, expanding inherited values, or searching parent `.env`
files. Missing required values are errors. The concise job/endpoint setups
ignore unused keys; the older asset/inventory setups reject unexpected keys.
The repository-root,
workshop, and older asset-sharing configurations are neither used nor changed.
No secrets, tokens, connection strings, tenant ID, or duplicate dev/prod aliases
belong here. The authentication flag does not move notebook execution, grant
permissions, or establish private routing. The notebook and this configuration
must be available on the host that actually executes its cells.

Notebook 05 and both pipeline notebooks pass `AZUREML_COMPUTE_NAME` directly
to the job without compute discovery or identity-resource reads. Inventory
notebook 01 retains discovery when the cluster name is omitted. The integration
pipeline still discovers the workspace's default datastore.
`AZUREML_COMPUTE_IDENTITY_CLIENT_ID` selects the cluster's UAMI directly.
Use its **Client ID**, not its Principal ID. It controls the submitted job's
runtime identity, independently of `USE_MANAGED_IDENTITY`, which selects the
notebook caller. The configured identity must already be attached to the cluster
and authorized to access the job's data.

Active endpoint notebooks 06 and 09 instead use **system-assigned endpoint
identities**. They do not consume the cluster Client ID or read a UAMI resource.
They use fresh `-workspace-sami-v2` and `-registry-sami-v2` names, leave old endpoints
untouched, and reject an existing endpoint with the wrong identity type.
Creation, deployment, invocation, and promotion remain explicit cells. Review
the new principal ID and required artifact access before deployment; no notebook
explicitly grants RBAC roles, deletes an endpoint, or opens network access.
Model data collection in notebook 07 is deferred; its deployment logic is
unchanged.

## Run in order

| Notebook | Validates | Effect when executed |
|---|---|---|
| [01 Workspace and compute](01_foundations/01_workspace_and_compute.ipynb) | Inventory, active managed network, registry outbound rule, Storage privacy | Read-only |
| [02 Data asset](01_foundations/02_register_data_asset.ipynb) | Local MLTable generation and workspace registration/readback | Registers data |
| [03 Environment](01_foundations/03_register_environment.ipynb) | Conda generation, base-image availability, registration/readback | Registers an environment |
| [04 Model](01_foundations/04_register_model.ipynb) | Transparent JSON model registration/readback | Registers a model |
| [05 Command job](01_foundations/05_submit_command_job.ipynb) | Cluster UAMI execution, completed run, downloaded summary | Submits a job |
| [06 Online endpoint](01_foundations/06_deploy_online_endpoint.ipynb) | System-assigned identity and workspace model/environment | Deploys, invokes, and promotes `workspace` on a new endpoint |
| [07 Data collection](01_foundations/07_deploy_model_data_collection.ipynb) | Deferred | Do not run as part of this update |
| [08 Registry sharing](01_foundations/08_register_assets_to_registry.ipynb) | Native model/environment/data sharing with immutable-version readback | Shares the selected assets |
| [09 Registry endpoint](01_foundations/09_deploy_registry_online_endpoint.ipynb) | System-assigned identity with both model and environment pinned to external-registry versions | Deploys, invokes, and promotes `registry` on a separate new endpoint |
| [Single-step job](02_jobs_and_pipelines/01_submit_single_step_merge.ipynb) | Existing YAML definition and cluster execution | Submits a job |
| [Integration pipeline](02_jobs_and_pipelines/02_submit_integration_compare.ipynb) | Merge, transform, train, predict, compare, registry registration | Submits the full pipeline |

In notebook 05 and both pipeline notebooks, run **setup**, **preparation**,
**submission**, **status**, and **outputs** as separate cells. Only submission
starts a job. Status is a manual snapshot. In all three notebooks, the output cell
waits up to 20 minutes, checking every 10 seconds, before downloading.
A timeout leaves the run untouched; rerun the output cell to keep waiting.
Downloads require `Completed`; the SDK resolves each named output's artifact
location. The code does not assume that `jobs.get().outputs[name].path` is
populated or guess a storage path. Downloaded JSON responses are displayed.
Failed/canceled jobs raise an error rather than being presented as successful;
all three also raise explicitly if their completion wait times out.
The SDK log streamer is not used: its SAS-generation path treats a token
credential as an account key in the current environment.
After a kernel restart, replace `submitted_job.name` in the status cell with the
quoted existing run name. Do not resubmit just to retrieve a response.

VS Code supplies the notebook path. Outside VS Code, start the concise
notebooks' kernels in their own notebook folder, and make the suite configuration
and shared workshop files available on that host. `false` supports local Azure
CLI authentication, but private workspaces/registries still require VPN/private
routing and DNS; the flag does not enable public access.

There are **no registration, submission, deployment, sharing, or promotion
switches**. The authentication flag does not gate these operations: they run when
their cells execute. Result verification and explicit errors remain. Run
registration notebooks before their consumers; notebook 09 consumes the assets
shared by notebook 08, not workspace copies.

Asset names are inline constants in each notebook and use the distinct
`readiness-taxi-*` prefix. Endpoint names include the selected workspace name:
06 uses `<workspace-prefix>-workspace-sami-v2` with deployment `workspace`;
09 uses `<workspace-prefix>-registry-sami-v2` with deployment `registry`.
Previously created endpoints are not renamed or deleted.
Endpoint definitions use the SDK value `system_assigned`, which serializes to
ARM's `SystemAssigned`. Identity checks account for casing and underscores in SDK
readback, including endpoints created with the earlier enum-based definition;
user-assigned, combined, and missing identities are still rejected.
Change corresponding names in producer and consumer notebooks together when
validating other assets. Asset-version selections, deployment sizes, and sampling
remain visible notebook choices, not environment variables.

The suite reuses checked-in sample inputs under
[workshop/data](../../workshop/data) and the existing
[six-step pipeline](../../workshop/pipelines/integration-compare-pipeline.yaml),
including its component/environment definitions. Generated scoring scripts,
Conda files, MLTable metadata, and downloads go to this suite's ignored `outputs`
directory, not workshop outputs. The shared CSV, YAML, and component files remain
dependencies by design; only notebook Python helpers are inlined. Run from the repository root, main notebooks
folder, suite folder, or either copied notebook folder for the older discovery
setups. The concise setups use the notebook path in VS Code or their own folder
as the working directory elsewhere.

## Connectivity is not asset authorization

- The workspace UAMI's **Network Connection Approver** role establishes managed
  private connectivity. It does not authorize the notebook caller or cluster
  identity to publish registry assets.
- Foundation 08 uses the **notebook caller** and native `share` APIs. It resolves
  source versions once and automatically chooses the highest integer destination
  version plus one (or `1` for a new asset), including archived versions.
  Non-integer versions are left untouched. Versions are refreshed before sharing;
  rerunning registration creates new versions and verifies their readback.
  Select kinds and source versions in its configuration cell. Avoid concurrent
  registration of the same assets; version selection is not an atomic reservation.
- The integration pipeline's sixth step uses the **compute cluster UAMI** to
  register mounted MLflow output directly in the registry. That identity needs
  **AzureML Registry User** on the target registry. Executing the submission cell
  includes this registry write. No roles are granted by the notebook.
- Native sharing also needs registry-to-source-Storage access. Successful
  workspace-to-registry endpoints do not prove this reverse service path works.
  Do not add firewall exceptions, policy exemptions, or administrator roles
  automatically to work around a failed sharing operation.
- Workspace 07's managed registry endpoints were verified Active/Approved.
  Its initial laptop-upload blocker was resolved after explicit approval:
  Storage `stprivatencus07` now has `SecurityControl=Ignore` and public access
  enabled for the single approved laptop IP, with default deny. Shared keys and
  anonymous Blob access remain disabled, and private endpoints are unchanged.
  Authenticated laptop Blob access was verified. The Terraform private baseline
  can reset this manual Storage exception; review any later apply carefully.

Endpoint deployments and jobs can incur charges. Private endpoint invocation
also requires private routing; these notebooks do not enable public endpoint
access. Notebooks 06 and 09 promote only their own tested new endpoints.
Notebook 07's model data collection is deferred. No automatic Azure cleanup is
performed.

## Local checks

From the repository root:

```powershell
python -m pytest -q tests\test_workspace_readiness.py
python workshop\scripts\validate_notebooks.py notebooks\workspace_readiness
```

These checks do not submit Azure jobs, deploy endpoints, share assets, or alter
roles/networking. They do not replace running the selected validations against
your Azure environment one notebook cell at a time.
