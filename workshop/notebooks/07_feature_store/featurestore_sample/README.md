# Official feature store sample assets

This folder contains the `featurestore/` and `project/` folders from the official
[Azure/azureml-examples `featurestore_sample`](https://github.com/Azure/azureml-examples/tree/65eceac7ff5cd2417af5f24d38192ab8e445dd85/sdk/python/featurestore_sample)
at commit `65eceac7ff5cd2417af5f24d38192ab8e445dd85`. That folder is identical to `main` at
`86d53a35d2ecc33ff40c669cc1389b06899e5a4b`. The sample is licensed under the MIT license in [LICENSE](LICENSE).

The notebooks in the parent folder set `root_dir` to this folder, exactly as the official notebooks
set it to the cloned `featurestore_sample` folder.

## Changes from the official files

| File | Change | Reason |
|---|---|---|
| `featurestore/featuresets/*/spec/FeatureSetSpec.yaml`, `project/fraud_model/pipelines/*.yaml` | `wasbs://data@azuremlexampledata.blob.core.windows.net/feature-store-prp/` → `abfss://spark@stpublicdlncus04.dfs.core.windows.net/feature-store-prp/` | The official sample data account now rejects anonymous reads (`PublicAccessNotPermitted`, [azureml-examples#3738](https://github.com/Azure/azureml-examples/issues/3738)). Notebook `00` writes data with the same schema to this ADLS Gen2 account. |
| `project/fraud_model/online_inference/conda.yml` | `azureml-featurestore[online]==1.1.0` → `1.2.2` | Microsoft Learn requires `azureml-featurestore` 1.2.1 or later for online feature lookup. |
| `project/fraud_model/pipelines/*.yaml` | Feature retrieval `runtime_version: "3.4"` → `"3.5"` | On Spark 3.4, the built-in feature retrieval component failed with an `azure.mgmt.core` import error; Spark 3.5 is the supported runtime. |
| `project/fraud_model/pipelines/*.yaml` | Feature retrieval step `conf` adds `spark.synapse.library.python.env` with `azureml-featurestore==1.2.2` | The component (version 1.1.1) installs `azureml-featurestore~=1.1.1`, which fails on current feature set metadata with `{'schema_version': ['Unknown field.']}`. |
| `project/fraud_model/pipelines/*.yaml` | Feature retrieval `output_data` is written to `azureml://datastores/featurestore_adls/paths/feature-store-prp/pipeline-outputs/${{name}}/output_data/` with `mode: direct` | The project workspace's default storage has blob soft delete, which Spark's ADLS Gen2 driver can't write to. Notebook 02 registers the datastore. |

The notebooks overwrite the two `FeatureSetSpec.yaml` files when they export the specifications. They also create
`project/fraud_model/feature_retrieval_spec/` and overwrite
`featurestore/featuresets/transactions/featureset_asset_offline_enabled.yaml` with values from your environment,
including your subscription ID. The repository ignores the retrieval spec folder and keeps the official asset YAML;
don't commit the regenerated asset YAML.
