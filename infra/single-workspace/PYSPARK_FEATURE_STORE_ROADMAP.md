# PySpark and Feature Store Roadmap

The replacement root provisions an Azure ML managed network for serverless Spark.
Infrastructure readiness is complete only when post-deployment validation confirms:

- `AllowOnlyApprovedOutbound`
- managed-network status `Active`
- `sparkReady=true`
- exactly one Azure-created default-Storage Blob rule
- that rule is active and Spark-enabled
- workspace UAMI has Storage `Contributor` and `Storage Blob Data Contributor`

The first workload gate is the checked-in managed-identity serverless Spark example
under `workshop\notebooks\06_spark_jobs_pipelines`.

Under approved-only outbound, Spark session Conda installation is unsupported. Package
custom dependencies as self-contained wheels in approved Storage and pass them through
`py_files`; FQDN rules do not change this restriction.

Feature-store selection remains deferred until the deterministic Spark workload
completes successfully. The decision must document offline and online stores,
point-in-time correctness, freshness, latency, identity, networking, encryption,
operations, and cost.
