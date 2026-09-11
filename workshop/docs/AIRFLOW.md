# Airflow Integration Contract

Airflow is the production scheduler. Azure ML owns the ML execution graph and compute lifecycle. Do not create a second Azure ML schedule for the same production process.

## Submission Flow

```text
Airflow task
  -> authenticate to Azure
  -> load h2o-customer-scoring-pipeline.yaml
  -> bind immutable model, data, environment, compute, and correlation ID
  -> submit Azure ML job
  -> persist the Azure ML job name
  -> poll until a terminal status
  -> publish output URIs to downstream tasks
```

## Authentication

Use workload identity or managed identity in the Airflow runtime. Interactive Azure CLI authentication is for the workshop only. Do not use a client secret in the DAG or `.env`.

## Required Inputs

| Input | Contract |
| --- | --- |
| Model | Immutable Azure ML custom-model name and version |
| Scoring data | Immutable data asset or approved datastore URI |
| Environment | Immutable environment name and version |
| Compute | Existing Azure ML compute cluster |
| Correlation ID | Stable Airflow DAG/run identifier |
| Reject policy | Explicit boolean controlling whether invalid rows fail the job |
| H2O JVM sizing | Explicit thread count and maximum heap size from approved runtime configuration |

## Terminal States

Treat `Completed` as success. Treat `Failed`, `Canceled`, and `NotResponding` as failure. Continue polling queued, preparing, provisioning, starting, and running states with bounded backoff.

## Idempotency

- Persist the Azure ML job name in Airflow task metadata before polling.
- On task retry, query the existing job before submitting another run.
- Use the Airflow run ID as the scoring correlation ID.
- Give each execution unique Azure ML output paths.
- Never resolve `latest` after a release has been approved.

## Outputs

The pipeline produces a scored-output folder and a monitoring-output folder. Downstream tasks should consume the returned Azure ML output URIs rather than reconstructing storage paths.