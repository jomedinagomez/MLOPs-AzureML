"""Score a registered Titanic model using managed serverless Spark 3.5."""

from __future__ import annotations

import argparse
from functools import reduce
from operator import or_

from pyspark.ml import PipelineModel
from pyspark.ml.functions import vector_to_array
from pyspark.sql import SparkSession
from pyspark.sql import functions as F


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--titanic_data", required=True)
    parser.add_argument("--model_input", required=True)
    parser.add_argument("--model_asset_id", required=True)
    parser.add_argument("--predictions", required=True)
    return parser.parse_args()


def child_uri(base: str, child: str) -> str:
    return f"{base.rstrip('/')}/{child}"


def main() -> None:
    args = parse_args()
    spark = SparkSession.builder.appName("titanic-native-spark-inference").getOrCreate()
    master = spark.sparkContext.master
    if master.lower().startswith("local"):
        raise RuntimeError(f"Native inference requires managed Spark, not {master}")
    if spark.version.split(".")[:2] != ["3", "5"]:
        raise RuntimeError(f"Expected Spark 3.5, found {spark.version}")

    source = (
        spark.read.option("header", True)
        .option("inferSchema", True)
        .csv(args.titanic_data)
    )
    required = {
        "PassengerId", "Pclass", "Sex", "Age", "SibSp", "Parch", "Fare", "Embarked"
    }
    missing = sorted(required.difference(source.columns))
    if missing:
        raise ValueError(f"Titanic inference input is missing columns: {missing}")

    label = F.col("Survived").cast("int") if "Survived" in source.columns else F.lit(None).cast("int")
    prepared = source.select(
        F.element_at(F.split(F.input_file_name(), "/"), -1).alias("source_file"),
        F.col("PassengerId").cast("long").alias("PassengerId"),
        label.alias("actual_label"),
        F.col("Pclass").cast("double").alias("Pclass"),
        F.col("Sex").cast("string").alias("Sex"),
        F.col("Age").cast("double").alias("Age"),
        F.col("SibSp").cast("double").alias("SibSp"),
        F.col("Parch").cast("double").alias("Parch"),
        F.col("Fare").cast("double").alias("Fare"),
        F.col("Embarked").cast("string").alias("Embarked"),
    ).fillna({"Embarked": "Unknown"})

    required_values = ["PassengerId", "Pclass", "Sex", "SibSp", "Parch", "Fare"]
    invalid_conditions = [F.col(name).isNull() for name in required_values]
    invalid_conditions.extend(F.isnan(name) for name in ["Pclass", "SibSp", "Parch", "Fare"])
    invalid_rows = prepared.filter(reduce(or_, invalid_conditions)).count()
    if invalid_rows:
        raise ValueError(f"Input contains {invalid_rows} invalid required-feature rows")

    input_rows = prepared.count()
    if not input_rows or prepared.select("PassengerId").distinct().count() != input_rows:
        raise ValueError("Input must contain nonempty, unique PassengerIds")

    provenance_rows = (
        spark.read.json(child_uri(args.model_input, "registered_model_manifest.json"))
        .select("model_asset_id", "registered_artifact_uri", "content_sha256")
        .collect()
    )
    if len(provenance_rows) != 1 or provenance_rows[0]["model_asset_id"] != args.model_asset_id:
        raise RuntimeError("The staged artifact does not belong to the selected registered model")
    provenance = provenance_rows[0]
    if not provenance["registered_artifact_uri"] or not provenance["content_sha256"]:
        raise RuntimeError("The registered model copy has no artifact provenance")
    model = PipelineModel.load(child_uri(args.model_input, "sparkml-model"))
    predictions = model.transform(prepared).select(
        "source_file",
        "PassengerId",
        F.col("prediction").cast("int").alias("prediction"),
        "actual_label",
        vector_to_array("probability")[1].alias("survival_probability"),
    ).cache()
    output_rows = predictions.count()
    invalid_predictions = predictions.filter(
        F.col("prediction").isNull()
        | ~F.col("prediction").isin(0, 1)
        | F.col("survival_probability").isNull()
        | F.isnan("survival_probability")
        | ~F.col("survival_probability").between(0.0, 1.0)
    ).count()
    if output_rows != input_rows or invalid_predictions:
        raise RuntimeError(
            f"Prediction contract failed: input={input_rows}, output={output_rows}, "
            f"invalid={invalid_predictions}"
        )

    (
        predictions.orderBy("PassengerId")
        .coalesce(1)
        .write.mode("overwrite")
        .option("header", True)
        .csv(child_uri(args.predictions, "csv"))
    )
    spark.range(1).select(
        F.lit(spark.version).alias("spark_version"),
        F.lit(master).alias("spark_master"),
        F.lit(spark.sparkContext.applicationId).alias("spark_application_id"),
        F.lit(args.model_asset_id).alias("model_asset_id"),
        F.lit(args.model_input).alias("model_artifact_uri"),
        F.lit(provenance["registered_artifact_uri"]).alias("registered_artifact_uri"),
        F.lit(provenance["content_sha256"]).alias("model_content_sha256"),
        F.lit(input_rows).alias("input_rows"),
        F.lit(output_rows).alias("output_rows"),
    ).coalesce(1).write.mode("overwrite").json(child_uri(args.predictions, "runtime"))

    print(f"Managed Spark version: {spark.version}")
    print(f"Spark master: {master}")
    print(f"Registered model: {args.model_asset_id}")
    print(f"Input/output rows: {input_rows}/{output_rows}")
    predictions.unpersist()


if __name__ == "__main__":
    main()
