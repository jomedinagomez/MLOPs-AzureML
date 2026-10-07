from __future__ import annotations

import ast
import importlib.util
import json
from pathlib import Path
import shlex
from types import SimpleNamespace
from unittest.mock import Mock

import pandas as pd
import pytest
import yaml


ROOT = Path(__file__).resolve().parents[1]
SPARK_ROOT = ROOT / "workshop" / "notebooks" / "06_spark_jobs_pipelines"
JOB = SPARK_ROOT / "titanic-serverless-model-consumption.yaml"
NOTEBOOK = SPARK_ROOT / "04_consume_registered_model_serverless_spark.ipynb"


@pytest.fixture
def verification():
    spec = importlib.util.spec_from_file_location(
        "consumption_verification", SPARK_ROOT / "src" / "inference_verification.py"
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_consumption_is_a_standalone_serverless_spark_job():
    from azure.ai.ml import load_job

    document = yaml.safe_load(JOB.read_text(encoding="utf-8"))
    assert document["type"] == "spark"
    assert document["$schema"].endswith("/sparkJob.schema.json")
    assert "jobs" not in document
    assert "compute" not in document
    assert "environment" not in document
    assert document["identity"] == {"type": "user_identity"}
    assert document["resources"] == {
        "instance_type": "standard_e4s_v3", "runtime_version": "3.5",
    }
    assert set(document["inputs"]) == {"titanic_data", "model_input"}
    assert all(item["mode"] == "direct" for item in document["inputs"].values())
    assert document["outputs"]["predictions"]["mode"] == "direct"

    model_id = "/subscriptions/sub/resourceGroups/rg/workspaces/ws/models/titanic/versions/1"
    model_uri = "abfss://spark@storage.dfs.core.windows.net/models/registered/version-1/"
    output_uri = "abfss://spark@storage.dfs.core.windows.net/model-consumption/test/"
    job_args = document["args"].replace("__REGISTERED_MODEL_ID__", shlex.quote(model_id))
    job = load_job(JOB, params_override=[
        {"inputs.model_input.path": model_uri},
        {"outputs.predictions.path": output_uri},
        {"args": job_args},
    ])
    assert job._validate().passed
    assert job.compute is None
    request = job._to_job()._to_rest_object().serialize()["properties"]
    assert request["jobType"] == "Spark"
    assert request["inputs"]["model_input"]["uri"] == model_uri
    assert request["outputs"]["predictions"]["uri"] == output_uri
    assert model_id in request["args"]
    assert "__REGISTERED_MODEL_ID__" not in request["args"]


def test_consumption_notebook_uses_registered_model_and_shared_native_helpers():
    notebook = json.loads(NOTEBOOK.read_text(encoding="utf-8"))
    code = "\n".join(
        "".join(cell["source"]) for cell in notebook["cells"] if cell["cell_type"] == "code"
    )
    ast.parse(code, filename=NOTEBOOK.name)
    for token in (
        "ml_client.models.get", "stage_registered_model",
        "ml_client.jobs.create_or_update", "ml_client.jobs.stream",
        "assert_native_spark_job", "download_predictions", "load_verified_predictions",
        "assert_prediction_parity", "shlex.quote(registered_model.id)",
        "RUN_TITANIC_SPARK_MODEL_CONSUMPTION", "TITANIC_SPARK_MODEL_CONSUMPTION_JOB_NAME",
        "display(", "uuid.uuid4()",
    ):
        assert token in code
    for forbidden in (
        "batch_endpoints", "batch_deployments", "pipeline_job",
        "SparkSession", "models.create_or_update", "environments.create_or_update",
        "components.create_or_update", "subprocess", "os.system",
    ):
        assert forbidden not in code
    assert notebook["metadata"]["kernelspec"]["name"] == "mlops-azureml"


def test_consumption_configuration_defaults_are_safe():
    example = (ROOT / "workshop" / ".env.example").read_text(encoding="utf-8")
    assert "RUN_TITANIC_SPARK_MODEL_CONSUMPTION=false" in example
    assert "TITANIC_SPARK_MODEL_CONSUMPTION_JOB_NAME=" in example
    assert "TITANIC_SPARK_MODEL_CONSUMPTION_OUTPUT_PATH=model-consumption/titanic" in example
    assert "TITANIC_SPARK_MODEL_CONSUMPTION_REFERENCE_PREDICTIONS_PATH=" in example


def test_shared_reader_validates_output_shape_and_provenance(verification, tmp_path):
    directory = tmp_path / "results"
    (directory / "csv").mkdir(parents=True)
    (directory / "runtime").mkdir()
    predictions = pd.DataFrame(
        {"PassengerId": [1, 2], "prediction": [0, 1], "survival_probability": [0.1, 0.9]}
    )
    predictions.to_csv(directory / "csv" / "part-000.csv", index=False)
    manifest = {
        "spark_version": "3.5.5", "spark_master": "yarn",
        "model_asset_id": "model:1", "registered_artifact_uri": "azureml://registered/model/",
        "model_content_sha256": "a" * 64, "input_rows": 2, "output_rows": 2,
    }
    runtime = directory / "runtime" / "part-000.json"
    runtime.write_text(json.dumps(manifest), encoding="utf-8")
    actual, evidence = verification.load_verified_predictions(
        directory, {1, 2}, "model:1", "azureml://registered/model/"
    )
    pd.testing.assert_frame_equal(actual, predictions)
    assert evidence == manifest
    with pytest.raises(RuntimeError, match="registered model"):
        verification.load_verified_predictions(
            directory, {1, 2}, "model:2", "azureml://registered/model/"
        )
    runtime.write_text("[]", encoding="utf-8")
    with pytest.raises(ValueError, match="JSON object"):
        verification.load_verified_predictions(
            directory, {1, 2}, "model:1", "azureml://registered/model/"
        )


def test_shared_downloader_uses_identity_and_rejects_unsafe_paths(verification, monkeypatch, tmp_path):
    content = b"PassengerId,prediction,survival_probability\n1,0,0.1\n"
    paths = [SimpleNamespace(name="output/job/csv/part-000.csv", is_directory=False)]
    filesystem = SimpleNamespace(
        get_paths=lambda **kwargs: paths,
        get_file_client=lambda name: SimpleNamespace(
            download_file=lambda: SimpleNamespace(readall=lambda: content)
        ),
    )
    service = Mock()
    service.__enter__ = Mock(return_value=service)
    service.__exit__ = Mock(return_value=False)
    service.get_file_system_client.return_value = filesystem
    factory = Mock(return_value=service)
    monkeypatch.setattr(verification, "DataLakeServiceClient", factory)
    credential = Mock()
    verification.download_predictions(
        "abfss://spark@storage.dfs.core.windows.net/output/job/", tmp_path, credential
    )
    factory.assert_called_once_with(
        account_url="https://storage.dfs.core.windows.net", credential=credential
    )
    assert (tmp_path / "csv" / "part-000.csv").read_bytes() == content
    paths[:] = [SimpleNamespace(name="output/job/../outside.csv", is_directory=False)]
    with pytest.raises(ValueError, match="Invalid remote output path"):
        verification.download_predictions(
            "abfss://spark@storage.dfs.core.windows.net/output/job/", tmp_path, credential
        )


@pytest.mark.parametrize(
    "uri",
    [
        "https://storage.blob.core.windows.net/output/job/",
        "abfss://spark@storage.dfs.core.windows.net/",
        "abfss://spark@storage.dfs.core.windows.net/output/../",
    ],
)
def test_shared_downloader_rejects_invalid_or_broad_outputs(verification, tmp_path, uri):
    with pytest.raises(ValueError):
        verification.download_predictions(uri, tmp_path, Mock())
