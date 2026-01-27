# Run OneLake Pipeline
from azure.identity import DefaultAzureCredential
from azure.ai.ml import MLClient, load_job
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv(override=True)

SUBSCRIPTION_ID = os.environ["SUBSCRIPTION_ID"]
RESOURCE_GROUP = os.environ["DEV_RESOURCE_GROUP"]
AML_WORKSPACE_NAME = os.environ["DEV_WORKSPACE_NAME"]

# Create ML Client
ml_client = MLClient(
    DefaultAzureCredential(), 
    SUBSCRIPTION_ID, 
    RESOURCE_GROUP, 
    AML_WORKSPACE_NAME
)

# Load the pipeline job from YAML
pipeline_job = load_job(source="./OneLakePipeline.yaml")

# Submit the pipeline job
submitted_job = ml_client.jobs.create_or_update(
    pipeline_job,
    experiment_name="OneLakeDataOperation-dev"
)

print(f"Pipeline job submitted!")
print(f"Job name: {submitted_job.name}")
print(f"Job status: {submitted_job.status}")
print(f"Studio URL: {submitted_job.studio_url}")

# Optional: Stream the job logs
# ml_client.jobs.stream(submitted_job.name)
