# Notebooks

Sandbox experiments and walkthroughs live here. The folder is organized by scenario:

- `00_submit_azureml_pipelines.ipynb` loads and submits the workshop pipeline YAML through the Azure ML Python SDK using `.env` settings.
- [Workspace Readiness](workspace_readiness/README.md) provides adapted foundation
  and job/pipeline notebooks for validating a deployed workspace, including
  managed-network checks and registry asset sharing. It has an isolated,
  four-value `.env`. Python setup is inline in every notebook, and validation
  operations run directly when their cells execute, without opt-in switches.
- `asset_sharing/` shows how to distribute assets across workspaces and registries.
- `deployments/` collects online deployment samples.
- `evaluations/` contains evaluation pipelines and data splits; the `evaluations_share/` folder mirrors artifacts intended for sharing.
- `h2o_mojo/` walks through creating, registering, and locally serving an H2O binary model with the Azure ML inference server.

Use `notebooks/conda.yaml` and `requirements.txt` to recreate the local notebook environment.
