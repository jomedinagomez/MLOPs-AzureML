# Model Artifact

Replace `customer_model.joblib` with the trusted customer artifact, keeping the same filename.

The included demonstration artifact is copied without modification from Microsoft's `Azure/azureml-examples` repository:

- Source: <https://github.com/Azure/azureml-examples/blob/main/sdk/python/endpoints/online/model-1/model/sklearn_regression_model.pkl>
- Example: <https://github.com/Azure/azureml-examples/tree/main/sdk/python/endpoints/online/model-1>
- License: <https://github.com/Azure/azureml-examples/blob/main/LICENSE> (MIT)

Joblib uses Python pickle serialization and can execute code while loading. Only use an artifact received through a trusted and verified channel. Match the serving package versions in `../environment/conda.yaml` to the customer's training environment.