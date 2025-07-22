import argparse
from pathlib import Path
from uuid import uuid4
from datetime import datetime
import os
import pandas as pd
from sklearn.linear_model import LinearRegression
from sklearn.model_selection import train_test_split
import mlflow
import mltable
import mlflow
from mlflow.tracking.client import MlflowClient
from mlflow.artifacts import download_artifacts

# Import required libraries
import os

from azure.ai.ml.constants import AssetTypes
from azure.ai.ml.entities import Data
from azure.ai.ml.automl import (
    classification,
    ClassificationPrimaryMetrics,
    ClassificationModels,
)


#### Client Getting ML Client
from azure.identity import DefaultAzureCredential,ManagedIdentityCredential,AzureCliCredential
from azure.ai.ml import automl, Input, MLClient, command
from azureml.core.run import Run

msi_client_id = os.environ.get("DEFAULT_IDENTITY_CLIENT_ID")
credential = ManagedIdentityCredential(client_id=msi_client_id)
credential.get_token("https://management.azure.com/.default")
run = Run.get_context(allow_offline=False)
ws = run.experiment.workspace
ml_client = MLClient(credential=credential,subscription_id=ws._subscription_id,resource_group_name=ws._resource_group,workspace_name=ws._workspace_name,)
####


#### Retreiving AutoML Config

from azure.ai.ml.entities import AmlCompute
from azure.core.exceptions import ResourceNotFoundError
compute_name = "cpu-cluster-uami"
_ = ml_client.compute.get(compute_name)
print("Found existing compute target.")
####

mlflow.sklearn.autolog()

parser = argparse.ArgumentParser("train")
parser.add_argument("--training_data", type=str, help="Path to training data")
parser.add_argument("--test_data", type=str, help="Path to test data")
parser.add_argument("--model_output", type=str, help="Path of output model")
parser.add_argument("--model_name", type=str, help="Model name")


args = parser.parse_args()

print("hello training world...")

lines = [
    f"Training data path: {args.training_data}",
    f"Test data path: {args.test_data}",
    f"Model output path: {args.model_output}",
    f"Test split ratio:{args.model_name}",
]

# Training MLTable defined locally, with local data to be uploaded
my_training_data_input = Input(
    type=AssetTypes.MLTABLE, path=str(Path(args.training_data))
)

####
# General job parameters
max_trials = 2
exp_name = "Taxi-Regression-AutoML-Job-subrun"

#https://github.com/Azure/azureml-examples/blob/main/sdk/python/jobs/automl-standalone-jobs/automl-classification-task-bankmarketing/automl-classification-task-bankmarketing.ipynb
#https://github.com/Azure/azureml-examples/blob/main/sdk/python/jobs/automl-standalone-jobs/automl-regression-task-hardware-performance/automl-regression-task-hardware-performance.ipynb
# Create the AutoML Regression job with the related factory-function.

classification_job = automl.classification(
    compute=compute_name,
    experiment_name=exp_name,
    training_data=my_training_data_input,
    target_column_name="cost",
    primary_metric="accuracy",
    n_cross_validations=2,
    enable_model_explainability=True,
    tags={"test": "My custom value"},
)

# Limits are all optional
classification_job.set_limits(
    timeout_minutes=600,
    trial_timeout_minutes=20,
    max_trials=max_trials,
    enable_early_termination=True,
)

# Training properties are optional
classification_job.set_training(
    enable_onnx_compatible_models=True,
    enable_stack_ensemble=False,
    EnableVoteEnsemble=False,
)

### Run Command

# Submit the AutoML job
returned_job = ml_client.jobs.create_or_update(classification_job)  # submit the job to the backend

print(f"Created job: {returned_job}")

# Wait until the AutoML job is finished
ml_client.jobs.stream(returned_job.name)

# Get a URL for the status of the job
returned_job.services["Studio"].endpoint
print(returned_job.name)


###Obtain the tracking URI for MLFlow

# Obtain the tracking URL from MLClient
MLFLOW_TRACKING_URI = ml_client.workspaces.get(
    name=ml_client.workspace_name
).mlflow_tracking_uri

print(MLFLOW_TRACKING_URI)

# Set the MLFLOW TRACKING URI

mlflow.set_tracking_uri(MLFLOW_TRACKING_URI)

print("\nCurrent tracking uri: {}".format(mlflow.get_tracking_uri()))

# Initialize MLFlow client
mlflow_client = MlflowClient()

job_name = returned_job.name

# Example if providing an specific Job name/ID
# job_name = "b4e95546-0aa1-448e-9ad6-002e3207b4fc"

# Get the parent run
mlflow_parent_run = mlflow_client.get_run(job_name)

print("Parent Run: ")
print(mlflow_parent_run)

# Print parent run tags. 'automl_best_child_run_id' tag should be there.
print(mlflow_parent_run.data.tags)

# Get the best model's child run

best_child_run_id = mlflow_parent_run.data.tags["automl_best_child_run_id"]
print("Found best child run id: ", best_child_run_id)

best_run = mlflow_client.get_run(best_child_run_id)

print("Best child run: ")
print(best_run)

best_run.data.metrics

#Download best model locally
local_path = download_artifacts(
    run_id=best_run.info.run_id, artifact_path="outputs", dst_path=args.model_output
)
print("Artifacts downloaded in: {}".format(local_path))
print("Artifacts: {}".format(os.listdir(local_path)))