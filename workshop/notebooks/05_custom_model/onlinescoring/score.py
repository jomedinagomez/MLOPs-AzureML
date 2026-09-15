"""Adapted from Azure/azureml-examples model-1 (MIT License).

Source: https://github.com/Azure/azureml-examples/blob/main/sdk/python/endpoints/online/model-1/onlinescoring/score.py
"""

import json
import os

import joblib
import numpy


def init():
    global model
    model_path = os.path.join(
        os.environ["AZUREML_MODEL_DIR"], "customer_model.joblib"
    )
    model = joblib.load(model_path)


def run(raw_data):
    data = numpy.array(json.loads(raw_data)["data"])
    return model.predict(data).tolist()