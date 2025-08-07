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

parser = argparse.ArgumentParser("deploy")
parser.add_argument("--model_name", type=str, help="Model_name_to_register")
parser.add_argument("--endpoint_name", type=str, help="Name of Endpoint")
parser.add_argument("--deployment_name", type=str, help="Name of Deployment")
parser.add_argument("--register_job_status", type=str, help="Name of score report")
parser.add_argument("--registry", type=str, required=False, help="Registry name to get model from")

args = parser.parse_args()

#### Registering model
print("Registering model")

lines = [
    f"Model name: {args.model_name}",
    f"Endpoint name: {args.endpoint_name}",
    f"Deployment name: {args.deployment_name}"
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
print("Model Name: ", model_name)

# Determine which client to use for model retrieval
if args.registry:
    print(f"Using external registry: {args.registry}")
    # Create registry client for model retrieval
    ml_client_model = MLClient(credential=credential, registry_name=args.registry)
    print(f"Getting model from registry: {args.registry}")
else:
    print("Using workspace for model retrieval")
    # Use workspace client for model retrieval
    ml_client_model = ml_client

# Let's pick the latest version of the model
latest_model_version = max(
    [int(m.version) for m in ml_client_model.models.list(name=model_name)]
)

print("Latest Model Version: ", latest_model_version)

model = ml_client_model.models.get(name=model_name, version=latest_model_version)

# define an online endpoint
endpoint = ManagedOnlineEndpoint(
    name=args.endpoint_name,
    description="this is an online endpoint",
    auth_mode="key",
    tags={
        "training_dataset": "credit_defaults",
    },
)

# create the online endpoint
# expect the endpoint to take approximately 2 minutes.

print("Creating Endpoint")
endpoint = ml_client.online_endpoints.begin_create_or_update(endpoint).result()

endpoint = ml_client.online_endpoints.get(name=args.endpoint_name)

print(
    f'Endpoint "{endpoint.name}" with provisioning state "{endpoint.provisioning_state}" is retrieved'
)

###Creating Deployment
deployment = ManagedOnlineDeployment(
    name=args.deployment_name,
    endpoint_name=args.endpoint_name,
    model=model,
    instance_type="Standard_F8S_V2",
    instance_count=1,
    liveness_probe=ProbeSettings(
        failure_threshold=30,
        success_threshold=1,
        timeout=2,
        period=10,
        initial_delay=2000,
    ),
    readiness_probe=ProbeSettings(
        failure_threshold=10,
        success_threshold=1,
        timeout=10,
        period=10,
        initial_delay=2000,
    ),
)

ml_client.online_deployments.begin_create_or_update(deployment).result()

print("Deployment Created")

# bankmarketing deployment to take 100% traffic
endpoint.traffic = {args.deployment_name: 100}
ml_client.begin_create_or_update(endpoint)