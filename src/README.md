# Source Code

Application and pipeline helper code lives here. Key areas:

- `components/` – YAML component specs consumed by Azure ML pipelines.
- Script folders (`compare`, `deploy`, `register`, etc.) – Python entry points used inside jobs.
- `cleanup_models/` – Utilities for pruning old model versions.
