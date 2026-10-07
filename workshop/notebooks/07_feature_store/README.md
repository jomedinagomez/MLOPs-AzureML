# Azure ML Managed Feature Store Demo

This module follows the talk track in [FEATURE_STORE_TALK_TRACK.md](FEATURE_STORE_TALK_TRACK.md). It runs the
official Microsoft [`featurestore_sample`](https://github.com/Azure/azureml-examples/tree/65eceac7ff5cd2417af5f24d38192ab8e445dd85/sdk/python/featurestore_sample)
notebooks **from your local computer**. The notebooks also submit **Azure ML serverless Spark** jobs and use offline and
online **materialization**. Code is copied from the official notebooks; the local-execution changes are listed below.

- [FEATURE_STORE_TALK_TRACK.md](FEATURE_STORE_TALK_TRACK.md) — slide-ready talk track (Part 1) and complete
  Microsoft Learn reference content (Part 2) for a Copilot-generated slide deck.
- [AzureMLDocumentation/](AzureMLDocumentation/) — the eight Learn PDFs, their extracted figures, and PNG renders of every page.
- [featurestore_sample/](featurestore_sample/README.md) — official `featurestore/` and `project/` assets used by the notebooks.

## Where each step runs

| Label in the notebooks | Runs on | Examples |
|---|---|---|
| **[Local]** | Your computer: local Spark or local Python | Develop and test feature set specs, local point-in-time joins, online feature lookup |
| **[Control plane]** | Azure ML or Azure Resource Manager APIs called from your computer | Create the feature store, register entities and feature sets, assign roles, create Azure Managed Redis and the endpoint |
| **[Serverless Spark]** | Azure ML managed Spark, submitted from your computer | Offline and online materialization (backfill and recurrent), feature retrieval in training and batch inference pipelines |

Materialization jobs always run on Azure ML managed serverless Spark. Your computer submits and monitors them.

## Notebook order

| Notebook | Official source | What it shows | Talk track |
|---|---|---|---|
| [00_prepare_sample_data](00_prepare_sample_data.ipynb) | New | Synthetic data with the official schema: local copy and ADLS Gen2 copy | Slide 13 |
| [01_develop_feature_set_and_register](01_develop_feature_set_and_register.ipynb) | Tutorial 1 | Create the feature store; develop `transactions` locally; register; local point-in-time join; offline backfill on serverless Spark | Slides 5–15 |
| [02_experiment_and_train_models](02_experiment_and_train_models.ipynb) | Tutorial 2 | Local experiments with unregistered features; register `accounts`; retrieval spec; training pipeline reading the offline store on serverless Spark | Slides 15–18 |
| [03_recurrent_materialization_batch_inference](03_recurrent_materialization_batch_inference.ipynb) | Tutorial 3 | Recurrent materialization schedule; batch inference pipeline with offline features | Slides 11, 19 |
| [04_online_store_and_online_inference](04_online_store_and_online_inference.ipynb) | Tutorial 4 | Azure Managed Redis online store; online materialization; local online lookup; managed online endpoint | Slides 12, 20, 23 |

Network isolation (Tutorial 6) is covered by Slides 25–27 and the official
[network isolation notebook](https://github.com/Azure/azureml-examples/blob/65eceac7ff5cd2417af5f24d38192ab8e445dd85/sdk/python/featurestore_sample/notebooks/sdk_and_cli/network_isolation/Network-isolation-feature-store.ipynb).
The demo workspace uses public connectivity.

## Prerequisites

1. Repository `.venv` with [workshop/requirements.txt](../../requirements.txt), registered as the `mlops-azureml`
   Jupyter kernel:

   ```powershell
   .\.venv\Scripts\python.exe -m ipykernel install --user --name mlops-azureml --display-name "Python (MLOPs-AzureML)"
   ```

2. Local Spark on Windows: JDK 17 and Hadoop Windows binaries (`winutils.exe`, `hadoop.dll`). Set `JAVA_HOME` and
   `HADOOP_HOME` in `workshop/.env`; notebooks 01 and 02 add `%HADOOP_HOME%\bin` to `PATH`.
3. `az login` to the tenant. The notebooks use `AzureCliCredential(process_timeout=60)`.
4. `Owner`, or `Contributor` plus `User Access Administrator`, on the project workspace resource group. The notebooks
   assign data-plane roles described below.
5. Serverless Spark quota for ESv3 in the feature store region, FSv2 for the `cpu-cluster-fs` training cluster, and
   DSv2 for the online endpoint.

## Configuration

Set these values in `workshop/.env` (see [.env.example](../../.env.example)). The feature store uses the project
workspace subscription and resource group, as in the official sample.

| Key | Purpose |
|---|---|
| `AZURE_USER_OBJECT_ID` | Your Microsoft Entra object ID for role assignments |
| `AZUREML_FEATURE_STORE_NAME` / `AZUREML_FEATURE_STORE_LOCATION` | Feature store name and region |
| `FEATURE_STORE_SOURCE_STORAGE_ACCOUNT` / `FEATURE_STORE_SOURCE_FILESYSTEM` | ADLS Gen2 account and filesystem for sample source and observation data |
| `FEATURE_STORE_REDIS_NAME` | Globally unique Azure Managed Redis name for the online store |
| `FEATURE_STORE_ONLINE_ENDPOINT_NAME` | Region-unique managed online endpoint name |

The pipeline YAML files and checked-in feature set specs reference `abfss://spark@stpublicdlncus04.dfs.core.windows.net/feature-store-prp/`.
Change those paths if you use another ADLS Gen2 account.

## Changes from the official notebooks

| Change | Reason |
|---|---|
| A local setup cell replaces “start Spark session”: it loads `.env`, sets the `AZUREML_ARM_*` variables Azure ML studio provides, and starts local Spark | Run locally instead of in an Azure ML studio Serverless Spark session |
| `AzureCliCredential(process_timeout=60)` replaces `AzureMLOnBehalfOfCredential()` | `AzureMLOnBehalfOfCredential` works only inside Azure ML compute |
| `root_dir` points to [featurestore_sample/](featurestore_sample/); names come from `.env` | Local paths and configuration |
| Notebook 00 generates sample data, including recent activity for the sample accounts used by online lookup; source paths use our ADLS Gen2 account | The official data account now rejects anonymous reads ([azureml-examples#3738](https://github.com/Azure/azureml-examples/issues/3738)) |
| Local Spark reads a local copy of the data; specs are exported with the ADLS Gen2 path | Local Spark can't use your Entra identity to read ADLS Gen2. Registered feature sets read ADLS Gen2 on serverless Spark |
| Local training-data examples use feature set **specifications**; registered, materialized features are retrieved on serverless Spark by the pipelines | Same reason |
| Grant your identity **Storage Blob Data Contributor** on the feature store default storage | New feature stores use identity-based system datastores (`systemDatastoresAuthMode: identity`); registering a feature set uploads its spec |
| Grant the materialization identity **Storage Blob Data Reader** on the source ADLS Gen2 account | Required by [Manage access](https://learn.microsoft.com/azure/machine-learning/how-to-setup-access-control-feature-store?view=azureml-api-2) for private source data |
| Notebook 03 downloads batch predictions and reads them with pandas | Local equivalent of the official Spark read |
| Notebook 03 passes the schedule `start_time` as the string `"2023-04-15T00:04:10"`, the format in the official feature set YAML, and prints the saved schedule instead of the whole feature set | The service rejected the official `datetime` start time (`Invalid DateTime string ... should follow ISO8601 standard`). It returns the saved start time as `04/15/2023 00:04:10 +00:00`, which `print()` can't render as YAML |
| Notebook 04 sets the schedule start time back to that string before it updates `transactions`, and prints only the materialization flags | Updating a feature set with the returned start time fails with the same `InvalidSchedule` error |
| Notebook 04 backfills end at `datetime.now(timezone.utc)` minus three hours (`accounts`) or four hours (`transactions`) | The SDK treats the official naive `datetime.now()` as UTC. On a computer at UTC−4 the window ended seven hours ago, and online materialization keeps only rows within the feature set's lookback (one day for `transactions`). With the notebook 03 schedule, the service also requires a `transactions` backfill to end before now − 3 hours (interval) − 20 minutes (source delay): `FeatureWindowEndTime of the backfill request should be less than (current_time - schedule interval - source delay)` |
| Notebook 04 creates Azure Managed Redis (Balanced B0) instead of Azure Cache for Redis Premium P2; the official cell is shown as reference, and the endpoint's Redis role uses the `redisEnterprise` scope | Azure Cache for Redis creation is rejected: "Azure Cache for Redis is retiring, create Azure Managed Redis instance instead." The installed online lookup client accepts Azure Managed Redis database IDs |
| Feature stores are created and updated with `ComputeRuntime(spark_runtime_version="3.5")` | Materialization on the SDK default (3.4) failed; the service reports runtimes below 3.5 as unsupported. Updates without a runtime reset it to 3.4 |
| Training and batch pipelines run the feature retrieval component on Spark `3.5` and install `azureml-featurestore==1.2.2` | On 3.4 the component failed with `cannot import name 'get_arm_endpoints' from 'azure.mgmt.core.tools'`. On 3.5 its pinned `azureml-featurestore~=1.1.1` failed with `{'schema_version': ['Unknown field.']}` |
| Notebook 02 registers the credential-less `featurestore_adls` datastore, and the pipelines write the feature retrieval output there | The project workspace's default storage has blob soft delete; Spark's ADLS Gen2 driver rejects it with `This endpoint does not support BlobStorageEvents or SoftDelete` |
| `cpu-cluster-fs` uses the workspace compute identity (`AZUREML_COMPUTE_NAME`'s user-assigned identity), which gets **Storage Blob Data Reader** on the ADLS Gen2 account | The workspace container registry has no admin user, so a cluster without an identity can't pull the training image. Command steps read credential-less datastores with the compute identity |
| Grant the materialization identity **Reader** on the Azure Managed Redis cluster | Attaching the online store grants **Contributor** only on the database; materialization also reads the cluster and failed with `Microsoft.Cache/redisEnterprise/read` |
| Online inference environment pins `azureml-featurestore[online]==1.2.2` | Learn requires 1.2.1 or later for online lookup |
| The online deployment uses the `mcr.microsoft.com/azureml/openmpi4.1.0-ubuntu22.04` base image instead of `ubuntu20.04` | The container crashed importing `azureml.featurestore`: the current `azureml-dataprep-rslex` needs glibc 2.32 or later (`undefined symbol: __libc_single_threaded`), and Ubuntu 20.04 has 2.31. The Ubuntu 20.04 image hasn't been updated since February 2025 |
| Notebook 04 grants the endpoint identity **Storage Blob Data Reader** on the feature store default storage | The scoring script downloads feature set specifications from that storage, which new feature stores access with identity. Without the role, `init()` failed with `AuthorizationPermissionMismatch` |
| `SecurityControl: Ignore` tags on created resources | Matches the tag posture of this repository's other Azure resources |

## Azure resources created

All resources are in the project workspace resource group and region.

| Resource | Created by | Cost note |
|---|---|---|
| Feature store, its storage account, key vault, and materialization identity | 01 | Storage and key vault |
| Serverless Spark materialization and feature retrieval jobs | 01–04 | Billed per job; the recurrent schedule from 03 runs every three hours |
| `cpu-cluster-fs` (Standard_F4s_v2, 0–1 nodes) | 02 | Scales to zero after six minutes idle |
| `fraud_model` | 02 | — |
| Azure Managed Redis (Balanced B0) | 04 | Billed hourly until deleted |
| Managed online endpoint (Standard_DS3_v2) | 04 | Billed hourly until deleted |

## Cleanup

After the demo, stop recurring cost first:

1. Delete the online endpoint (`FEATURE_STORE_ONLINE_ENDPOINT_NAME`).
2. Disable the recurrent schedule: get the `transactions` feature set, set `materialization_settings.schedule = None`,
   and update it with `fs_client.feature_sets.begin_create_or_update()`. The update can return HTTP 500
   `CreateTriggerPollerTimeoutError` even though it applied; get the feature set again and confirm that `schedule` is `None`.
3. Delete Azure Managed Redis (`FEATURE_STORE_REDIS_NAME`).
4. Delete the feature store if it was created only for this demo, with its generated storage account, key vault,
   Application Insights, Log Analytics workspace, and `materialization-uai-*` identity. A failed create attempt can
   leave its own set of these `mlfs*` resources; compare with `az ml workspace show` before you delete them.
5. Remove `workshop/outputs/feature_store_sample_data/`, `workshop/outputs/feature_store_batch_inference/`, and the
   sample data under `feature-store-prp/` in the ADLS Gen2 account.

## Source and license

Notebook code and the [featurestore_sample/](featurestore_sample/) assets are adapted from
[Azure/azureml-examples](https://github.com/Azure/azureml-examples/tree/65eceac7ff5cd2417af5f24d38192ab8e445dd85/sdk/python/featurestore_sample)
at commit `65eceac` under the MIT license ([LICENSE](featurestore_sample/LICENSE)). Microsoft Learn content in the
talk track and documentation folder is licensed under CC BY 4.0.
