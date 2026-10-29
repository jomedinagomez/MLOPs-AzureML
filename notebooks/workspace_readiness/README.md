# Workspace Readiness

Validate a deployed Azure ML workspace from discovery through assets, jobs,
private endpoints, and registry sharing. Each notebook contains its own Python
setup, configuration loading, and required helpers; no shared Python module is
imported. These are adapted copies of the
[workshop foundations](../../workshop/notebooks/01_foundations) and
[job notebooks](../../workshop/notebooks/02_jobs_and_pipelines); the originals
remain unchanged.

## Configure once

Use the existing repository Python environment, or install
[requirements.txt](requirements.txt) into your own notebook environment. Select
that environment's kernel and sign in with `az login`. The notebooks consistently
use your signed-in Azure CLI identity, not credentials from another `.env`.

Setup reads the environment file directly with `dotenv_values`, assigns plain
workspace variables, and constructs `AzureCliCredential` and `MLClient` directly.
The same simple setup is visible inside every notebook.

Copy [.env.example](.env.example) to a local `.env`. Only four deployment
coordinates are needed:

```dotenv
AZURE_SUBSCRIPTION_ID=<subscription>
AZURE_RESOURCE_GROUP=<workspace-resource-group>
AZUREML_WORKSPACE_NAME=<workspace-name>
AZUREML_REGISTRY_NAME=<existing-registry-name>
```

The local configuration prepared for this run targets `mlwprivatencus07` in
`rg-aml-private-ncus-07`, using the existing `mlrprivatencus06` registry.
Change those coordinates to validate a different environment.

Each notebook reads **only this suite's `.env`**, without modifying process
environment variables, expanding inherited values, or searching parent `.env`
files. Missing values and unexpected keys are errors. The repository-root,
workshop, and older asset-sharing configurations are neither used nor changed.
No secrets, tokens, connection strings, tenant ID, or duplicate dev/prod aliases
belong here.

The suite discovers the sole compute cluster, its UAMI client ID, and the default
datastore. For multiple clusters, set `COMPUTE_NAME` in that notebook's
configuration cell. Endpoint notebooks resolve the Terraform-provisioned
`private-mi-online-endpoint` identity in the selected workspace's resource group;
change `ENDPOINT_IDENTITY_NAME` in the cell if your deployment uses another name.
No identity or role assignment is created automatically.

## Run in order

| Notebook | Validates | Effect when executed |
|---|---|---|
| [01 Workspace and compute](01_foundations/01_workspace_and_compute.ipynb) | Inventory, active managed network, registry outbound rule, Storage privacy | Read-only |
| [02 Data asset](01_foundations/02_register_data_asset.ipynb) | Local MLTable generation and workspace registration/readback | Registers data |
| [03 Environment](01_foundations/03_register_environment.ipynb) | Conda generation, base-image availability, registration/readback | Registers an environment |
| [04 Model](01_foundations/04_register_model.ipynb) | Transparent JSON model registration/readback | Registers a model |
| [05 Command job](01_foundations/05_submit_command_job.ipynb) | Cluster UAMI execution, completed run, downloaded summary | Submits a job |
| [06 Online endpoint](01_foundations/06_deploy_online_endpoint.ipynb) | Private Entra-authenticated scoring with the registered model | Deploys, invokes, and promotes blue to 100% |
| [07 Data collection](01_foundations/07_deploy_model_data_collection.ipynb) | Separate collector deployment on the discovered default datastore | Deploys, invokes, and promotes collector to 100% |
| [08 Registry sharing](01_foundations/08_register_assets_to_registry.ipynb) | Native model/environment/data sharing with immutable-version readback | Shares the selected assets |
| [Single-step job](02_jobs_and_pipelines/01_submit_single_step_merge.ipynb) | Existing YAML definition and cluster execution | Submits a job |
| [Integration pipeline](02_jobs_and_pipelines/02_submit_integration_compare.ipynb) | Merge, transform, train, predict, compare, registry registration | Submits the full pipeline |

There are **no registration, submission, deployment, sharing, or promotion
switches**. These operations run directly when their cells execute, so there is
nothing to set to `True` in `.env`. Result verification and explicit error
handling remain. Run earlier registration notebooks before the notebooks that
consume their assets.

Asset names are inline constants in each notebook and use the distinct
`readiness-taxi-*` prefix. Endpoint names include the selected workspace name.
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
folder, suite folder, or either copied notebook folder.

## Connectivity is not asset authorization

- The workspace UAMI's **Network Connection Approver** role establishes managed
  private connectivity. It does not authorize the notebook caller or cluster
  identity to publish registry assets.
- Foundation 08 uses the **notebook caller** and native `share` APIs. It resolves
  source versions once, checks destination collisions, refuses to overwrite
  existing versions, and retrieves each shared asset for verification.
  Select kinds and source/target versions in its configuration cell.
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
access. Notebook 06 promotes its tested blue deployment to 100% traffic; notebook
07 subsequently promotes collector to 100%. No automatic Azure cleanup is performed.

## Local checks

From the repository root:

```powershell
python -m pytest -q tests\test_workspace_readiness.py
python workshop\scripts\validate_notebooks.py notebooks\workspace_readiness
```

These checks do not submit Azure jobs, deploy endpoints, share assets, or alter
roles/networking. They do not replace running the selected validations against
your Azure environment one notebook cell at a time.
