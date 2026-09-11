# Sources and Attribution

The workshop adapts code from the sources below. Both external repositories use the MIT License. Copies of their notices are retained under `licenses/`.

## Source Mapping

| Workshop area | Source | Pinned revision | Adaptation |
| --- | --- | --- | --- |
| MLTable data registration | [AzureML-deep-dive-L200 dataset registration](https://github.com/jomedinagomez/AzureML-deep-dive-L200/blob/efa77413408a8053781096c41fb07cb882c8f518/taxi-fare-predictions/notebooks/dataset_registration.ipynb) | `efa77413408a8053781096c41fb07cb882c8f518` | Retain the short SDK-v2 teaching flow; use `python-dotenv`, remove hardcoded fallback identifiers, fix `mltable` naming, and verify the created asset. |
| Data assets | [Azure ML data example](https://github.com/Azure/azureml-examples/blob/b7e34d4ef1b790479795512785bce96ff7bf24c7/sdk/python/assets/data/data.ipynb) and [MLTable example](https://github.com/Azure/azureml-examples/blob/main/sdk/python/assets/data/working_with_mltable.ipynb) | `b7e34d4ef1b790479795512785bce96ff7bf24c7` for `data.ipynb` | Use explicit `Data`, `AssetTypes`, `create_or_update`, and `get` operations. |
| Environments | [Azure ML environment example](https://github.com/Azure/azureml-examples/blob/7dbe9a3ddfc4a920a9de82eaa4af7eaf118841d8/sdk/python/assets/environment/environment.ipynb) | `7dbe9a3ddfc4a920a9de82eaa4af7eaf118841d8` | Use a checked-in Conda file and an immutable name/version. |
| Models | [Azure ML model example](https://github.com/Azure/azureml-examples/blob/70f0ddd0cf92fb54af4031db0bb1dbd4a8443543/sdk/python/assets/model/model.ipynb) | `70f0ddd0cf92fb54af4031db0bb1dbd4a8443543` | Register a small checked-in model asset and retrieve it for verification. |
| Managed online endpoint | [Azure ML simple managed endpoint example](https://github.com/Azure/azureml-examples/blob/37c3572b3ceafdaaa90ee4503c920cfff899df1f/sdk/python/endpoints/online/managed/online-endpoints-simple-deployment.ipynb) | `37c3572b3ceafdaaa90ee4503c920cfff899df1f` | Use Microsoft Entra authentication, optional UMI, zero-traffic validation, and explicit promotion controls. |
| Taxi scripts and YAML | This repository's `src/`, `environment/`, and `pipelines/` | Workshop implementation commit | Copy only the files required by the single-step and registry-free integration flows; preserve the explicit `argparse` and mounted-file style. |
| Pipeline submission | This repository's `notebooks/00_submit_azureml_pipelines.ipynb` | Workshop implementation commit | Reuse `load_job`, compute override, submit, stream, and final-status verification. |
| H2O binary-model workflow | This repository's `notebooks/h2o_mojo/01-05` | Workshop implementation commit | Split operations into focused notebooks and extract generated scoring code into checked-in scripts. |

## Adaptation Rules

- Each adapted notebook starts with a visible source-attribution section.
- Azure identifiers and behavior switches come only from `workshop/.env`.
- No source notebook outputs, user paths, subscription IDs, generated AutoML artifacts, or credentials are copied.
- Azure ML Python SDK v2 patterns are used throughout.
- H2O material is described accurately as a version-specific binary-model workflow, not a portable MOJO workflow.