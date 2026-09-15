import json
import shutil
import sys
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
WORKSHOP_ROOT = REPO_ROOT / "workshop"
H2O_SOURCE = WORKSHOP_ROOT / "src" / "h2o"
PROFILE_ROOT = WORKSHOP_ROOT / "data" / "h2o" / "customer_bundle" / "profiles"

sys.path.insert(0, str(H2O_SOURCE))
from customer_profiles import prepare_customer_bundle  # noqa: E402
from validate_bundle import validate_bundle  # noqa: E402


def temporary_profile_root(tmp_path: Path, profile: str) -> Path:
    workshop_root = tmp_path / "workshop"
    destination = (
        workshop_root / "data" / "h2o" / "customer_bundle" / "profiles" / profile
    )
    shutil.copytree(PROFILE_ROOT / profile, destination)
    return workshop_root


def test_prepopulated_mojo_profile_is_detected_and_validated(tmp_path):
    result = prepare_customer_bundle(
        WORKSHOP_ROOT,
        "mojo",
        output_dir=tmp_path / "bundle",
    )
    summary = result["summary"]

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
    assert summary["golden_rows"] == 4


def test_prepopulated_binary_profile_is_detected_and_validated(tmp_path):
    result = prepare_customer_bundle(
        WORKSHOP_ROOT,
        "binary",
        output_dir=tmp_path / "bundle",
    )
    summary = result["summary"]

    assert summary["model_format"] == "h2o_binary"
    assert summary["h2o_version"] == "3.46.0.12"
    assert summary["runtime_h2o_version"] == "3.46.0.12"
    assert summary["mojo_version"] is None
    assert summary["golden_provided"] is True
    assert summary["golden_rows"] == 20


def test_mojo_profile_asserted_features_must_match_model_ini(tmp_path):
    workshop_root = temporary_profile_root(tmp_path, "mojo")
    profile_path = (
        workshop_root
        / "data/h2o/customer_bundle/profiles/mojo/profile.json"
    )
    profile = json.loads(profile_path.read_text(encoding="utf-8"))
    profile["features"] = ["wrong_feature"]
    profile_path.write_text(json.dumps(profile), encoding="utf-8")

    with pytest.raises(ValueError, match="do not match MOJO model.ini"):
        prepare_customer_bundle(workshop_root, "mojo")


def test_profile_rejects_a_model_of_the_other_format(tmp_path):
    workshop_root = temporary_profile_root(tmp_path, "mojo")
    source = workshop_root / "data/h2o/customer_bundle/profiles/mojo"
    source.rename(source.parent / "binary")

    with pytest.raises(ValueError, match="requires h2o_binary"):
        prepare_customer_bundle(workshop_root, "binary")


def test_binary_profile_can_omit_golden_data(tmp_path):
    workshop_root = temporary_profile_root(tmp_path, "binary")
    profile_dir = (
        workshop_root / "data/h2o/customer_bundle/profiles/binary"
    )
    (profile_dir / "golden_input.csv").unlink()
    (profile_dir / "golden_expected.csv").unlink()

    result = prepare_customer_bundle(workshop_root, "binary")
    summary = result["summary"]

    assert summary["model_format"] == "h2o_binary"
    assert summary["golden_provided"] is False
    assert summary["golden_validation_enabled"] is False
    assert summary["golden_rows"] == 0
    assert summary["golden_validation"] == "not_provided"


def test_profile_rejects_an_incomplete_golden_pair(tmp_path):
    workshop_root = temporary_profile_root(tmp_path, "binary")
    profile_dir = (
        workshop_root / "data/h2o/customer_bundle/profiles/binary"
    )
    (profile_dir / "golden_expected.csv").unlink()

    with pytest.raises(ValueError, match="must contain both"):
        prepare_customer_bundle(workshop_root, "binary")


def test_required_golden_validation_rejects_missing_data(tmp_path):
    workshop_root = temporary_profile_root(tmp_path, "binary")
    profile_dir = (
        workshop_root / "data/h2o/customer_bundle/profiles/binary"
    )
    (profile_dir / "golden_input.csv").unlink()
    (profile_dir / "golden_expected.csv").unlink()

    with pytest.raises(ValueError, match="required, but no golden pair exists"):
        prepare_customer_bundle(
            workshop_root,
            "binary",
            require_golden_validation=True,
        )


def test_golden_runtime_validation_can_be_disabled(tmp_path):
    result = prepare_customer_bundle(
        WORKSHOP_ROOT,
        "mojo",
        run_golden_validation=False,
        output_dir=tmp_path / "bundle",
    )
    summary = validate_bundle(
        Path(result["bundle_dir"]),
        "3.46.0.12",
        require_packaging_validation=True,
    )

    assert summary["golden_provided"] is True
    assert summary["golden_validation_enabled"] is False
    assert summary["golden_validation"] == "skipped"
