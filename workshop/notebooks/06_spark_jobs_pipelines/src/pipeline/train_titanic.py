"""Train and persist a Spark ML Titanic classifier."""

from __future__ import annotations

import argparse

from pyspark.ml import Pipeline
from pyspark.ml.classification import RandomForestClassifier
from pyspark.ml.feature import Imputer, StringIndexer, VectorAssembler
from pyspark.sql import SparkSession


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prepared_data", required=True)
    parser.add_argument("--model_output", required=True)
    return parser.parse_args()


def child_uri(base: str, child: str) -> str:
    return f"{base.rstrip('/')}/{child}"


def main() -> None:
    args = parse_args()
    spark = SparkSession.builder.appName("titanic-train-model").getOrCreate()
    training_data = spark.read.parquet(child_uri(args.prepared_data, "train"))

    imputer = Imputer(
        inputCols=["Age"],
        outputCols=["Age_imputed"],
        strategy="median",
    )
    sex_indexer = StringIndexer(
        inputCol="Sex",
        outputCol="Sex_index",
        handleInvalid="keep",
    )
    embarked_indexer = StringIndexer(
        inputCol="Embarked",
        outputCol="Embarked_index",
        handleInvalid="keep",
    )
    assembler = VectorAssembler(
        inputCols=[
            "Pclass",
            "Sex_index",
            "Age_imputed",
            "SibSp",
            "Parch",
            "Fare",
            "Embarked_index",
        ],
        outputCol="features",
        handleInvalid="keep",
    )
    classifier = RandomForestClassifier(
        labelCol="label",
        featuresCol="features",
        numTrees=100,
        maxDepth=8,
        seed=42,
    )

    pipeline_model = Pipeline(
        stages=[imputer, sex_indexer, embarked_indexer, assembler, classifier]
    ).fit(training_data)
    pipeline_model.write().overwrite().save(
        child_uri(args.model_output, "sparkml-model")
    )

    training_rows = training_data.count()
    spark.sql(
        "SELECT "
        "'SparkML RandomForestClassifier' AS algorithm, "
        "'3.5' AS spark_runtime, "
        f"CAST({training_rows} AS BIGINT) AS training_rows, "
        "CAST(100 AS INT) AS num_trees, "
        "CAST(8 AS INT) AS max_depth"
    ).coalesce(1).write.mode("overwrite").json(
        child_uri(args.model_output, "training-metadata")
    )

    print(f"Training rows: {training_rows}")
    print(f"Model output: {args.model_output}")


if __name__ == "__main__":
    main()
