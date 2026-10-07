from __future__ import annotations

import ast
import json
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
WORKSHOP = REPO_ROOT / "workshop"
SPARK_ROOT = WORKSHOP / "notebooks" / "06_spark_jobs_pipelines"
PIPELINE_FILE = SPARK_ROOT / "titanic-spark-training-pipeline.yml"
NOTEBOOK_FILE = SPARK_ROOT / "02_submit_titanic_training_pipeline.ipynb"
SOURCE_ROOT = SPARK_ROOT / "src" / "pipeline"


def test_pipeline_has_four_ordered_spark_35_jobs():
    pipeline = yaml.safe_load(PIPELINE_FILE.read_text(encoding="utf-8"))

    assert pipeline["type"] == "pipeline"
    assert tuple(pipeline["jobs"]) == (
        "prepare_data",
        "train_model",
        "score_test_data",
        "validate_model",
    )
    assert pipeline["inputs"]["titanic_data"]["path"].startswith(
        "abfss://spark@stpublicdlncus04.dfs.core.windows.net/"
    )

    for name, job in pipeline["jobs"].items():
        assert job["type"] == "spark", name
        assert job["resources"]["runtime_version"] == "3.5", name
        assert job["resources"]["instance_type"] == "standard_e4s_v3", name
        assert job["identity"] == {"type": "user_identity"}, name

    train_input = pipeline["jobs"]["train_model"]["inputs"]["prepared_data"]
    assert train_input["path"] == "${{parent.jobs.prepare_data.outputs.prepared_data}}"
    assert train_input["mode"] == "direct"

    evaluate_inputs = pipeline["jobs"]["score_test_data"]["inputs"]
    assert (
        evaluate_inputs["model_input"]["path"]
        == "${{parent.jobs.train_model.outputs.model_output}}"
    )
    assert (
        evaluate_inputs["prepared_data"]["path"]
        == "${{parent.jobs.prepare_data.outputs.prepared_data}}"
    )
    assert all(value["mode"] == "direct" for value in evaluate_inputs.values())

    validation_input = pipeline["jobs"]["validate_model"]["inputs"]["metrics_input"]
    assert (
        validation_input["path"]
        == "${{parent.jobs.score_test_data.outputs.metrics_output}}"
    )
    assert validation_input["mode"] == "direct"


def test_pipeline_sources_are_valid_and_cover_prepare_train_evaluate():
    required_tokens = {
        "prepare_titanic.py": (
            "randomSplit",
            'write.mode("overwrite").parquet',
            "label",
        ),
        "train_titanic.py": (
            "RandomForestClassifier",
            "VectorAssembler",
            'write().overwrite().save',
        ),
        "score_titanic.py": (
            "PipelineModel.load",
            "MulticlassClassificationEvaluator",
            "BinaryClassificationEvaluator",
            "accuracy",
        ),
        "validate_titanic.py": (
            "validated",
            "accuracy_threshold",
            "model validation failed",
        ),
    }

    for name, tokens in required_tokens.items():
        source = (SOURCE_ROOT / name).read_text(encoding="utf-8")
        ast.parse(source, filename=name)
        for token in tokens:
            assert token in source, f"{name} is missing {token}"


def test_notebook_submits_pipeline_downloads_artifacts_and_registers_model():
    notebook = json.loads(NOTEBOOK_FILE.read_text(encoding="utf-8"))
    code = "\n".join(
        "".join(cell.get("source", []))
        for cell in notebook["cells"]
        if cell.get("cell_type") == "code"
    )

    ast.parse(code, filename=NOTEBOOK_FILE.name)
    assert "load_job(" in code
    assert "ml_client.jobs.create_or_update" in code
    assert "ml_client.jobs.stream" in code
    assert "DataLakeServiceClient" in code
    assert "ml_client.models.create_or_update" in code
    assert "AssetTypes.CUSTOM_MODEL" in code
    assert "validated" in code
    assert "TITANIC_SPARK_VALIDATION_PATH" in code
    assert "RUN_TITANIC_SPARK_PIPELINE" in code
    assert "REGISTER_TITANIC_SPARK_MODEL" in code
    assert "subprocess" not in code
    assert "os.system" not in code
    assert "az ml" not in code.lower()


def test_environment_and_dependency_contracts_are_documented():
    env_example = (WORKSHOP / ".env.example").read_text(encoding="utf-8")
    requirements = (WORKSHOP / "requirements.txt").read_text(encoding="utf-8")

    assert "TITANIC_SPARK_MODEL_NAME=workshop-titanic-spark-model" in env_example
    assert "RUN_TITANIC_SPARK_PIPELINE=false" in env_example
    assert "REGISTER_TITANIC_SPARK_MODEL=false" in env_example
    assert (
        "TITANIC_SPARK_VALIDATION_PATH=pipelines/titanic-training/validation"
        in env_example
    )
    assert "azure-storage-file-datalake==12.14.0" in requirements
