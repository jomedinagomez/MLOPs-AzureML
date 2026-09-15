# Joblib Managed Online Endpoint

This folder is a self-contained Azure Machine Learning managed online endpoint example for a trusted `.joblib` model.

## Source Attribution

The folder structure, scoring contract, sample request, and deployment flow are adapted from Microsoft's `model-1` example in `Azure/azureml-examples`, licensed under the MIT License:

- Example folder: <https://github.com/Azure/azureml-examples/tree/main/sdk/python/endpoints/online/model-1>
- Sample model: <https://github.com/Azure/azureml-examples/blob/main/sdk/python/endpoints/online/model-1/model/sklearn_regression_model.pkl>
- Scoring script: <https://github.com/Azure/azureml-examples/blob/main/sdk/python/endpoints/online/model-1/onlinescoring/score.py>
- Sample request: <https://github.com/Azure/azureml-examples/blob/main/sdk/python/endpoints/online/model-1/sample-request.json>
- Source license: <https://github.com/Azure/azureml-examples/blob/main/LICENSE>

The Conda definition is the environment contract supplied for this workshop.

## Folder Layout

```text
05_custom_model/
  01_deploy_joblib_model.ipynb
  README.md
  input.csv
  environment/
    conda.yaml
  model/
    customer_model.joblib
  onlinescoring/
    score.py
  sample-request.json
```

## Use a Customer Model

1. Replace `model/customer_model.joblib` with the customer's trusted joblib file, keeping the same filename.
2. Replace `input.csv` with data in the feature order expected by the customer model.
3. Edit the constants in Cell 2 of `01_deploy_joblib_model.ipynb`.
4. Run Cell 3 to load the model and score the CSV locally. It creates `sample-request.json` from the same rows.
5. Set `DEPLOY = True` and run Cell 4 to deploy and score those rows in Azure ML.

Joblib uses Python pickle serialization and can execute code while loading. Only load an artifact received through a trusted and verified channel. Scikit-learn also recommends matching the training and serving package versions; update `environment/conda.yaml` to the customer's training contract before deployment.