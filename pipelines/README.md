# Azure ML Pipelines

Pipeline YAML definitions referenced by CI/CD live here:

- `integration-compare-pipeline.yaml` runs the compare job promoted by the integration workflow.
- `dev-deploy-validation.yaml` executes endpoint validation in the dev workspace.
- `prod-deploy-pipeline.yaml` handles production deployments and traffic orchestration.
- `dev-e2e-pipeline.yaml` holds the historical end-to-end template.

Keep the structure synchronized with `.github/workflows/` so overrides remain valid.
