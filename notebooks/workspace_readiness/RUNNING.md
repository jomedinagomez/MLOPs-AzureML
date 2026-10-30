# Running the Workspace Readiness Notebooks

Run these notebooks directly in VS Code, one cell at a time. No notebook runner
script is needed. The notebooks use the sample files in this repository's
`workshop` directory, so keep the repository together.

## 1. Prepare the environment

1. Use Python 3.10 or later and select a notebook kernel with the packages in
   [requirements.txt](requirements.txt) installed. An existing Azure ML compute
   instance kernel can be used if it has the required packages.
2. Ensure the machine running the notebooks can reach the workspace, registry,
   and their Storage/ACR endpoints. Private resources require private routing and
   DNS; changing the authentication option does not provide network access.
3. Ensure the notebook caller has the required workspace and registry
   permissions. The configured compute cluster and its user-assigned managed
   identity must already exist and have access to the job inputs and outputs.
4. Copy [.env.example](.env.example) to a file named `.env` in this folder and
   fill in the workspace, registry, compute cluster name, and cluster identity
   **Client ID**. Use the Client ID, not the Principal ID. Do not put secrets or
   tokens in the file; the local `.env` is ignored by Git.
5. Set `USE_MANAGED_IDENTITY=true` when the notebook runs on Azure compute with a
   managed identity. Set it to `false` when using Azure CLI authentication, and
   sign in with `az login` on that machine first.

The authentication option selects the **notebook caller**. The cluster Client ID
selects the submitted **job identity**; the system-assigned identity on each
online endpoint is separate from both.

## 2. Run the notebooks

Open each notebook and run its code cells from top to bottom:

1. [01 Workspace and compute](01_foundations/01_workspace_and_compute.ipynb):
   inspect the workspace, compute, and connectivity.
2. [02 Data asset](01_foundations/02_register_data_asset.ipynb),
   [03 Environment](01_foundations/03_register_environment.ipynb), and
   [04 Model](01_foundations/04_register_model.ipynb): register the workspace
   assets needed by the later notebooks.
3. [05 Command job](01_foundations/05_submit_command_job.ipynb): submit a job
   to the configured cluster and download its summary after it completes.
4. [06 Online endpoint](01_foundations/06_deploy_online_endpoint.ipynb): create
   a private, system-assigned endpoint using the workspace model and
   environment, then deploy and invoke `workspace`.
5. Skip **07 model data collection**; it is deferred.
6. [08 Registry sharing](01_foundations/08_register_assets_to_registry.ipynb):
   preview and share the workspace model, environment, and data to the configured
   registry. Registration selects new numeric destination versions.
7. [09 Registry endpoint](01_foundations/09_deploy_registry_online_endpoint.ipynb):
   create a separate private, system-assigned endpoint and deploy `registry`
   using the model and environment from the external registry.
8. Run the jobs in [02_jobs_and_pipelines](02_jobs_and_pipelines):
   [01 Single-step merge](02_jobs_and_pipelines/01_submit_single_step_merge.ipynb)
   followed by
   [02 Integration compare](02_jobs_and_pipelines/02_submit_integration_compare.ipynb).
   The integration pipeline includes registry registration by the cluster
   identity, which needs the appropriate registry permissions.

Check each cell's output before continuing. Notebooks 06 and 09 invoke their
deployments and check the response before promoting traffic. Notebook 08 and the
integration pipeline require registry access; see the
[README](README.md#connectivity-is-not-asset-authorization) for details.

## 3. Monitor jobs and avoid duplicate submissions

In notebook 05 and both pipeline notebooks, preparation, submission, status, and
output retrieval are separate cells. **Rerunning a submission cell starts another
job.** The output cell checks the existing run every 10 seconds for up to 20
minutes, downloads only after completion, and reports a terminal failure.

If the wait times out, the Azure job is not canceled. Check it in Azure ML
Studio or rerun only the output cell to keep waiting. After a kernel restart,
rerun setup, then replace `submitted_job.name` in the status cell with the quoted
existing run name before checking status and retrieving the output. Do not
resubmit just to retrieve a result.

Generated files and downloads are kept under this suite's ignored `outputs`
directory. Endpoint deployments and compute jobs can incur charges, including
while an endpoint is idle. No notebook automatically deletes Azure resources;
remove resources you no longer need through your normal Azure cleanup process.
