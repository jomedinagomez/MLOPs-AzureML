"""
Run the single-step merge job in the production environment.
This script submits the merge job to the prod workspace.
"""

from azure.ai.ml import MLClient, load_job
from azure.identity import DefaultAzureCredential
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv(override=True)

# Production environment configuration
SUBSCRIPTION_ID = os.environ.get("SUBSCRIPTION_ID", "5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25")
PROD_RESOURCE_GROUP = "rg-aml-ws-prod-cc-01"
PROD_WORKSPACE_NAME = "mlwprodcc01"

print("=" * 80)
print("Single-Step Merge Job - Production Deployment")
print("=" * 80)
print(f"Subscription: {SUBSCRIPTION_ID}")
print(f"Resource Group: {PROD_RESOURCE_GROUP}")
print(f"Workspace: {PROD_WORKSPACE_NAME}")
print("=" * 80)

# Create ML Client for production workspace
ml_client = MLClient(
    DefaultAzureCredential(),
    SUBSCRIPTION_ID,
    PROD_RESOURCE_GROUP,
    PROD_WORKSPACE_NAME
)

print("✓ Connected to production workspace")

# Load the job YAML
job = load_job(source="./single-step-merge-job.yaml")

print(f"\nJob Configuration:")
print(f"  Command: {job.command}")
print(f"  Compute: {job.compute}")
print(f"  Environment: {job.environment}")
print(f"  Output: {job.outputs['merged_data']}")

# Submit the job
print("\n⏳ Submitting job to production...")
returned_job = ml_client.jobs.create_or_update(job)

print(f"\n✓ Job submitted successfully!")
print(f"Job Name: {returned_job.name}")
print(f"Job Status: {returned_job.status}")
print(f"\nStudio URL: {returned_job.studio_url}")
print("\nℹ Monitor the job progress in Azure ML Studio")
