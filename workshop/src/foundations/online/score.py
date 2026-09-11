import json
import os
from pathlib import Path

import pandas as pd


model = None


def init():
    global model
    model_root = Path(os.environ["AZUREML_MODEL_DIR"])
    matches = list(model_root.rglob("model.json"))
    if len(matches) != 1:
        raise RuntimeError(f"Expected one model.json, found {len(matches)}")
    model = json.loads(matches[0].read_text(encoding="utf-8"))


def run(raw_data):
    payload = json.loads(raw_data) if isinstance(raw_data, (str, bytes)) else raw_data
    input_data = payload.get("input_data", {})
    columns = input_data.get("columns")
    rows = input_data.get("data")
    if columns != model["features"]:
        raise ValueError(f"Expected columns in this order: {model['features']}")
    if not isinstance(rows, list) or not rows:
        raise ValueError("Request must contain at least one row")

    frame = pd.DataFrame(rows, columns=columns).apply(pd.to_numeric, errors="raise")
    predictions = model["intercept"]
    for feature, coefficient in zip(model["features"], model["coefficients"], strict=True):
        predictions = predictions + frame[feature] * coefficient
    return {"predictions": predictions.astype(float).tolist()}