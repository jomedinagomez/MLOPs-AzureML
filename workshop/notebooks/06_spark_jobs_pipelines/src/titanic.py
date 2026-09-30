"""Wrangle Titanic data with Azure ML serverless Spark.

Adapted from Azure/azureml-examples at commit
86d53a35d2ecc33ff40c669cc1389b06899e5a4b.
"""

from __future__ import annotations

import argparse

from pyspark.ml.feature import Imputer
from pyspark.sql import SparkSession


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--titanic_data", required=True)
    parser.add_argument("--wrangled_data", required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    spark = SparkSession.builder.appName("workshop-titanic-wrangling").getOrCreate()

    source = (
        spark.read.option("header", True)
        .option("inferSchema", True)
        .csv(args.titanic_data)
    )

    required_columns = {"PassengerId", "Age", "Cabin"}
    missing_columns = required_columns.difference(source.columns)
    if missing_columns:
        raise ValueError(
            f"Titanic input is missing required columns: {sorted(missing_columns)}"
        )

    imputer = Imputer(inputCols=["Age"], outputCols=["Age"]).setStrategy("mean")
    wrangled = imputer.fit(source).transform(source)
    wrangled = wrangled.fillna({"Cabin": "None"}).dropna()

    input_rows = source.count()
    output_rows = wrangled.count()
    if output_rows == 0 or output_rows > input_rows:
        raise RuntimeError(
            f"Unexpected row counts: input={input_rows}, output={output_rows}"
        )

    print(f"Input rows: {input_rows}")
    print(f"Output rows: {output_rows}")
    wrangled.printSchema()

    (
        wrangled.orderBy("PassengerId")
        .write.mode("overwrite")
        .option("header", True)
        .csv(args.wrangled_data)
    )


if __name__ == "__main__":
    main()
