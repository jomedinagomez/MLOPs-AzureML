import argparse
import os
from azure.identity import ManagedIdentityCredential
from azure.ai.ml import MLClient
from azure.ai.ml.entities import Environment
from azureml.core.run import Run

parser = argparse.ArgumentParser("create_env")
parser.add_argument("--env_name", type=str, required=True, help="Name of the environment to create")
parser.add_argument("--conda_file", type=str, required=True, help="Path to the conda.yaml file to use for the new AzureML environment")
parser.add_argument("--env_status", type=str, required=False, help="Dummy output folder for dependency enforcement")
args = parser.parse_args()


print(f"Creating environment: {args.env_name}")
print(f"conda_file argument received: {args.conda_file}")
print("Current working directory:", os.getcwd())
print("Directory contents:", os.listdir(os.getcwd()))
if os.path.exists(args.conda_file):
    print(f"conda_file exists at: {args.conda_file}")
else:
    print(f"conda_file NOT FOUND at: {args.conda_file}")

# Authenticate using Managed Identity (pattern from deploy.py)
msi_client_id = os.environ.get("DEFAULT_IDENTITY_CLIENT_ID")
credential = ManagedIdentityCredential(client_id=msi_client_id)
credential.get_token("https://management.azure.com/.default")
run = Run.get_context(allow_offline=False)
ws = run.experiment.workspace
ml_client = MLClient(credential=credential, subscription_id=ws._subscription_id, resource_group_name=ws._resource_group, workspace_name=ws._workspace_name)

# Create the environment (simple Python base, can be customized)
conda_file_path = os.path.join(os.path.dirname(__file__), args.conda_file)
print(f"Resolved conda_file_path: {conda_file_path}")
if not os.path.exists(conda_file_path):
    print(f"ERROR: Conda file does not exist at {conda_file_path}")
    exit(1)
env = Environment(
    name=args.env_name,
    image="mcr.microsoft.com/azureml/openmpi4.1.0-ubuntu20.04:20231023.v1",
    conda_file=conda_file_path,
    description="Taxi classification production environment"
)

ml_client.environments.create_or_update(env)
print(f"Environment '{args.env_name}' created or updated.")

# Write dummy output for dependency enforcement
if args.env_status:
    os.makedirs(args.env_status, exist_ok=True)
    with open(os.path.join(args.env_status, "done.txt"), "w") as f:
        f.write("Environment creation complete.")
    with open(os.path.join(args.env_status, "env_log.txt"), "w") as logf:
        logf.write(f"Environment name: {args.env_name}\n")
        logf.write("Environment created successfully.\n")
