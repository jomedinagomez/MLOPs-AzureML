import argparse
import pandas as pd
import os
from pathlib import Path
from sklearn.linear_model import LinearRegression
import mlflow
import mltable
from azure.ai.ml.constants import AssetTypes

# import required libraries
from azure.ai.ml.entities import (
    ManagedOnlineEndpoint,
    ManagedOnlineDeployment,
    Model,
    Environment,
    CodeConfiguration,
    ProbeSettings,
)
from azure.ai.ml.constants import ModelType


mlflow.sklearn.autolog()


parser = argparse.ArgumentParser("register")
parser.add_argument("--model_input", type=str, help="Path of input model")
parser.add_argument("--model_name", type=str, help="Model_name_to_register")
parser.add_argument("--compare_output", type=str, help="Placeholder to define order")
parser.add_argument("--register_output", type=str, help="Placeholder to define order")

args = parser.parse_args()

#### Registering model
print("Registering model")

lines = [
    f"Model name: {args.model_name}",
    f"Model path: {args.model_input}",
    f"Model path: {args.compare_output}",
    f"Model path: {args.register_output}",
]

for line in lines:
    print(line)

#### Client Getting ML Client
print("Initializing MLclient")
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

#### Client Getting ML Client
print("Initializing MLclient")

model_name = args.model_name
mlflow_model_path = str(Path(args.model_input) / "outputs")+"/"+"mlflow-model"
arr = os.listdir(mlflow_model_path)

print(mlflow_model_path)
model = Model(
    path=mlflow_model_path,
    name=model_name,
    description="my sample classification model",
    type=AssetTypes.MLFLOW_MODEL,
)

# for downloaded file
# model = Model(path="artifact_downloads/outputs/model.pkl", name=model_name)

registered_model = ml_client.models.create_or_update(model)

with open((Path(args.register_output) / "register.txt"), "a") as f:
    f.write("Model Registered:")
