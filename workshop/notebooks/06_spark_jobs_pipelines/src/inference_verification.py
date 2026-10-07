"""Runtime and prediction checks for serverless Spark inference."""

from __future__ import annotations

from collections.abc import Mapping
import json
from pathlib import Path, PurePosixPath
import re
from typing import Any
from urllib.parse import urlparse

from azure.core.credentials import TokenCredential
from azure.storage.filedatalake import DataLakeServiceClient
import pandas as pd


def assert_native_spark_job(job: Any) -> None:
    properties = job.properties or {}
    target_type = properties.get("_azureml.ComputeTargetType")
    compute = job.compute
    resources = getattr(job, "resources", None)
    standalone_serverless = (
        compute is None
        and getattr(job, "type", None) == "spark"
        and bool(getattr(resources, "instance_type", None))
    )
    if target_type != "amlspark" or (
        str(compute).lower() != "serverless" and not standalone_serverless
    ):
        raise RuntimeError(
            f"Expected managed serverless Spark: compute={compute}, "
            f"ComputeTargetType={target_type}"
        )


def validate_runtime_manifest(
    manifest: Mapping[str, Any],
    model_asset_id: str,
    expected_rows: int,
    registered_artifact_uri: str,
) -> None:
    if str(manifest.get("spark_version", "")).split(".")[:2] != ["3", "5"]:
        raise RuntimeError(f"Expected Spark 3.5 runtime: {manifest}")
    master = str(manifest.get("spark_master", ""))
    if not master or master.lower().startswith("local"):
        raise RuntimeError(f"Expected managed Spark master, found {master!r}")
    if manifest.get("model_asset_id") != model_asset_id:
        raise RuntimeError("Inference did not use the expected registered model")
    if manifest.get("registered_artifact_uri") != registered_artifact_uri:
        raise RuntimeError("Inference did not originate from the registered artifact URI")
    if not re.fullmatch(r"[0-9a-f]{64}", str(manifest.get("model_content_sha256", ""))):
        raise RuntimeError("Inference has no valid registered-model content checksum")
    if expected_rows <= 0 or (
        manifest.get("input_rows") != expected_rows
        or manifest.get("output_rows") != expected_rows
    ):
        raise RuntimeError(f"Runtime manifest row counts do not match: {manifest}")


def validate_predictions(
    predictions: pd.DataFrame,
    expected_passenger_ids: set[int],
) -> None:
    required = {"PassengerId", "prediction", "survival_probability"}
    missing = sorted(required.difference(predictions.columns))
    if missing:
        raise RuntimeError(f"Predictions are missing columns: {missing}")
    ids = pd.to_numeric(predictions["PassengerId"], errors="raise")
    if (
        not expected_passenger_ids
        or len(predictions) != len(expected_passenger_ids)
        or ids.isna().any()
        or not ids.mod(1).eq(0).all()
        or ids.duplicated().any()
        or set(ids) != expected_passenger_ids
    ):
        raise RuntimeError("Prediction PassengerIds do not exactly match the input")
    classes = pd.to_numeric(predictions["prediction"], errors="raise")
    if not classes.isin([0, 1]).all():
        raise RuntimeError("Predictions must be integer classes 0 or 1")
    probabilities = pd.to_numeric(predictions["survival_probability"], errors="raise")
    if not probabilities.between(0.0, 1.0).all():
        raise RuntimeError("Survival probabilities must be finite values in [0, 1]")


def assert_prediction_parity(
    predictions: pd.DataFrame,
    reference: pd.DataFrame,
    tolerance: float = 1e-9,
) -> None:
    for frame in (predictions, reference):
        if frame["PassengerId"].duplicated().any():
            raise RuntimeError("Parity comparison requires unique PassengerIds")
    if set(predictions["PassengerId"]) != set(reference["PassengerId"]):
        raise RuntimeError("Reference and native prediction PassengerIds differ")
    actual = predictions.set_index("PassengerId").sort_index()
    expected = reference.set_index("PassengerId").sort_index()
    if not actual["prediction"].eq(expected["prediction"]).all():
        raise RuntimeError("Native Spark prediction classes differ from the reference")
    difference = (actual["survival_probability"] - expected["survival_probability"]).abs()
    if not difference.le(tolerance).all():
        raise RuntimeError(
            f"Native Spark probabilities differ from the reference: "
            f"maximum absolute difference={difference.max()}"
        )


def download_predictions(
    uri: str,
    destination: Path,
    credential: TokenCredential,
) -> None:
    parsed = urlparse(uri)
    if parsed.scheme != "abfss" or "@" not in parsed.netloc:
        raise ValueError(f"Expected a direct ADLS output URI, found {uri}")
    filesystem, host = parsed.netloc.split("@", 1)
    prefix = parsed.path.strip("/")
    if not prefix or ".." in PurePosixPath(prefix).parts:
        raise ValueError("Predictions must be in a specific ADLS output directory")
    downloaded = 0
    with DataLakeServiceClient(account_url=f"https://{host}", credential=credential) as service:
        filesystem_client = service.get_file_system_client(filesystem)
        for remote in filesystem_client.get_paths(path=prefix, recursive=True):
            if remote.is_directory:
                continue
            relative = PurePosixPath(remote.name).relative_to(prefix)
            if ".." in relative.parts:
                raise ValueError(f"Invalid remote output path: {remote.name}")
            local = destination.joinpath(*relative.parts)
            local.parent.mkdir(parents=True, exist_ok=True)
            local.write_bytes(filesystem_client.get_file_client(remote.name).download_file().readall())
            downloaded += 1
    if not downloaded:
        raise FileNotFoundError(f"No predictions or runtime evidence found at {uri}")


def load_verified_predictions(
    directory: Path,
    expected_passenger_ids: set[int],
    model_asset_id: str,
    registered_artifact_uri: str,
) -> tuple[pd.DataFrame, dict[str, Any]]:
    csv_files = sorted((directory / "csv").glob("part-*.csv"))
    runtime_files = sorted((directory / "runtime").glob("part-*.json"))
    if not csv_files or len(runtime_files) != 1:
        raise FileNotFoundError("Inference must produce CSV predictions and one runtime manifest")
    predictions = pd.concat([pd.read_csv(path) for path in csv_files], ignore_index=True)
    manifest = json.loads(runtime_files[0].read_text(encoding="utf-8"))
    if not isinstance(manifest, dict):
        raise ValueError("The runtime manifest must be a JSON object")
    validate_predictions(predictions, expected_passenger_ids)
    validate_runtime_manifest(
        manifest, model_asset_id, len(expected_passenger_ids), registered_artifact_uri
    )
    return predictions, manifest
