from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from pathlib import Path

import pandas as pd


SUPPORTED_MODEL_FORMATS = {"h2o_binary", "h2o_mojo"}
REQUIRED_MANIFEST_FIELDS = {
    "model_name",
    "model_version",
    "model_format",
    "h2o_version",
    "model_file",
    "features",
    "categorical_features",
    "files",
}


def detect_model_format(model_path: Path) -> str:
    model_path = Path(model_path).resolve()
    if not model_path.is_file():
        raise FileNotFoundError(f"Model artifact not found: {model_path}")
    if not zipfile.is_zipfile(model_path):
        return "h2o_binary"
    with zipfile.ZipFile(model_path) as archive:
        return "h2o_mojo" if "model.ini" in archive.namelist() else "h2o_binary"


def read_mojo_metadata(model_path: Path) -> dict:
    model_path = Path(model_path).resolve()
    if not zipfile.is_zipfile(model_path):
        raise ValueError(f"MOJO artifact is not a ZIP file: {model_path}")

    with zipfile.ZipFile(model_path) as archive:
        try:
            model_ini = archive.read("model.ini").decode("utf-8")
        except KeyError as exc:
            raise ValueError(f"MOJO artifact has no model.ini: {model_path}") from exc

    section = ""
    info: dict[str, str] = {}
    columns: list[str] = []
    for raw_line in model_ini.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            continue
        if section == "info" and "=" in line:
            key, value = line.split("=", 1)
            info[key.strip()] = value.strip()
        elif section == "columns":
            columns.append(line)

    required_info = {"h2o_version", "mojo_version", "category", "n_features"}
    missing_info = sorted(required_info - info.keys())
    if missing_info:
        raise ValueError(f"MOJO model.ini fields missing: {missing_info}")

    try:
        n_features = int(info["n_features"])
    except ValueError as exc:
        raise ValueError("MOJO n_features must be an integer") from exc
    if len(columns) != n_features + 1:
        raise ValueError(
            "MOJO columns must contain every feature followed by the response column"
        )

    return {
        "h2o_version": info["h2o_version"],
        "mojo_version": info["mojo_version"],
        "category": info["category"],
        "n_features": n_features,
        "features": columns[:-1],
        "target": columns[-1],
    }


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_bundle(
    bundle_dir: Path,
    expected_h2o_version: str | None = None,
    require_packaging_validation: bool = False,
    require_golden_validation: bool = False,
) -> dict:
    bundle_dir = Path(bundle_dir).resolve()
    manifest_path = bundle_dir / "model_manifest.json"
    if not manifest_path.is_file():
        raise FileNotFoundError(f"Manifest not found: {manifest_path}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    missing_fields = sorted(REQUIRED_MANIFEST_FIELDS - manifest.keys())
    if missing_fields:
        raise ValueError(f"Manifest fields missing: {missing_fields}")
    model_format = manifest["model_format"]
    if model_format not in SUPPORTED_MODEL_FORMATS:
        raise ValueError(
            f"Unsupported H2O model format: {model_format}; "
            f"expected one of {sorted(SUPPORTED_MODEL_FORMATS)}"
        )
    if str(manifest["model_version"]).lower() == "latest":
        raise ValueError("Use an immutable model version, not 'latest'")
    runtime_h2o_version = manifest.get(
        "runtime_h2o_version",
        manifest["h2o_version"],
    )
    if expected_h2o_version and runtime_h2o_version != expected_h2o_version:
        raise ValueError(
            f"Expected runtime h2o=={expected_h2o_version}; "
            f"bundle requires {runtime_h2o_version}"
        )

    features = manifest["features"]
    categorical_features = manifest["categorical_features"]
    if not isinstance(features, list) or not features or len(features) != len(set(features)):
        raise ValueError("Manifest features must be a non-empty list without duplicates")
    if not set(categorical_features).issubset(features):
        raise ValueError("Every categorical feature must also appear in features")

    model_path = bundle_dir / manifest["model_file"]
    detected_model_format = detect_model_format(model_path)
    if detected_model_format != model_format:
        raise ValueError(
            f"Manifest model_format is {model_format}, but the artifact is "
            f"{detected_model_format}"
        )

    golden_data = manifest.get("golden_data")
    if golden_data is None:
        legacy_golden_files = {"golden_input.csv", "golden_expected.csv"}
        golden_provided = legacy_golden_files.issubset(manifest["files"])
        golden_validate = golden_provided
        golden_input_name = "golden_input.csv" if golden_provided else None
        golden_expected_name = "golden_expected.csv" if golden_provided else None
        golden_required = False
    else:
        if not isinstance(golden_data, dict):
            raise ValueError("golden_data must be an object")
        golden_provided = golden_data.get("provided")
        golden_validate = golden_data.get("validate", golden_provided)
        golden_required = golden_data.get("required", False)
        if (
            not isinstance(golden_provided, bool)
            or not isinstance(golden_validate, bool)
            or not isinstance(golden_required, bool)
        ):
            raise ValueError(
                "golden_data provided, validate, and required must be booleans"
            )
        golden_input_name = golden_data.get("input_file")
        golden_expected_name = golden_data.get("expected_file")
        if golden_provided and not golden_input_name:
            raise ValueError("golden_data.input_file is required when golden data is provided")
        if golden_provided and not golden_expected_name:
            raise ValueError(
                "golden_data.expected_file is required when golden data is provided"
            )
        if not golden_provided and (golden_input_name or golden_expected_name):
            raise ValueError("Golden filenames must be omitted when golden data is not provided")
        if golden_required and not golden_provided:
            raise ValueError("Golden validation is required but golden data is not provided")
        if golden_validate and not golden_provided:
            raise ValueError("Golden validation is enabled but golden data is not provided")
        if golden_required and not golden_validate:
            raise ValueError("Required golden validation cannot be disabled")

    required_files = {manifest["model_file"]}
    if golden_provided:
        required_files.update({golden_input_name, golden_expected_name})
    if not required_files.issubset(manifest["files"]):
        missing = sorted(required_files - manifest["files"].keys())
        raise ValueError(f"Manifest checksums missing: {missing}")

    for name, expected_hash in manifest["files"].items():
        path = bundle_dir / name
        if not path.is_file():
            raise FileNotFoundError(f"Bundle file not found: {path}")
        if sha256(path) != expected_hash:
            raise ValueError(f"Checksum mismatch: {name}")

    mojo_metadata = None
    if model_format == "h2o_mojo":
        mojo_fields = {
            "mojo_version",
            "runtime_h2o_version",
            "h2o_pip_spec",
            "python_version",
            "java_version",
            "target",
        }
        missing_mojo_fields = sorted(mojo_fields - manifest.keys())
        if missing_mojo_fields:
            raise ValueError(f"MOJO manifest fields missing: {missing_mojo_fields}")

        mojo_metadata = read_mojo_metadata(model_path)
        if mojo_metadata["h2o_version"] != manifest["h2o_version"]:
            raise ValueError("Manifest H2O producer version does not match model.ini")
        if mojo_metadata["mojo_version"] != manifest["mojo_version"]:
            raise ValueError("Manifest MOJO version does not match model.ini")
        if mojo_metadata["features"] != features:
            raise ValueError(
                f"Manifest features must match MOJO columns: {mojo_metadata['features']}"
            )
        if manifest.get("target") != mojo_metadata["target"]:
            raise ValueError(
                f"Manifest target must match the MOJO response: {mojo_metadata['target']}"
            )
    elif runtime_h2o_version != manifest["h2o_version"]:
        raise ValueError(
            "Native H2O binaries require runtime_h2o_version to match h2o_version"
        )

    golden_rows = 0
    if golden_provided:
        golden_input = pd.read_csv(bundle_dir / golden_input_name)
        golden_expected = pd.read_csv(bundle_dir / golden_expected_name)
        if list(golden_input.columns) != features:
            raise ValueError(f"Golden input columns must be ordered as: {features}")
        if list(golden_expected.columns) != ["predict"]:
            raise ValueError("Golden expected output must contain only the 'predict' column")
        if golden_input.empty or len(golden_input) != len(golden_expected):
            raise ValueError(
                "Golden input and expected output must contain the same non-zero row count"
            )
        golden_rows = len(golden_input)

    packaging = manifest.get("packaging", {})
    if require_packaging_validation and packaging.get("status") != "passed":
        raise ValueError("Bundle does not contain passed packaging validation")

    validation = manifest.get("validation", {})
    if require_golden_validation:
        if not golden_provided:
            raise ValueError("Golden validation is required but golden data is not provided")
        if not golden_validate:
            raise ValueError("Golden validation is required but disabled")
        if validation.get("status") != "passed":
            raise ValueError("Bundle does not contain passed golden-validation evidence")
        validation_h2o_version = validation.get(
            "runtime_h2o_version",
            validation.get("h2o_version"),
        )
        if validation_h2o_version != runtime_h2o_version:
            raise ValueError("Golden validation used a different H2O runtime version")
        if validation.get("golden_rows") != golden_rows:
            raise ValueError("Golden-validation row count does not match the bundle")

    return {
        "bundle_dir": str(bundle_dir),
        "model_name": manifest["model_name"],
        "model_version": str(manifest["model_version"]),
        "model_format": model_format,
        "h2o_version": manifest["h2o_version"],
        "runtime_h2o_version": runtime_h2o_version,
        "mojo_version": manifest.get("mojo_version"),
        "model_category": mojo_metadata["category"] if mojo_metadata else None,
        "model_file": manifest["model_file"],
        "features": features,
        "golden_provided": golden_provided,
        "golden_validation_enabled": golden_validate,
        "golden_required": golden_required,
        "golden_input_file": golden_input_name,
        "golden_expected_file": golden_expected_name,
        "golden_rows": golden_rows,
        "checksums": "passed",
        "packaging_validation": packaging.get("status", "not_recorded"),
        "golden_validation": validation.get("status", "not_recorded"),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate an H2O model bundle")
    parser.add_argument("--bundle-dir", required=True)
    parser.add_argument("--expected-h2o-version")
    parser.add_argument("--require-packaging-validation", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    result = validate_bundle(
        Path(args.bundle_dir),
        args.expected_h2o_version,
        require_packaging_validation=args.require_packaging_validation,
    )
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()