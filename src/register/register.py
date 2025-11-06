"""
Azure ML Model Registration Script

PURPOSE:
This script registers MLflow models to Azure ML workspace and optionally to external registry.

REGISTRATION LOGIC:
- If --registry parameter NOT provided: Register to workspace only
- If --registry parameter IS provided: Register to BOTH workspace AND registry

FAILURE BEHAVIOR:
- Uses strict failure handling - any registration failure causes pipeline to fail immediately
- No graceful degradation to ensure all registration issues are caught and addressed
- Provides detailed error messages for troubleshooting specific failure points

COMMON USAGE:
- Workspace only: python register.py --model_input <path> --model_name <name> --compare_output <path> --register_output <path>
- Dual registration: python register.py --model_input <path> --model_name <name> --compare_output <path> --register_output <path> --registry <registry_name>
"""

import argparse
import json
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
parser.add_argument("--registry", type=str, required=False, help="Placeholder to define order")

args = parser.parse_args()

#### Registering model
print("Registering model")

lines = [
    f"Model name: {args.model_name}",
    f"Model path: {args.model_input}",
    f"Model path: {args.registry}",
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

ml_client_workspace = MLClient(credential=credential,subscription_id=ws._subscription_id,resource_group_name=ws._resource_group,workspace_name=ws._workspace_name,)

####

#### Client Getting ML Client
print("Initializing MLclient")

model_name = args.model_name

base_path = Path(args.model_input)
candidate_paths = [
    base_path / "outputs" / "mlflow-model",
    base_path / "mlflow-model",
    base_path,
]

mlflow_model_path = None
for candidate in candidate_paths:
    if (candidate / "MLmodel").exists():
        mlflow_model_path = str(candidate)
        break

if not mlflow_model_path:
    raise SystemExit(
        "Could not locate MLflow model artifacts under the provided model_input. "
        "Ensure the path contains an MLmodel file."
    )

print(mlflow_model_path)
model = Model(
    path=mlflow_model_path,
    name=model_name,
    description="my sample classification model",
    type=AssetTypes.MLFLOW_MODEL,
)
    
output_dir = Path(args.register_output)
output_dir.mkdir(parents=True, exist_ok=True)

workspace_registered_model = None
registry_registered_model = None

# for downloaded file
# model = Model(path="artifact_downloads/outputs/model.pkl", name=model_name)

if args.registry:
    print("Using external registry - will register to both workspace and registry")
    
    """
    DUAL REGISTRATION LOGIC:
    When registry parameter is provided, this script implements strict dual registration:
    1. Register model to workspace first (MUST succeed)
    2. Register model to external registry (MUST succeed)
    
    FAILURE BEHAVIOR:
    - ANY failure in either registration step will cause the pipeline to fail immediately
    - No graceful degradation or fallback behavior
    - Ensures pipeline fails fast on registration issues for immediate attention
    
    COMMON FAILURE SCENARIOS:
    - Workspace registration fails: Usually indicates connectivity or permission issues with workspace
    - Registry client creation fails: Registry doesn't exist or no access permissions
    - Registry access test fails: Identity lacks proper RBAC on registry (needs AzureML Registry User role)
    - Registry registration fails: Model registration logic error or registry storage issues
    """
    
    # Always register to workspace first
    print("Registering model to workspace")
    try:
        model = Model(
            path=mlflow_model_path,
            name=model_name,
            description="my sample classification model",
            type=AssetTypes.MLFLOW_MODEL)

        workspace_registered_model = ml_client_workspace.models.create_or_update(model)
        print("Model successfully registered to workspace")
    except Exception as workspace_error:
        print(f"FAILED: Could not register model to workspace: {workspace_error}")
        raise workspace_error
    
    # Then register to external registry (both must succeed)
    print(f"Attempting to register model to external registry: {args.registry}")
    try:
        ml_client_registry = MLClient(credential=credential, registry_name=args.registry)
        
        # Test registry access by trying to list models (this will fail if no permissions)
        try:
            # Use simple list() without parameters to test access
            list(ml_client_registry.models.list())
            print(f"Registry {args.registry} accessible, registering model to registry")
        except Exception as registry_access_error:
            print(f"FAILED: Cannot access registry {args.registry}: {registry_access_error}")
            raise registry_access_error
            
        # If access test passed, register the model
        try:
            # CRITICAL: Must create a NEW Model object for registry registration
            # Cannot reuse the model object from workspace registration because:
            # 1. Model objects become "bound" to their target context after first use
            # 2. The workspace model contains workspace-specific URL paths (azureml://subscriptions/.../workspaces/<workspace>)
            # 3. Registry expects registry-specific paths, not workspace paths
            # 4. Reusing causes "workspaces/None" invalid URL errors in registry operations
            # Solution: Always create fresh Model objects for each registration target
            model_for_registry = Model(
                path=mlflow_model_path,
                name=model_name,
                description="my sample classification model",
                type=AssetTypes.MLFLOW_MODEL)
                    
            registry_registered_model = ml_client_registry.models.create_or_update(model_for_registry)
            print("Model successfully registered to both workspace and registry")
        except Exception as registry_registration_error:
            print(f"FAILED: Could not register model to registry: {registry_registration_error}")
            raise registry_registration_error
            
    except Exception as client_error:
        print(f"FAILED: Could not create registry client for {args.registry}: {client_error}")
        raise client_error
        
else:
    print("No external registry provided - registering to workspace only")
    
    """
    SINGLE REGISTRATION LOGIC:
    When no registry parameter is provided, register only to workspace.
    
    FAILURE BEHAVIOR:
    - Workspace registration failure will cause pipeline to fail immediately
    - Ensures all model registration attempts are explicit and traceable
    """
    
    try:
        workspace_registered_model = ml_client_workspace.models.create_or_update(model)
        print("Model successfully registered to workspace")
    except Exception as workspace_error:
        print(f"FAILED: Could not register model to workspace: {workspace_error}")
        raise workspace_error

metadata = {
    "model_name": model_name,
    "workspace_version": getattr(workspace_registered_model, "version", None),
    "registry_version": getattr(registry_registered_model, "version", None),
}

with open(output_dir / "model_versions.json", "w", encoding="utf-8") as metadata_file:
    json.dump(metadata, metadata_file)

with open(output_dir / "register.txt", "a", encoding="utf-8") as f:
    f.write("Model Registered:")
