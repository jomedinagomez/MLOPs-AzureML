# Two-Day Azure Machine Learning Workshop

## Day 1: Azure ML Foundations and Pipelines

1. Azure Machine Learning introduction slides provided by the instructor.
2. Workshop outcomes, platform architecture, CMK, private networking, and MLOps lifecycle.
3. Compute-instance setup, Azure authentication, `.env`, permissions, and preflight validation.
4. Azure ML Studio tour: workspace, notebooks, compute, data, models, environments, endpoints, jobs, pipelines, and registries.
5. Register and inspect a data asset, environment, and model with the Python SDK v2.
6. Submit and inspect a command job.
7. Create, deploy, and invoke a managed online endpoint.
8. Submit the single-step merge job from a notebook.
9. Submit the integration compare pipeline from a notebook and inspect its child jobs and outputs.
10. Review lineage, reproducibility, immutable versions, managed identities, logs, and Day 2 prerequisites.

## Day 2: H2O Binary Models and Customer Onboarding

1. H2O binary-model compatibility, OpenJDK 17, manifests, checksums, and golden tests.
2. Create and validate the reference H2O binary-model bundle.
3. Test the reference model with the local Azure ML inference server.
4. Deploy and invoke the reference model on a managed online endpoint.
5. Submit the reference offline-scoring pipeline.
6. Add and validate a customer-provided H2O binary model and representative input data.
7. Register the validated customer bundle as an immutable custom model.
8. Create and register the version-pinned H2O environment.
9. Deploy the customer model at zero traffic, inspect logs, test directly, and optionally promote traffic.
10. Submit the static customer-scoring pipeline YAML.
11. Discuss the Airflow submission contract and why Airflow remains the production scheduler.
12. Review Dev/Prod promotion, monitoring, governance, rollout, rollback, cost, and guarded cleanup.