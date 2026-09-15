import json
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
WORKSHOP = REPO_ROOT / "workshop"


def notebook_code(relative_path: str) -> str:
    notebook = json.loads((WORKSHOP / relative_path).read_text(encoding="utf-8"))
    return "\n".join(
        "".join(cell.get("source", []))
        for cell in notebook["cells"]
        if cell.get("cell_type") == "code"
    )


def test_yaml_first_job_section_keeps_checked_in_definitions():
    single_step = notebook_code(
        "notebooks/02_jobs_and_pipelines/01_submit_single_step_merge.ipynb"
    )
    integration = notebook_code(
        "notebooks/02_jobs_and_pipelines/02_submit_integration_compare.ipynb"
    )

    assert 'pipelines/single-step-merge-job.yaml' in single_step
    assert 'pipelines/integration-compare-pipeline.yaml' in integration
    assert "outputs/generated" not in single_step
    assert "outputs/generated" not in integration

    for relative_path in (
        "pipelines/single-step-merge-job.yaml",
        "pipelines/integration-compare-pipeline.yaml",
        "src/components/transform.yaml",
        "src/components/train.yaml",
        "src/components/predict.yaml",
        "src/components/compare.yaml",
    ):
        with (WORKSHOP / relative_path).open(encoding="utf-8") as handle:
            assert yaml.safe_load(handle)


def test_foundation_and_h2o_runtime_files_are_not_checked_in_dependencies():
    notebook_paths = (
        "notebooks/01_foundations/03_register_environment.ipynb",
        "notebooks/01_foundations/05_submit_command_job.ipynb",
        "notebooks/01_foundations/06_deploy_online_endpoint.ipynb",
        "notebooks/03_h2o_reference/03_test_local_endpoint.ipynb",
        "notebooks/03_h2o_reference/04_deploy_reference_endpoint.ipynb",
        "notebooks/03_h2o_reference/05_submit_reference_scoring_pipeline.ipynb",
        "notebooks/04_h2o_customer/03_create_environment.ipynb",
        "notebooks/04_h2o_customer/04_deploy_online_endpoint.ipynb",
        "notebooks/04_h2o_customer/05_submit_scoring_pipeline.ipynb",
    )
    forbidden = (
        'WORKSHOP_ROOT / "environment/',
        'WORKSHOP_ROOT / "src/foundations/',
        'WORKSHOP_ROOT / "src/h2o/online',
        'WORKSHOP_ROOT / "src/h2o/batch',
        'WORKSHOP_ROOT / "pipelines/h2o-',
        'WORKSHOP_ROOT / "data/requests/',
    )

    for notebook_path in notebook_paths:
        code = notebook_code(notebook_path)
        assert "outputs/generated" in code, notebook_path
        for value in forbidden:
            assert value not in code, f"{notebook_path} still depends on {value}"


def test_customer_scorers_support_both_h2o_artifact_formats():
    online = notebook_code(
        "notebooks/04_h2o_customer/04_deploy_online_endpoint.ipynb"
    )
    batch = notebook_code(
        "notebooks/04_h2o_customer/05_submit_scoring_pipeline.ipynb"
    )

    for code in (online, batch):
        assert "h2o.load_model" in code
        assert "h2o.upload_mojo" in code
        assert "h2o_binary" in code
        assert "h2o_mojo" in code


def test_customer_packaging_supports_optional_golden_data():
    packaging = notebook_code(
        "notebooks/04_h2o_customer/01_package_and_validate_model.ipynb"
    )

    assert "H2O_CUSTOMER_GOLDEN_INPUT_PATH" in packaging
    assert "H2O_CUSTOMER_GOLDEN_EXPECTED_PATH" in packaging
    assert "H2O_CUSTOMER_RUN_GOLDEN_VALIDATION" in packaging
    assert "H2O_CUSTOMER_REQUIRE_GOLDEN_VALIDATION" in packaging
    assert '"provided": GOLDEN_PROVIDED' in packaging


def test_required_golden_validation_gates_batch_submission():
    batch = notebook_code(
        "notebooks/04_h2o_customer/05_submit_scoring_pipeline.ipynb"
    )

    assert "GOLDEN_VALIDATION_REQUIRED" in batch
    assert "RUNTIME_VALIDATION_PATH" in batch
    assert "Required runtime validation evidence is missing" in batch


def test_obsolete_checked_in_runtime_files_are_removed():
    obsolete_paths = (
        "data/requests/foundation-endpoint.json",
        "environment/foundations/conda.yaml",
        "environment/h2o/batch-conda.yaml",
        "environment/h2o/online-conda.yaml",
        "pipelines/h2o-customer-scoring-pipeline.yaml",
        "src/components/h2o-score.yaml",
        "src/foundations/command_job/summarize.py",
        "src/foundations/online/score.py",
        "src/h2o/batch/score.py",
        "src/h2o/online/score.py",
    )

    for relative_path in obsolete_paths:
        assert not (WORKSHOP / relative_path).exists(), relative_path
