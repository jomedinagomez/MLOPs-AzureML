"""Azure ML batch scoring entry point for the Titanic Spark ML model."""

from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import List

import pandas as pd
from pyspark.ml import PipelineModel
from pyspark.ml.functions import vector_to_array
from pyspark.sql import SparkSession
from pyspark.sql import functions as F


spark: SparkSession
model: PipelineModel


def _find_spark_model(model_root: Path) -> Path:
    candidates = sorted(
        metadata.parent
        for metadata in model_root.rglob("metadata")
        if (metadata.parent / "stages").is_dir()
    )
    if len(candidates) != 1:
        raise RuntimeError(
            f"Expected one Spark ML pipeline below {model_root}, found {candidates}"
        )
    return candidates[0]


def init() -> None:
    global spark
    global model

    os.environ["PYSPARK_PYTHON"] = sys.executable
    os.environ["PYSPARK_DRIVER_PYTHON"] = sys.executable
    spark = (
        SparkSession.builder.master("local[1]")
        .appName("titanic-spark-batch-scoring")
        .config("spark.ui.enabled", "false")
        .getOrCreate()
    )
    spark.sparkContext.setLogLevel("WARN")

    model_root = Path(os.environ["AZUREML_MODEL_DIR"]).resolve()
    spark_model_path = _find_spark_model(model_root)
    model = PipelineModel.load(str(spark_model_path))
    print(f"Loaded Spark ML model from {spark_model_path}")


def run(mini_batch: List[str]) -> pd.DataFrame:
    csv_paths = [path for path in mini_batch if path.lower().endswith(".csv")]
    if not csv_paths:
        return pd.DataFrame(
            columns=[
                "source_file",
                "PassengerId",
                "prediction",
                "actual_label",
                "survival_probability",
            ]
        )

    source = (
        spark.read.option("header", True)
        .option("inferSchema", True)
        .csv(csv_paths)
    )
    required_columns = {
        "PassengerId",
        "Survived",
        "Pclass",
        "Sex",
        "Age",
        "SibSp",
        "Parch",
        "Fare",
        "Embarked",
    }
    missing_columns = required_columns.difference(source.columns)
    if missing_columns:
        raise ValueError(
            f"Batch input is missing required columns: {sorted(missing_columns)}"
        )

    prepared = (
        source.select(
            F.element_at(F.split(F.input_file_name(), "/"), -1).alias(
                "source_file"
            ),
            F.col("PassengerId").cast("long").alias("PassengerId"),
            F.col("Survived").cast("double").alias("actual_label"),
            F.col("Pclass").cast("double").alias("Pclass"),
            F.col("Sex").cast("string").alias("Sex"),
            F.col("Age").cast("double").alias("Age"),
            F.col("SibSp").cast("double").alias("SibSp"),
            F.col("Parch").cast("double").alias("Parch"),
            F.col("Fare").cast("double").alias("Fare"),
            F.col("Embarked").cast("string").alias("Embarked"),
        )
        .fillna({"Embarked": "Unknown"})
        .dropna(
            subset=[
                "PassengerId",
                "Pclass",
                "Sex",
                "SibSp",
                "Parch",
                "Fare",
            ]
        )
    )
    predictions = model.transform(prepared)
    output = (
        predictions.select(
            "source_file",
            "PassengerId",
            F.col("prediction").cast("int").alias("prediction"),
            F.col("actual_label").cast("int").alias("actual_label"),
            vector_to_array("probability")[1].alias("survival_probability"),
        )
        .orderBy("PassengerId")
        .toPandas()
    )
    print(f"Scored {len(output)} rows from {len(csv_paths)} file(s)")
    return output
