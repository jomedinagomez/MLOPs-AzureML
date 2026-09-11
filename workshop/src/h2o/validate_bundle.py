from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import pandas as pd


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


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_bundle(
    bundle_dir: Path,
    expected_h2o_version: str | None = None,
) -> dict:
    bundle_dir = Path(bundle_dir).resolve()
    manifest_path = bundle_dir / "model_manifest.json"
    if not manifest_path.is_file():
        raise FileNotFoundError(f"Manifest not found: {manifest_path}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    missing_fields = sorted(REQUIRED_MANIFEST_FIELDS - manifest.keys())
    if missing_fields:
        raise ValueError(f"Manifest fields missing: {missing_fields}")
    if manifest["model_format"] != "h2o_binary":
        raise ValueError("The manifest does not describe an H2O binary model")
    if str(manifest["model_version"]).lower() == "latest":
        raise ValueError("Use an immutable model version, not 'latest'")
    if expected_h2o_version and manifest["h2o_version"] != expected_h2o_version:
        raise ValueError(
            f"Expected h2o=={expected_h2o_version}; bundle requires {manifest['h2o_version']}"
        )

    features = manifest["features"]
    categorical_features = manifest["categorical_features"]
    if not isinstance(features, list) or not features or len(features) != len(set(features)):
        raise ValueError("Manifest features must be a non-empty list without duplicates")
    if not set(categorical_features).issubset(features):
        raise ValueError("Every categorical feature must also appear in features")

    required_files = {
        manifest["model_file"],
        "golden_input.csv",
        "golden_expected.csv",
    }
    if not required_files.issubset(manifest["files"]):
        missing = sorted(required_files - manifest["files"].keys())
        raise ValueError(f"Manifest checksums missing: {missing}")

    for name, expected_hash in manifest["files"].items():
        path = bundle_dir / name
        if not path.is_file():
            raise FileNotFoundError(f"Bundle file not found: {path}")
        if sha256(path) != expected_hash:
            raise ValueError(f"Checksum mismatch: {name}")

    golden_input = pd.read_csv(bundle_dir / "golden_input.csv")
    golden_expected = pd.read_csv(bundle_dir / "golden_expected.csv")
    if list(golden_input.columns) != features:
        raise ValueError(f"Golden input columns must be ordered as: {features}")
    if list(golden_expected.columns) != ["predict"]:
        raise ValueError("Golden expected output must contain only the 'predict' column")
    if golden_input.empty or len(golden_input) != len(golden_expected):
        raise ValueError("Golden input and expected output must contain the same non-zero row count")

    return {
        "bundle_dir": str(bundle_dir),
        "model_name": manifest["model_name"],
        "model_version": str(manifest["model_version"]),
        "model_format": manifest["model_format"],
        "h2o_version": manifest["h2o_version"],
        "model_file": manifest["model_file"],
        "features": features,
        "golden_rows": len(golden_input),
        "checksums": "passed",
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate an H2O binary-model bundle")
    parser.add_argument("--bundle-dir", required=True)
    parser.add_argument("--expected-h2o-version")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    result = validate_bundle(Path(args.bundle_dir), args.expected_h2o_version)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()