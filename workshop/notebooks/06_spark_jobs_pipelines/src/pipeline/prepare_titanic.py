"""Prepare deterministic Titanic train and test data with Spark."""

from __future__ import annotations

import argparse

from pyspark.sql import SparkSession
from pyspark.sql import functions as F


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw_data", required=True)
    parser.add_argument("--prepared_data", required=True)
    return parser.parse_args()


def child_uri(base: str, child: str) -> str:
    return f"{base.rstrip('/')}/{child}"


def main() -> None:
    args = parse_args()
    spark = SparkSession.builder.appName("titanic-prepare-data").getOrCreate()

    source = (
        spark.read.option("header", True)
        .option("inferSchema", True)
        .csv(args.raw_data)
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
            f"Titanic input is missing required columns: {sorted(missing_columns)}"
        )

    prepared = (
        source.select(
            F.col("PassengerId").cast("long").alias("PassengerId"),
            F.col("Survived").cast("double").alias("label"),
            F.col("Pclass").cast("double").alias("Pclass"),
            F.col("Sex").cast("string").alias("Sex"),
            F.col("Age").cast("double").alias("Age"),
            F.col("SibSp").cast("double").alias("SibSp"),
            F.col("Parch").cast("double").alias("Parch"),
            F.col("Fare").cast("double").alias("Fare"),
            F.col("Embarked").cast("string").alias("Embarked"),
        )
        .fillna({"Embarked": "Unknown"})
        .dropna(subset=["PassengerId", "label", "Pclass", "Sex", "SibSp", "Parch", "Fare"])
    )

    train_data, test_data = prepared.randomSplit([0.8, 0.2], seed=42)
    train_rows = train_data.count()
    test_rows = test_data.count()
    source_rows = source.count()
    prepared_rows = prepared.count()
    if train_rows == 0 or test_rows == 0:
        raise RuntimeError(
            f"Unexpected split row counts: train={train_rows}, test={test_rows}"
        )

    train_data.write.mode("overwrite").parquet(
        child_uri(args.prepared_data, "train")
    )
    test_data.write.mode("overwrite").parquet(
        child_uri(args.prepared_data, "test")
    )
    spark.sql(
        "SELECT "
        f"CAST({source_rows} AS BIGINT) AS source_rows, "
        f"CAST({prepared_rows} AS BIGINT) AS prepared_rows, "
        f"CAST({train_rows} AS BIGINT) AS train_rows, "
        f"CAST({test_rows} AS BIGINT) AS test_rows"
    ).coalesce(1).write.mode("overwrite").json(
        child_uri(args.prepared_data, "summary")
    )

    print(f"Prepared rows: {prepared_rows}")
    print(f"Train rows: {train_rows}")
    print(f"Test rows: {test_rows}")


if __name__ == "__main__":
    main()
