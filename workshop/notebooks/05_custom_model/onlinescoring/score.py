"""Adapted from Azure/azureml-examples model-1 (MIT License).

Source: https://github.com/Azure/azureml-examples/blob/main/sdk/python/endpoints/online/model-1/onlinescoring/score.py
"""

import json
import os

import joblib
import pandas as pd


def init():
    global model
    model_path = os.path.join(os.environ["AZUREML_MODEL_DIR"], "customer_model.joblib")
    model = joblib.load(model_path)


def run(raw_data):
    request = json.loads(raw_data)
    input_data = pd.DataFrame(request["instances"])
    model_input = (
        input_data.loc[:, model.feature_names_in_]
        if hasattr(model, "feature_names_in_")
        else input_data.to_numpy()
    )
    predict = model.predict_proba if hasattr(model, "predict_proba") else model.predict
    return predict(model_input).tolist()