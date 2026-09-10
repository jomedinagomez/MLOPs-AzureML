import atexit
import hashlib
import json
import logging
import os
import threading
from pathlib import Path

import h2o
import pandas as pd
from azureml_inference_server_http.api.aml_response import AMLResponse

_model = None
_manifest = None
_predict_lock = threading.Lock()


def _sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _find_manifest(model_root):
    matches = list(model_root.rglob("model_manifest.json"))
    if len(matches) != 1:
        raise RuntimeError(f"Expected one model_manifest.json, found {len(matches)}")
    return matches[0]


def _predict(frame):
    h2o_frame = None
    prediction_frame = None
    try:
        h2o_frame = h2o.H2OFrame(frame)
        for column in _manifest.get("categorical_features", []):
            h2o_frame[column] = h2o_frame[column].asfactor()
        prediction_frame = _model.predict(h2o_frame)
        return prediction_frame.as_data_frame()["predict"].astype(float).tolist()
    finally:
        if prediction_frame is not None:
            h2o.remove(prediction_frame)
        if h2o_frame is not None:
            h2o.remove(h2o_frame)


def _parse_request(raw_data):
    payload = json.loads(raw_data) if isinstance(raw_data, (str, bytes)) else raw_data
    input_data = payload.get("input_data") if isinstance(payload, dict) else None
    if not isinstance(input_data, dict):
        raise ValueError("Request must contain an input_data object")

    columns = input_data.get("columns")
    rows = input_data.get("data")
    expected_columns = _manifest["features"]
    if columns != expected_columns:
        raise ValueError(f"Expected columns in this order: {expected_columns}")
    if not isinstance(rows, list) or not 1 <= len(rows) <= 100:
        raise ValueError("Request must contain between 1 and 100 rows")
    if any(not isinstance(row, list) or len(row) != len(columns) for row in rows):
        raise ValueError("Every row must have one value for each column")

    frame = pd.DataFrame(rows, columns=columns)
    for column in expected_columns:
        frame[column] = pd.to_numeric(frame[column], errors="raise")
    if frame.isna().any().any():
        raise ValueError("Null values are not accepted by this endpoint contract")
    return frame


def _shutdown_h2o():
    try:
        if h2o.connection() is not None:
            h2o.cluster().shutdown(prompt=False)
    except Exception:
        logging.exception("H2O shutdown failed")


def init():
    global _model, _manifest

    model_root = Path(os.environ["AZUREML_MODEL_DIR"]).resolve()
    manifest_path = _find_manifest(model_root)
    _manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    model_path = manifest_path.parent / _manifest["model_file"]

    if _manifest.get("model_format") != "h2o_binary":
        raise RuntimeError("The registered asset is not an H2O binary model")
    if h2o.__version__ != _manifest["h2o_version"]:
        raise RuntimeError(
            f"Expected h2o=={_manifest['h2o_version']}, found {h2o.__version__}"
        )
    if _sha256(model_path) != _manifest["files"][model_path.name]:
        raise RuntimeError("Binary model checksum does not match the manifest")

    h2o.no_progress()
    h2o.init(
        ip="127.0.0.1",
        port=54321,
        start_h2o=True,
        nthreads=int(os.environ.get("H2O_NTHREADS", "3")),
        max_mem_size=os.environ.get("H2O_MAX_MEM_SIZE", "6G"),
        strict_version_check=True,
        bind_to_localhost=True,
        verbose=False,
        telemetry=False,
    )
    _model = h2o.load_model(str(model_path))
    warmup = pd.read_csv(manifest_path.parent / "golden_input.csv").head(1)
    with _predict_lock:
        _predict(warmup)
    atexit.register(_shutdown_h2o)
    logging.info(
        "H2O model initialized: name=%s version=%s h2o=%s threads=%s heap=%s",
        _manifest["model_name"],
        _manifest["model_version"],
        _manifest["h2o_version"],
        os.environ.get("H2O_NTHREADS", "3"),
        os.environ.get("H2O_MAX_MEM_SIZE", "6G"),
    )


def run(raw_data):
    try:
        frame = _parse_request(raw_data)
    except (ValueError, TypeError, KeyError, json.JSONDecodeError) as exc:
        return AMLResponse({"error": str(exc)}, 400, json_str=True)

    with _predict_lock:
        predictions = _predict(frame)

    return {
        "predictions": predictions,
        "model_name": _manifest["model_name"],
        "model_version": _manifest["model_version"],
        "h2o_version": _manifest["h2o_version"],
    }
