"""Validate Titanic model metrics before model registration."""

from __future__ import annotations

import argparse
import math

from pyspark.sql import SparkSession


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--metrics_input", required=True)
    parser.add_argument("--validation_output", required=True)
    parser.add_argument("--accuracy_threshold", type=float, default=0.70)
    return parser.parse_args()


def child_uri(base: str, child: str) -> str:
    return f"{base.rstrip('/')}/{child}"


def main() -> None:
    args = parse_args()
    spark = SparkSession.builder.appName("titanic-validate-model").getOrCreate()
    metrics = spark.read.json(child_uri(args.metrics_input, "metrics"))
    rows = metrics.select("accuracy", "f1", "area_under_roc", "test_rows").take(2)
    if len(rows) != 1:
        raise RuntimeError(f"Expected one metrics row, found {len(rows)}")

    metric_row = rows[0]
    accuracy = float(metric_row["accuracy"])
    f1 = float(metric_row["f1"])
    area_under_roc = float(metric_row["area_under_roc"])
    test_rows = int(metric_row["test_rows"])
    validated = (
        math.isfinite(accuracy)
        and math.isfinite(f1)
        and math.isfinite(area_under_roc)
        and test_rows > 0
        and accuracy >= args.accuracy_threshold
    )

    spark.sql(
        "SELECT "
        f"CAST({str(validated).lower()} AS BOOLEAN) AS validated, "
        f"CAST({accuracy!r} AS DOUBLE) AS accuracy, "
        f"CAST({f1!r} AS DOUBLE) AS f1, "
        f"CAST({area_under_roc!r} AS DOUBLE) AS area_under_roc, "
        f"CAST({test_rows} AS BIGINT) AS test_rows, "
        f"CAST({args.accuracy_threshold!r} AS DOUBLE) AS accuracy_threshold"
    ).coalesce(1).write.mode("overwrite").json(args.validation_output)

    if not validated:
        raise RuntimeError(
            "model validation failed: "
            f"accuracy={accuracy:.6f}, threshold={args.accuracy_threshold:.6f}"
        )

    print("Model validation passed")
    print(f"Accuracy: {accuracy:.6f}")
    print(f"Accuracy threshold: {args.accuracy_threshold:.6f}")


if __name__ == "__main__":
    main()
