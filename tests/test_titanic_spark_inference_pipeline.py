from __future__ import annotations

import ast
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace

import pandas as pd
import pytest
import yaml


ROOT = Path(__file__).resolve().parents[1]
SPARK_ROOT = ROOT / "workshop" / "notebooks" / "06_spark_jobs_pipelines"
SOURCE_ROOT = SPARK_ROOT / "src"
PIPELINE = SPARK_ROOT / "titanic-spark-inference-pipeline.yaml"
NOTEBOOK = SPARK_ROOT / "03_run_titanic_spark_inference_pipeline.ipynb"


@pytest.fixture
def verification():
    path = SOURCE_ROOT / "inference_verification.py"
    spec = importlib.util.spec_from_file_location("titanic_inference_verification", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_pipeline_selects_one_managed_spark_job_without_aml_compute():
    from azure.ai.ml import Input, load_job

    document = yaml.safe_load(PIPELINE.read_text(encoding="utf-8"))
    assert document["type"] == "pipeline"
    assert document["$schema"].endswith("/pipelineJob.schema.json")
    assert document["settings"]["force_rerun"] is True
    assert "default_compute" not in document["settings"]
    assert document["inputs"]["titanic_data"]["mode"] == "direct"
    assert document["inputs"]["model_input"]["mode"] == "direct"
    assert document["outputs"]["predictions"]["mode"] == "direct"
    assert tuple(document["jobs"]) == ("spark_score",)
    child = document["jobs"]["spark_score"]
    assert child["type"] == "spark"
    assert child["resources"] == {
        "instance_type": "standard_e4s_v3",
        "runtime_version": "3.5",
    }
    assert "compute" not in child
    assert "environment" not in child
    assert child["identity"] == {"type": "user_identity"}
    assert child["inputs"]["model_input"]["mode"] == "direct"
    assert child["inputs"]["titanic_data"]["mode"] == "direct"
    assert child["outputs"]["predictions"] == {
        "type": "uri_folder",
        "path": "${{parent.outputs.predictions}}",
        "mode": "direct",
    }

    pipeline = load_job(PIPELINE)
    pipeline.inputs.model_input = Input(
        type="uri_folder",
        path="azureml://datastores/workspaceblobstore/paths/LocalUpload/model-v1/pipeline_model",
        mode="direct",
    )
    pipeline.inputs.model_asset_id = "registered-model-id"
    assert pipeline._validate().passed
    assert pipeline.jobs["spark_score"].type == "spark"
    assert pipeline.jobs["spark_score"].compute is None
    output = pipeline._to_rest_object().serialize()["properties"]["jobs"][
        "spark_score"
    ]["outputs"]["predictions"]
    assert output["mode"].lower() == "direct"


def test_native_entry_point_never_creates_a_local_spark_master():
    source = (SOURCE_ROOT / "inference" / "spark_inference.py").read_text(encoding="utf-8")
    ast.parse(source, filename="spark_inference.py")
    assert ".master(" not in source
    assert ".toPandas(" not in source
    assert "PipelineModel.load" in source
    assert "spark.sparkContext.master" in source
    assert "spark.version" in source
    assert "model_asset_id" in source


def test_notebook_submits_only_jobs_and_verifies_registered_model_predictions():
    notebook = json.loads(NOTEBOOK.read_text(encoding="utf-8"))
    code = "\n".join(
        "".join(cell.get("source", []))
        for cell in notebook["cells"]
        if cell["cell_type"] == "code"
    )
    ast.parse(code, filename=NOTEBOOK.name)
    for token in (
        "load_job(",
        "ml_client.jobs.create_or_update",
        "ml_client.jobs.stream",
        "registered_model.path",
        "registered_model.id",
        "stage_registered_model",
        "assert_native_spark_job",
        "load_verified_predictions",
        "assert_prediction_parity",
        "DataLakeServiceClient",
        "RUN_TITANIC_SPARK_INFERENCE_PIPELINE",
        "TITANIC_SPARK_INFERENCE_JOB_NAME",
        "uuid.uuid4()",
    ):
        assert token in code
    for forbidden in (
        "batch_endpoints",
        "batch_deployments",
        "BatchEndpoint",
        "BatchDeployment",
        "components.create_or_update",
        "models.create_or_update",
        "environments.create_or_update",
        "subprocess",
        "os.system",
    ):
        assert forbidden not in code
    assert "mlops-azureml" == notebook["metadata"]["kernelspec"]["name"]


def test_inference_submission_is_disabled_by_default():
    example = (ROOT / "workshop" / ".env.example").read_text(encoding="utf-8")
    assert "RUN_TITANIC_SPARK_INFERENCE_PIPELINE=false" in example
    assert "TITANIC_SPARK_INFERENCE_JOB_NAME=" in example
    assert "TITANIC_SPARK_INFERENCE_OUTPUT_PATH=pipelines/titanic-inference" in example
    assert "TITANIC_SPARK_INFERENCE_REFERENCE_PREDICTIONS_PATH=" in example
    assert "PROMOTE_TITANIC_NATIVE_SPARK" not in example


def test_verification_requires_actual_amlspark_job_marker(verification):
    native = SimpleNamespace(
        properties={"_azureml.ComputeTargetType": "amlspark"},
        compute="Serverless",
    )
    verification.assert_native_spark_job(native)
    standalone = SimpleNamespace(
        type="spark",
        compute=None,
        resources=SimpleNamespace(instance_type="standard_e4s_v3"),
        properties={"_azureml.ComputeTargetType": "amlspark"},
    )
    verification.assert_native_spark_job(standalone)
    for job in (
        SimpleNamespace(properties={}, compute="Serverless"),
        SimpleNamespace(
            properties={"_azureml.ComputeTargetType": "amlcompute"},
            compute="aml-cluster-public-ncus04",
        ),
        SimpleNamespace(
            properties={"_azureml.ComputeTargetType": "amlspark"},
            compute="aml-cluster-public-ncus04",
        ),
        SimpleNamespace(
            properties={"_azureml.ComputeTargetType": "amlspark"},
            compute=None,
        ),
        SimpleNamespace(
            type="spark", compute=None,
            properties={"_azureml.ComputeTargetType": "amlspark"},
            resources=SimpleNamespace(instance_type=None),
        ),
    ):
        with pytest.raises(RuntimeError):
            verification.assert_native_spark_job(job)


def test_runtime_manifest_checks_runtime_master_and_registered_model(verification):
    manifest = {
        "spark_version": "3.5.8",
        "spark_master": "yarn",
        "model_asset_id": "azureml:model:1",
        "registered_artifact_uri": "azureml://datastores/models/paths/model-v1/",
        "model_content_sha256": "a" * 64,
        "input_rows": 2,
        "output_rows": 2,
    }
    source_uri = manifest["registered_artifact_uri"]
    verification.validate_runtime_manifest(manifest, "azureml:model:1", 2, source_uri)
    for field, invalid_value in (
        ("spark_version", "3.4.0"),
        ("spark_master", "local[1]"),
        ("model_asset_id", "azureml:model:2"),
        ("registered_artifact_uri", "azureml://datastores/models/paths/model-v2/"),
        ("model_content_sha256", "unverified"),
        ("output_rows", 1),
    ):
        invalid_manifest = {**manifest, field: invalid_value}
        with pytest.raises(RuntimeError):
            verification.validate_runtime_manifest(
                invalid_manifest, "azureml:model:1", 2, source_uri
            )


def test_prediction_contract_rejects_fractional_classes_duplicates_and_bad_probabilities(
    verification,
):
    predictions = pd.DataFrame(
        {
            "source_file": ["titanic.csv", "titanic.csv"],
            "PassengerId": [1, 2],
            "prediction": [0, 1],
            "actual_label": [0, 1],
            "survival_probability": [0.1, 0.9],
        }
    )
    verification.validate_predictions(predictions, {1, 2})
    for column, values in (
        ("PassengerId", [1, 1]),
        ("PassengerId", [1, 3]),
        ("PassengerId", [1.5, 2]),
        ("prediction", [0.5, 1]),
        ("survival_probability", [float("nan"), 0.9]),
        ("survival_probability", [0.1, float("inf")]),
    ):
        invalid = predictions.copy()
        invalid[column] = values
        with pytest.raises(RuntimeError):
            verification.validate_predictions(invalid, {1, 2})


def test_parity_comparison_is_keyed_by_passenger_not_row_order(verification):
    original = pd.DataFrame(
        {
            "PassengerId": [1, 2],
            "prediction": [0, 1],
            "survival_probability": [0.1, 0.9],
        }
    )
    verification.assert_prediction_parity(original.iloc[::-1], original)
    changed = original.copy()
    changed.loc[0, "survival_probability"] = 0.3
    with pytest.raises(RuntimeError):
        verification.assert_prediction_parity(changed, original)
