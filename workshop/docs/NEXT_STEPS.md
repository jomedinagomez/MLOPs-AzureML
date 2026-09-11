# Next Steps Discussion

## Production MLOps

- Separate development and production workspaces and promotion approvals.
- Promote immutable model, environment, code, and data-contract versions together.
- Add validation gates before endpoint traffic changes.
- Retain the previous deployment for rollback.

## Airflow

- Use workload identity or managed identity.
- Package Azure ML submission and polling into one reusable Airflow operator/helper.
- Store submitted Azure ML job names for retry-safe recovery.
- Define ownership of Airflow retries versus Azure ML component retries.

## Monitoring

- Capture aggregate latency, throughput, rejection rate, and prediction distribution.
- Define data-quality, drift, and model-performance thresholds.
- Route alerts to the customer's operational system.
- Establish retention and access rules for scored and monitoring outputs.

## Security and Governance

- Keep CMK and private networking requirements explicit.
- Review every FQDN rule and remove destinations that are no longer required.
- Replace broad user assignments with Entra groups and least-privilege roles.
- Record model provenance, source license, validation evidence, and approver.

## Reliability and Cost

- Tune compute minimum/maximum nodes and idle scale-down.
- Select endpoint SKU and replica count from measured load.
- Test quota, regional capacity, disaster recovery, and endpoint rollback.
- Track Azure Firewall costs caused by FQDN managed-network rules.