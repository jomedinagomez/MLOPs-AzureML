"""
Register custom environment with OneLake write support
"""

from azure.ai.ml import MLClient
from azure.ai.ml.entities import Environment
from azure.identity import DefaultAzureCredential
import os
from dotenv import load_dotenv

load_dotenv(override=True)

# Production environment configuration
SUBSCRIPTION_ID = os.environ.get("SUBSCRIPTION_ID", "5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25")
PROD_RESOURCE_GROUP = "rg-aml-ws-prod-cc-01"
PROD_WORKSPACE_NAME = "mlwprodcc01"

print("=" * 80)
print("Register Custom Environment with OneLake Support")
print("=" * 80)

# Create ML Client
ml_client = MLClient(
    DefaultAzureCredential(),
    SUBSCRIPTION_ID,
    PROD_RESOURCE_GROUP,
    PROD_WORKSPACE_NAME
)

print("✓ Connected to production workspace")

# Create environment
env = Environment(
    name="merge_with_onelake",
    description="Custom environment with azure-storage-file-datalake for OneLake write support",
    conda_file="../environment/merge_with_onelake/conda.yaml",
    image="mcr.microsoft.com/azureml/openmpi4.1.0-ubuntu20.04:latest"
)

print("\nRegistering environment...")
print(f"  Name: {env.name}")
print(f"  Conda file: {env.conda_file}")
print(f"  Base image: {env.image}")

# Register the environment
ml_client.environments.create_or_update(env)

print("\n✓ Environment registered successfully!")
print("\nNext steps:")
print("1. Update single-step-merge-job.yaml to use: azureml:merge_with_onelake@latest")
print("2. Re-run the job with: python run_single_step_merge_prod.py")
