from __future__ import annotations

import ast
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
WORKSHOP = REPO_ROOT / "workshop"
SPARK_ROOT = WORKSHOP / "notebooks" / "06_spark_jobs_pipelines"
BATCH_ROOT = SPARK_ROOT / "batch"


def test_batch_scoring_contract_loads_spark_model_and_returns_predictions():
    source = (BATCH_ROOT / "score.py").read_text(encoding="utf-8")

    ast.parse(source, filename="score.py")
    for token in (
        "def init(",
        "def run(",
        "AZUREML_MODEL_DIR",
        "PipelineModel.load",
        "SparkSession.builder",
        "PassengerId",
        "survival_probability",
    ):
        assert token in source


def test_batch_environment_contains_java_spark_and_azure_batch_runtime():
    conda = yaml.safe_load(
        (BATCH_ROOT / "conda.yml").read_text(encoding="utf-8")
    )
    dependencies = conda["dependencies"]
    pip_dependencies = next(
        dependency["pip"]
        for dependency in dependencies
        if isinstance(dependency, dict) and "pip" in dependency
    )

    assert "python=3.10" in dependencies
    assert "openjdk=17" in dependencies
    assert "pyspark==3.5.8" in pip_dependencies
    assert "azureml-core==1.60.0.post1" in pip_dependencies
    assert "azureml-dataset-runtime[fuse]==1.60.0" in pip_dependencies

