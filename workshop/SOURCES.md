# Sources and Attribution

The workshop adapts code and one demo artifact from the sources below. The Azure ML code sources use the MIT License, and the H2O-3 MOJO uses Apache License 2.0. Copies of the applicable notices are retained under `licenses/`.

## Source Mapping

| Workshop area | Source | Pinned revision | Adaptation |
| --- | --- | --- | --- |
| MLTable data registration | [AzureML-deep-dive-L200 dataset registration](https://github.com/jomedinagomez/AzureML-deep-dive-L200/blob/efa77413408a8053781096c41fb07cb882c8f518/taxi-fare-predictions/notebooks/dataset_registration.ipynb) | `efa77413408a8053781096c41fb07cb882c8f518` | Retain the short SDK-v2 teaching flow; use `python-dotenv`, remove hardcoded fallback identifiers, fix `mltable` naming, and verify the created asset. |
| Data assets | [Azure ML data example](https://github.com/Azure/azureml-examples/blob/b7e34d4ef1b790479795512785bce96ff7bf24c7/sdk/python/assets/data/data.ipynb) and [MLTable example](https://github.com/Azure/azureml-examples/blob/main/sdk/python/assets/data/working_with_mltable.ipynb) | `b7e34d4ef1b790479795512785bce96ff7bf24c7` for `data.ipynb` | Use explicit `Data`, `AssetTypes`, `create_or_update`, and `get` operations. |
| Environments | [Azure ML environment example](https://github.com/Azure/azureml-examples/blob/7dbe9a3ddfc4a920a9de82eaa4af7eaf118841d8/sdk/python/assets/environment/environment.ipynb) | `7dbe9a3ddfc4a920a9de82eaa4af7eaf118841d8` | Generate reviewable Conda files in the owning notebooks and register immutable name/version pairs. |
| Models | [Azure ML model example](https://github.com/Azure/azureml-examples/blob/70f0ddd0cf92fb54af4031db0bb1dbd4a8443543/sdk/python/assets/model/model.ipynb) | `70f0ddd0cf92fb54af4031db0bb1dbd4a8443543` | Register a small checked-in model asset and retrieve it for verification. |
| Managed online endpoint | [Azure ML simple managed endpoint example](https://github.com/Azure/azureml-examples/blob/37c3572b3ceafdaaa90ee4503c920cfff899df1f/sdk/python/endpoints/online/managed/online-endpoints-simple-deployment.ipynb) | `37c3572b3ceafdaaa90ee4503c920cfff899df1f` | Use Microsoft Entra authentication, optional UMI, zero-traffic validation, and explicit promotion controls. |
| Taxi scripts and YAML | This repository's `src/`, `environment/`, and `pipelines/` | Workshop implementation commit | Copy only the files required by the single-step and registry-free integration flows; preserve the explicit `argparse` and mounted-file style. |
| Pipeline submission | This repository's `notebooks/00_submit_azureml_pipelines.ipynb` | Workshop implementation commit | Reuse `load_job`, compute override, submit, stream, and final-status verification. |
| H2O model workflow | This repository's `notebooks/h2o_mojo/01-05` | Workshop implementation commit | Split operations into focused notebooks and generate scoring code, environments, requests, components, and pipeline definitions inside the owning notebook. |
| Bundled customer H2O demo | [H2O-3 GBM MOJO test resource](https://github.com/h2oai/h2o-3/blob/ce08492c71e6f2fe9ce902cd82b1e7828ca3b1f6/h2o-genmodel/src/test/resources/hex/genmodel/algos/gbm/gbm_variable_importance.zip) | `ce08492c71e6f2fe9ce902cd82b1e7828ca3b1f6` | Use the Apache-2.0 prostate GBM MOJO as an independently published customer-style artifact; add synthetic golden rows and predictions validated with the declared target H2O runtime. |

## Adaptation Rules

- Each adapted notebook starts with a visible source-attribution section.
- Azure identifiers and behavior switches come only from `workshop/.env`.
- No source notebook outputs, user paths, subscription IDs, generated AutoML artifacts, or credentials are copied.
- Azure ML Python SDK v2 patterns are used throughout.
- H2O artifact formats are named explicitly: the reference flow uses a native binary, while the customer BYOM flow supports native binaries and MOJO ZIPs; the bundled customer demo is a MOJO.