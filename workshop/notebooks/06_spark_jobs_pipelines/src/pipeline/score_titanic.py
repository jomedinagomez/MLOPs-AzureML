"""Score held-out Titanic data and persist model metrics."""

from __future__ import annotations

import argparse

from pyspark.ml import PipelineModel
from pyspark.ml.evaluation import (
    BinaryClassificationEvaluator,
    MulticlassClassificationEvaluator,
)
from pyspark.sql import SparkSession


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prepared_data", required=True)
    parser.add_argument("--model_input", required=True)
    parser.add_argument("--metrics_output", required=True)
    return parser.parse_args()


def child_uri(base: str, child: str) -> str:
    return f"{base.rstrip('/')}/{child}"


def main() -> None:
    args = parse_args()
    spark = SparkSession.builder.appName("titanic-score-test-data").getOrCreate()
    test_data = spark.read.parquet(child_uri(args.prepared_data, "test"))
    model = PipelineModel.load(child_uri(args.model_input, "sparkml-model"))
    predictions = model.transform(test_data).cache()

    accuracy = MulticlassClassificationEvaluator(
        labelCol="label",
        predictionCol="prediction",
        metricName="accuracy",
    ).evaluate(predictions)
    f1 = MulticlassClassificationEvaluator(
        labelCol="label",
        predictionCol="prediction",
        metricName="f1",
    ).evaluate(predictions)
    area_under_roc = BinaryClassificationEvaluator(
        labelCol="label",
        rawPredictionCol="rawPrediction",
        metricName="areaUnderROC",
    ).evaluate(predictions)
    test_rows = predictions.count()

    if accuracy < 0.70:
        raise RuntimeError(f"Accuracy {accuracy:.4f} is below the 0.70 threshold")

    spark.sql(
        "SELECT "
        f"CAST({float(accuracy)!r} AS DOUBLE) AS accuracy, "
        f"CAST({float(f1)!r} AS DOUBLE) AS f1, "
        f"CAST({float(area_under_roc)!r} AS DOUBLE) AS area_under_roc, "
        f"CAST({test_rows} AS BIGINT) AS test_rows"
    ).coalesce(1).write.mode("overwrite").json(
        child_uri(args.metrics_output, "metrics")
    )
    (
        predictions.select("PassengerId", "label", "prediction", "probability")
        .write.mode("overwrite")
        .parquet(child_uri(args.metrics_output, "predictions"))
    )

    print(f"Test rows: {test_rows}")
    print(f"Accuracy: {accuracy:.6f}")
    print(f"F1: {f1:.6f}")
    print(f"Area under ROC: {area_under_roc:.6f}")


if __name__ == "__main__":
    main()
