from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import time
from datetime import datetime, timezone
from pathlib import Path

import h2o
import mlflow
import numpy as np
import pandas as pd


def parse_bool(value: str) -> bool:
    normalized = str(value).strip().lower()
    if normalized in {"1", "true", "yes", "y"}:
        return True
    if normalized in {"0", "false", "no", "n"}:
        return False
    raise argparse.ArgumentTypeError(f"Expected a boolean value, received {value!r}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Score a CSV with an H2O binary model")
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--input-data", required=True)
    parser.add_argument("--scored-output", required=True)
    parser.add_argument("--monitoring-output", required=True)
    parser.add_argument("--correlation-id", required=True)
    parser.add_argument("--id-column", default="__generated__")
    parser.add_argument("--fail-on-rejects", type=parse_bool, default=False)
    parser.add_argument("--h2o-nthreads", type=int, default=4)
    parser.add_argument("--h2o-max-mem-size", default="6G")
    return parser.parse_args()


def emit(event: str, **fields: object) -> None:
    print(json.dumps({"event": event, **fields}, sort_keys=True, default=str), flush=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def find_one(root: Path, name: str) -> Path:
    matches = list(root.rglob(name))
    if len(matches) != 1:
        raise RuntimeError(f"Expected one {name} beneath {root}, found {len(matches)}")
    return matches[0]


def resolve_csv(path: Path) -> Path:
    if path.is_file():
        return path
    matches = sorted(path.rglob("*.csv"))
    if len(matches) != 1:
        raise RuntimeError(f"Expected one CSV beneath {path}, found {len(matches)}")
    return matches[0]


def safe_metric_name(value: str) -> str:
    return "".join(character if character.isalnum() else "_" for character in value).strip("_")


def prepare_input(
    input_path: Path,
    manifest: dict,
    id_column: str,
) -> tuple[pd.DataFrame, pd.Series, pd.DataFrame, dict[str, int], str]:
    source_path = resolve_csv(input_path)
    source = pd.read_csv(source_path)
    if source.empty:
        raise ValueError("Input CSV contains no rows")

    if "pickupHour" not in source.columns and "tpepPickupDateTime" in source.columns:
        pickup_time = pd.to_datetime(source["tpepPickupDateTime"], errors="coerce")
        source["pickupHour"] = pickup_time.dt.hour

    features = manifest["features"]
    missing = [column for column in features if column not in source.columns]
    if missing:
        raise ValueError(f"Missing required feature columns: {missing}")

    if id_column and id_column != "__generated__":
        if id_column not in source.columns:
            raise ValueError(f"Configured ID column is missing: {id_column}")
        if source[id_column].isna().any():
            raise ValueError(f"Configured ID column contains null values: {id_column}")
        row_ids = source[id_column].astype(str)
        if row_ids.duplicated().any():
            raise ValueError(f"Configured ID column contains duplicates: {id_column}")
    else:
        width = max(6, len(str(len(source))))
        row_ids = pd.Series(
            [f"{source_path.stem}:{index:0{width}d}" for index in range(len(source))],
            index=source.index,
            dtype="string",
        )

    numeric = pd.DataFrame(index=source.index)
    invalid_by_feature: dict[str, int] = {}
    for feature in features:
        numeric[feature] = pd.to_numeric(source[feature], errors="coerce")
        invalid_by_feature[feature] = int((~np.isfinite(numeric[feature])).sum())

    invalid_mask = ~np.isfinite(numeric.to_numpy(dtype=float)).all(axis=1)
    rejection_reasons = []
    for row_index in numeric.index[invalid_mask]:
        invalid_features = [
            feature for feature in features if not math.isfinite(float(numeric.at[row_index, feature]))
        ]
        rejection_reasons.append("invalid_or_null:" + ",".join(invalid_features))

    rejects = pd.DataFrame(
        {
            "row_id": row_ids.loc[invalid_mask].astype(str).to_numpy(),
            "source_file": source_path.name,
            "status": "rejected",
            "rejection_reason": rejection_reasons,
        }
    )
    valid_mask = ~invalid_mask
    return (
        numeric.loc[valid_mask, features].reset_index(drop=True),
        row_ids.loc[valid_mask].reset_index(drop=True),
        rejects,
        invalid_by_feature,
        source_path.name,
    )


def log_mlflow(summary: dict, manifest: dict, feature_statistics: pd.DataFrame, output_dir: Path) -> str:
    if not os.getenv("AZUREML_RUN_ID"):
        return "skipped_local"
    try:
        mlflow.log_params(
            {
                "model_name": manifest["model_name"],
                "model_version": manifest["model_version"],
                "model_format": manifest["model_format"],
                "h2o_version": manifest["h2o_version"],
                "model_sha256": summary["model_sha256"],
                "correlation_id": summary["correlation_id"],
            }
        )
        metrics = {
            "input_rows": summary["input_rows"],
            "scored_rows": summary["scored_rows"],
            "rejected_rows": summary["rejected_rows"],
            "reject_rate": summary["reject_rate"],
            "duration_seconds": summary["duration_seconds"],
            "jvm_startup_seconds": summary["jvm_startup_seconds"],
            "scoring_seconds": summary["scoring_seconds"],
            "rows_per_second": summary["rows_per_second"],
        }
        if summary["scored_rows"]:
            metrics.update(
                {
                    "prediction_mean": summary["prediction_mean"],
                    "prediction_std": summary["prediction_std"],
                    "prediction_min": summary["prediction_min"],
                    "prediction_max": summary["prediction_max"],
                }
            )
        for _, row in feature_statistics.iterrows():
            prefix = "feature_" + safe_metric_name(str(row["feature"]))
            for statistic in ("mean", "std", "min", "max", "invalid_count"):
                value = row.get(statistic)
                if pd.notna(value):
                    metrics[f"{prefix}_{statistic}"] = float(value)
        mlflow.log_metrics(metrics)
        mlflow.set_tags(
            {
                "pipeline_stage": "h2o_batch_scoring",
                "model_format": "h2o_binary",
                "aml_run_id": summary["aml_run_id"],
                "source_file": summary["source_file"],
                "quality_gate": summary["quality_gate"],
            }
        )
        mlflow.log_artifact(str(output_dir / "feature_statistics.csv"), "monitoring")
        mlflow.log_artifact(str(output_dir / "run_manifest.json"), "monitoring")
        return "logged"
    except Exception as exc:
        emit("mlflow_logging_failed", error_type=type(exc).__name__)
        return "failed"


def main() -> None:
    args = parse_args()
    started = time.perf_counter()
    scoring_time = datetime.now(timezone.utc).isoformat()
    aml_run_id = os.getenv("AZUREML_RUN_ID", "local")
    correlation_id = args.correlation_id or aml_run_id
    scored_output = Path(args.scored_output)
    monitoring_output = Path(args.monitoring_output)
    scored_output.mkdir(parents=True, exist_ok=True)
    monitoring_output.mkdir(parents=True, exist_ok=True)

    model_root = Path(args.model_dir).resolve()
    manifest_path = find_one(model_root, "model_manifest.json")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    model_path = manifest_path.parent / manifest["model_file"]
    if manifest.get("model_format") != "h2o_binary":
        raise RuntimeError("Registered model is not an H2O binary model")
    if h2o.__version__ != manifest["h2o_version"]:
        raise RuntimeError(f"Expected h2o=={manifest['h2o_version']}, found {h2o.__version__}")
    model_sha = sha256(model_path)
    if model_sha != manifest["files"].get(model_path.name):
        raise RuntimeError("Binary model checksum does not match the manifest")

    valid_features, valid_ids, rejects, invalid_counts, source_file = prepare_input(
        Path(args.input_data), manifest, args.id_column
    )
    input_rows = len(valid_features) + len(rejects)
    emit(
        "batch_scoring_started",
        aml_run_id=aml_run_id,
        correlation_id=correlation_id,
        input_rows=input_rows,
        valid_rows=len(valid_features),
        rejected_rows=len(rejects),
        model_name=manifest["model_name"],
        model_version=manifest["model_version"],
    )

    predictions = np.asarray([], dtype=float)
    jvm_startup_seconds = 0.0
    scoring_seconds = 0.0
    try:
        if len(valid_features):
            h2o.no_progress()
            jvm_started = time.perf_counter()
            h2o.init(
                ip="127.0.0.1",
                port=54321,
                start_h2o=True,
                nthreads=args.h2o_nthreads,
                max_mem_size=args.h2o_max_mem_size,
                strict_version_check=True,
                bind_to_localhost=True,
                verbose=False,
                telemetry=False,
            )
            model = h2o.load_model(str(model_path))
            jvm_startup_seconds = time.perf_counter() - jvm_started
            scoring_started = time.perf_counter()
            h2o_frame = h2o.H2OFrame(valid_features)
            for column in manifest.get("categorical_features", []):
                h2o_frame[column] = h2o_frame[column].asfactor()
            prediction_frame = model.predict(h2o_frame)
            predictions = prediction_frame.as_data_frame()["predict"].to_numpy(dtype=float)
            scoring_seconds = time.perf_counter() - scoring_started
            h2o.remove(prediction_frame)
            h2o.remove(h2o_frame)
    finally:
        try:
            if h2o.connection() is not None:
                h2o.cluster().shutdown(prompt=False)
        except Exception as exc:
            emit("h2o_shutdown_failed", error_type=type(exc).__name__)

    predictions_frame = pd.DataFrame(
        {
            "row_id": valid_ids.astype(str),
            "prediction": predictions,
            "model_name": manifest["model_name"],
            "model_version": manifest["model_version"],
            "model_sha256": model_sha,
            "h2o_version": manifest["h2o_version"],
            "aml_run_id": aml_run_id,
            "source_file": source_file,
            "scoring_time_utc": scoring_time,
            "correlation_id": correlation_id,
            "status": "scored",
        }
    )
    if len(predictions_frame) != len(valid_features):
        raise RuntimeError("Prediction count does not match valid input row count")

    monitoring_frame = valid_features.copy()
    monitoring_frame.insert(0, "row_id", valid_ids.astype(str))
    monitoring_frame["prediction"] = predictions
    monitoring_frame["model_name"] = manifest["model_name"]
    monitoring_frame["model_version"] = manifest["model_version"]
    monitoring_frame["scoring_time_utc"] = scoring_time
    monitoring_frame["correlation_id"] = correlation_id

    statistics = valid_features.describe().T.reset_index(names="feature") if len(valid_features) else pd.DataFrame({"feature": manifest["features"]})
    statistics["invalid_count"] = statistics["feature"].map(invalid_counts).fillna(0).astype(int)

    predictions_frame.to_csv(scored_output / "predictions.csv", index=False)
    rejects.to_csv(scored_output / "rejects.csv", index=False)
    monitoring_frame.to_csv(monitoring_output / "monitoring_data.csv", index=False)
    statistics.to_csv(monitoring_output / "feature_statistics.csv", index=False)

    duration_seconds = time.perf_counter() - started
    summary = {
        "aml_run_id": aml_run_id,
        "correlation_id": correlation_id,
        "source_file": source_file,
        "model_name": manifest["model_name"],
        "model_version": manifest["model_version"],
        "model_sha256": model_sha,
        "h2o_version": manifest["h2o_version"],
        "input_rows": input_rows,
        "scored_rows": len(predictions_frame),
        "rejected_rows": len(rejects),
        "reject_rate": len(rejects) / input_rows,
        "duration_seconds": duration_seconds,
        "jvm_startup_seconds": jvm_startup_seconds,
        "scoring_seconds": scoring_seconds,
        "rows_per_second": len(predictions_frame) / duration_seconds if duration_seconds else 0.0,
        "prediction_mean": float(predictions.mean()) if len(predictions) else None,
        "prediction_std": float(predictions.std()) if len(predictions) else None,
        "prediction_min": float(predictions.min()) if len(predictions) else None,
        "prediction_max": float(predictions.max()) if len(predictions) else None,
        "quality_gate": "passed" if len(predictions_frame) + len(rejects) == input_rows else "failed",
        "mlflow_status": "pending",
    }
    run_manifest = {
        "schema_version": "1.0",
        "created_utc": scoring_time,
        "input": {"source_file": source_file, "rows": input_rows},
        "model": {
            "name": manifest["model_name"],
            "version": manifest["model_version"],
            "format": manifest["model_format"],
            "sha256": model_sha,
            "h2o_version": manifest["h2o_version"],
        },
        "execution": {
            "aml_run_id": aml_run_id,
            "correlation_id": correlation_id,
            "fail_on_rejects": args.fail_on_rejects,
        },
        "outputs": {
            "predictions": "predictions.csv",
            "rejects": "rejects.csv",
            "monitoring_data": "monitoring_data.csv",
            "feature_statistics": "feature_statistics.csv",
        },
    }
    (monitoring_output / "run_manifest.json").write_text(
        json.dumps(run_manifest, indent=2) + "\n", encoding="utf-8"
    )
    summary["mlflow_status"] = log_mlflow(summary, manifest, statistics, monitoring_output)
    (monitoring_output / "summary.json").write_text(
        json.dumps(summary, indent=2) + "\n", encoding="utf-8"
    )
    if os.getenv("AZUREML_RUN_ID") and summary["mlflow_status"] == "logged":
        mlflow.log_artifact(str(monitoring_output / "summary.json"), "monitoring")

    emit(
        "batch_scoring_completed",
        aml_run_id=aml_run_id,
        correlation_id=correlation_id,
        input_rows=input_rows,
        scored_rows=len(predictions_frame),
        rejected_rows=len(rejects),
        duration_seconds=round(duration_seconds, 6),
        rows_per_second=round(summary["rows_per_second"], 6),
        quality_gate=summary["quality_gate"],
        mlflow_status=summary["mlflow_status"],
    )
    if args.fail_on_rejects and len(rejects):
        raise RuntimeError(f"Rejected {len(rejects)} rows and fail_on_rejects is enabled")


if __name__ == "__main__":
    main()
