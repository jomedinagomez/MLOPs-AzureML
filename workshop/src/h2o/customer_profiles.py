from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path
from typing import Any

import pandas as pd

from validate_bundle import detect_model_format, read_mojo_metadata, validate_bundle


PROFILE_FORMATS = {
    "binary": "h2o_binary",
    "mojo": "h2o_mojo",
}
PROFILE_FILE = "profile.json"
GOLDEN_INPUT_FILE = "golden_input.csv"
GOLDEN_EXPECTED_FILE = "golden_expected.csv"
SELECTED_BUNDLE_PATH = Path("outputs/h2o_customer_bundle")
IGNORED_PROFILE_FILES = {
    PROFILE_FILE,
    GOLDEN_INPUT_FILE,
    GOLDEN_EXPECTED_FILE,
    "model_manifest.json",
    "README.md",
}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _required_string(config: dict[str, Any], name: str) -> str:
    value = str(config.get(name, "")).strip()
    if not value:
        raise ValueError(f"Profile setting {name!r} is required")
    return value


def _string_list(
    config: dict[str, Any], name: str, *, required: bool = False
) -> list[str]:
    value = config.get(name, [])
    if not isinstance(value, list) or any(
        not isinstance(item, str) or not item.strip() for item in value
    ):
        raise ValueError(f"Profile setting {name!r} must be a list of strings")
    result = [item.strip() for item in value]
    if required and not result:
        raise ValueError(f"Profile setting {name!r} must not be empty")
    if len(result) != len(set(result)):
        raise ValueError(f"Profile setting {name!r} contains duplicates")
    return result


def selected_bundle_dir(workshop_root: Path) -> Path:
    return Path(workshop_root).resolve() / SELECTED_BUNDLE_PATH


def load_selected_manifest(workshop_root: Path) -> tuple[Path, dict[str, Any]]:
    bundle_dir = selected_bundle_dir(workshop_root)
    manifest_path = bundle_dir / "model_manifest.json"
    if not manifest_path.is_file():
        raise FileNotFoundError(
            "No staged customer bundle was found. Run "
            "01_package_and_validate_model.ipynb first."
        )
    return bundle_dir, json.loads(manifest_path.read_text(encoding="utf-8"))


def prepare_customer_bundle(
    workshop_root: Path,
    profile_name: str,
    *,
    run_golden_validation: bool = True,
    require_golden_validation: bool = False,
    output_dir: Path | None = None,
) -> dict[str, Any]:
    workshop_root = Path(workshop_root).resolve()
    selected_profile = str(profile_name).strip().lower()
    if selected_profile not in PROFILE_FORMATS:
        raise ValueError(
            f"CUSTOMER_MODEL_PROFILE must be one of {sorted(PROFILE_FORMATS)}"
        )

    profile_dir = (
        workshop_root
        / "data/h2o/customer_bundle/profiles"
        / selected_profile
    )
    profile_path = profile_dir / PROFILE_FILE
    if not profile_path.is_file():
        raise FileNotFoundError(f"Profile configuration not found: {profile_path}")
    config = json.loads(profile_path.read_text(encoding="utf-8"))

    model_candidates = sorted(
        path
        for path in profile_dir.iterdir()
        if path.is_file()
        and not path.name.startswith(".")
        and path.name not in IGNORED_PROFILE_FILES
    )
    if len(model_candidates) != 1:
        raise ValueError(
            f"Profile {selected_profile!r} must contain exactly one model "
            f"artifact; found {[path.name for path in model_candidates]}"
        )
    source_model_path = model_candidates[0]

    model_format = detect_model_format(source_model_path)
    expected_format = PROFILE_FORMATS[selected_profile]
    if model_format != expected_format:
        raise ValueError(
            f"Profile {selected_profile!r} requires {expected_format}, but "
            f"{source_model_path.name!r} was detected as {model_format}"
        )

    source_golden_input = profile_dir / GOLDEN_INPUT_FILE
    source_golden_expected = profile_dir / GOLDEN_EXPECTED_FILE
    if source_golden_input.is_file() != source_golden_expected.is_file():
        raise ValueError(
            f"Profile {selected_profile!r} must contain both "
            f"{GOLDEN_INPUT_FILE} and {GOLDEN_EXPECTED_FILE}, or neither"
        )
    golden_provided = source_golden_input.is_file()
    if require_golden_validation and not golden_provided:
        raise ValueError("Golden validation is required, but no golden pair exists")
    golden_validation_enabled = golden_provided and run_golden_validation
    if require_golden_validation and not golden_validation_enabled:
        raise ValueError("Required golden validation cannot be disabled")

    mojo_metadata = (
        read_mojo_metadata(source_model_path)
        if model_format == "h2o_mojo"
        else None
    )
    if mojo_metadata:
        model_h2o_version = mojo_metadata["h2o_version"]
        mojo_version = mojo_metadata["mojo_version"]
        features = mojo_metadata["features"]
        target = mojo_metadata["target"]
        configured_features = _string_list(config, "features")
        configured_target = str(config.get("target", "")).strip()
        if configured_features and configured_features != features:
            raise ValueError("Profile features do not match MOJO model.ini")
        if configured_target and configured_target != target:
            raise ValueError("Profile target does not match MOJO model.ini")
    else:
        model_h2o_version = _required_string(config, "model_h2o_version")
        mojo_version = None
        features = _string_list(config, "features", required=True)
        target = _required_string(config, "target")

    categorical_features = _string_list(config, "categorical_features")
    if not set(categorical_features).issubset(features):
        raise ValueError("Profile categorical_features must be a subset of features")

    runtime_h2o_version = str(
        config.get("runtime_h2o_version", model_h2o_version)
    ).strip()
    if not runtime_h2o_version:
        raise ValueError("Profile setting 'runtime_h2o_version' is required")
    if model_format == "h2o_binary" and runtime_h2o_version != model_h2o_version:
        raise ValueError("Native binaries require matching producer and runtime H2O")

    python_version = _required_string(config, "python_version")
    java_version = _required_string(config, "java_version")
    h2o_pip_spec = str(config.get("h2o_pip_spec", "")).strip()
    if not h2o_pip_spec:
        h2o_pip_spec = f"h2o=={runtime_h2o_version}"

    bundle_dir = (
        Path(output_dir).resolve()
        if output_dir is not None
        else selected_bundle_dir(workshop_root)
    )
    if bundle_dir.exists():
        shutil.rmtree(bundle_dir)
    bundle_dir.mkdir(parents=True)

    model_path = bundle_dir / source_model_path.name
    shutil.copy2(source_model_path, model_path)
    golden_input_path = bundle_dir / GOLDEN_INPUT_FILE
    golden_expected_path = bundle_dir / GOLDEN_EXPECTED_FILE
    if golden_provided:
        shutil.copy2(source_golden_input, golden_input_path)
        shutil.copy2(source_golden_expected, golden_expected_path)

    prediction_type = None
    golden_rows = 0
    if golden_provided:
        golden_input = pd.read_csv(golden_input_path)
        golden_expected = pd.read_csv(golden_expected_path)
        if list(golden_input.columns) != features:
            raise ValueError(f"Golden input columns must be ordered as: {features}")
        if list(golden_expected.columns) != ["predict"]:
            raise ValueError("Golden expected must contain one column named 'predict'")
        if golden_input.empty or len(golden_input) != len(golden_expected):
            raise ValueError(
                "Golden files must contain the same non-zero row count"
            )
        expected_numeric = pd.to_numeric(
            golden_expected["predict"], errors="coerce"
        )
        prediction_type = (
            "number" if expected_numeric.notna().all() else "string"
        )
        golden_rows = len(golden_input)

    manifest: dict[str, Any] = {
        "profile": selected_profile,
        "model_name": _required_string(config, "model_name"),
        "environment_name": _required_string(config, "environment_name"),
        "endpoint_name": _required_string(config, "endpoint_name"),
        "deployment_name": _required_string(config, "deployment_name"),
        "input_data_name": _required_string(config, "input_data_name"),
        "experiment_name": _required_string(config, "experiment_name"),
        "model_version": _required_string(config, "model_version"),
        "model_format": model_format,
        "h2o_version": model_h2o_version,
        "runtime_h2o_version": runtime_h2o_version,
        "h2o_pip_spec": h2o_pip_spec,
        "python_version": python_version,
        "java_version": java_version,
        "model_file": model_path.name,
        "target": target,
        "features": features,
        "categorical_features": categorical_features,
        "prediction_type": prediction_type,
        "files": {model_path.name: _sha256(model_path)},
        "golden_data": {
            "provided": golden_provided,
            "validate": golden_validation_enabled,
            "required": require_golden_validation,
            "input_file": GOLDEN_INPUT_FILE if golden_provided else None,
            "expected_file": GOLDEN_EXPECTED_FILE if golden_provided else None,
        },
        "packaging": {"status": "passed"},
        "validation": {
            "status": (
                "pending"
                if golden_validation_enabled
                else "skipped"
                if golden_provided
                else "not_provided"
            ),
            "location": "target_runtime",
        },
    }
    if mojo_version:
        manifest["mojo_version"] = mojo_version
    if golden_provided:
        manifest["files"].update(
            {
                GOLDEN_INPUT_FILE: _sha256(golden_input_path),
                GOLDEN_EXPECTED_FILE: _sha256(golden_expected_path),
            }
        )
    if isinstance(config.get("source"), dict):
        manifest["source"] = config["source"]

    manifest_path = bundle_dir / "model_manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    summary = validate_bundle(
        bundle_dir,
        runtime_h2o_version,
        require_packaging_validation=True,
    )
    return {
        "profile": selected_profile,
        "profile_dir": str(profile_dir),
        "bundle_dir": str(bundle_dir),
        "model_path": str(model_path),
        "manifest_path": str(manifest_path),
        "golden_provided": golden_provided,
        "golden_rows": golden_rows,
        "manifest": manifest,
        "summary": summary,
    }