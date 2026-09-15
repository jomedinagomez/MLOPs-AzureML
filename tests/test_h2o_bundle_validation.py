import importlib.util
import json
import shutil
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
VALIDATOR_PATH = REPO_ROOT / "workshop" / "src" / "h2o" / "validate_bundle.py"
DEMO_BUNDLE = REPO_ROOT / "workshop" / "data" / "h2o" / "customer_bundle" / "demo"
REFERENCE_BUNDLE = REPO_ROOT / "workshop" / "data" / "h2o" / "reference_bundle"

spec = importlib.util.spec_from_file_location("validate_bundle", VALIDATOR_PATH)
validate_bundle_module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(validate_bundle_module)


def test_published_mojo_demo_bundle_validates():
    summary = validate_bundle_module.validate_bundle(
        DEMO_BUNDLE,
        "3.46.0.12",
        require_packaging_validation=True,
    )

    assert summary["model_format"] == "h2o_mojo"
    assert summary["h2o_version"] == "3.32.0.99999"
    assert summary["runtime_h2o_version"] == "3.46.0.12"
    assert summary["mojo_version"] == "1.40"
    assert summary["model_category"] == "Binomial"
    assert summary["packaging_validation"] == "passed"
    assert summary["golden_provided"] is True
    assert summary["golden_validation_enabled"] is True
    assert summary["golden_required"] is False
    assert summary["golden_validation"] == "pending"


def test_native_reference_bundle_remains_supported():
    summary = validate_bundle_module.validate_bundle(
        REFERENCE_BUNDLE,
        "3.46.0.12",
    )

    assert summary["model_format"] == "h2o_binary"
    assert summary["runtime_h2o_version"] == "3.46.0.12"
    assert summary["mojo_version"] is None
    assert summary["golden_provided"] is True


def test_mojo_manifest_feature_order_must_match_model(tmp_path):
    bundle = tmp_path / "bundle"
    shutil.copytree(DEMO_BUNDLE, bundle)
    manifest_path = bundle / "model_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["features"] = list(reversed(manifest["features"]))
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    with pytest.raises(ValueError, match="Manifest features must match MOJO columns"):
        validate_bundle_module.validate_bundle(bundle, "3.46.0.12")


def test_native_bundle_can_omit_golden_data(tmp_path):
    bundle = tmp_path / "native"
    bundle.mkdir()
    model_path = bundle / "customer-native-model"
    shutil.copy2(REFERENCE_BUNDLE / "taxi-fare-gbm", model_path)
    reference_manifest = json.loads(
        (REFERENCE_BUNDLE / "model_manifest.json").read_text(encoding="utf-8")
    )
    manifest = {
        **reference_manifest,
        "model_name": "customer-native-model",
        "model_file": model_path.name,
        "runtime_h2o_version": reference_manifest["h2o_version"],
        "files": {
            model_path.name: validate_bundle_module.sha256(model_path),
        },
        "golden_data": {
            "provided": False,
            "validate": False,
            "required": False,
            "input_file": None,
            "expected_file": None,
        },
        "packaging": {"status": "passed"},
        "validation": {"status": "not_provided", "location": "target_runtime"},
    }
    (bundle / "model_manifest.json").write_text(
        json.dumps(manifest),
        encoding="utf-8",
    )

    summary = validate_bundle_module.validate_bundle(
        bundle,
        "3.46.0.12",
        require_packaging_validation=True,
    )

    assert summary["model_format"] == "h2o_binary"
    assert summary["golden_provided"] is False
    assert summary["golden_validation_enabled"] is False
    assert summary["golden_rows"] == 0
    assert summary["golden_validation"] == "not_provided"


def test_required_golden_validation_rejects_missing_data(tmp_path):
    bundle = tmp_path / "native"
    bundle.mkdir()
    model_path = bundle / "customer-native-model"
    shutil.copy2(REFERENCE_BUNDLE / "taxi-fare-gbm", model_path)
    reference_manifest = json.loads(
        (REFERENCE_BUNDLE / "model_manifest.json").read_text(encoding="utf-8")
    )
    manifest = {
        **reference_manifest,
        "model_file": model_path.name,
        "runtime_h2o_version": reference_manifest["h2o_version"],
        "files": {model_path.name: validate_bundle_module.sha256(model_path)},
        "golden_data": {
            "provided": False,
            "validate": True,
            "required": True,
            "input_file": None,
            "expected_file": None,
        },
    }
    (bundle / "model_manifest.json").write_text(
        json.dumps(manifest),
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="required but golden data is not provided"):
        validate_bundle_module.validate_bundle(bundle, "3.46.0.12")


def test_golden_runtime_validation_can_be_disabled(tmp_path):
    bundle = tmp_path / "bundle"
    shutil.copytree(DEMO_BUNDLE, bundle)
    manifest_path = bundle / "model_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["golden_data"]["validate"] = False
    manifest["validation"]["status"] = "skipped"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    summary = validate_bundle_module.validate_bundle(
        bundle,
        "3.46.0.12",
        require_packaging_validation=True,
    )

    assert summary["golden_provided"] is True
    assert summary["golden_validation_enabled"] is False
    assert summary["golden_validation"] == "skipped"
