"""
Copy Azure ML job output from blob storage to OneLake.
Run this after the merge job completes successfully.
"""

from azure.ai.ml import MLClient
from azure.identity import DefaultAzureCredential
from azure.storage.filedatalake import DataLakeServiceClient
import pandas as pd
import os
from dotenv import load_dotenv

load_dotenv(override=True)

# Configuration
SUBSCRIPTION_ID = os.environ.get("SUBSCRIPTION_ID", "5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25")
PROD_RESOURCE_GROUP = "rg-aml-ws-prod-cc-01"
PROD_WORKSPACE_NAME = "mlwprodcc01"

# Get the job name from user input
job_name = input("Enter the job name (e.g., orange_glass_ycn796p0cy): ").strip()

print(f"\n📥 Retrieving job output from: {job_name}")

# Create ML Client
ml_client = MLClient(
    DefaultAzureCredential(),
    SUBSCRIPTION_ID,
    PROD_RESOURCE_GROUP,
    PROD_WORKSPACE_NAME
)

# Get the job
job = ml_client.jobs.get(job_name)

if job.status != "Completed":
    print(f"⚠ Warning: Job status is '{job.status}', not 'Completed'")
    proceed = input("Continue anyway? (y/n): ").strip().lower()
    if proceed != 'y':
        exit(0)

# Download the output
print("\n📥 Downloading merged data from Azure ML...")
output_path = ml_client.jobs.download(job_name, download_path="./temp_output", output_name="merged_data")
print(f"✓ Downloaded to: {output_path}")

# Read the CSV file
csv_file = os.path.join(output_path, "named-outputs", "merged_data", "merged_taxi_data.csv")
print(f"\n📖 Reading: {csv_file}")
df = pd.read_csv(csv_file)
print(f"✓ Loaded {len(df)} rows")

# Upload to OneLake
print("\n📤 Uploading to OneLake...")

onelake_endpoint = "https://onelake.dfs.fabric.microsoft.com"
workspace_name = "TechNextWS"
lakehouse_name = "TechNextLH.Lakehouse"

service_client = DataLakeServiceClient(
    account_url=onelake_endpoint,
    credential=DefaultAzureCredential()
)

file_system_client = service_client.get_file_system_client(workspace_name)
directory_client = file_system_client.get_directory_client(
    f"{lakehouse_name}/Files/uploaded_data"
)

# Upload the file
file_client = directory_client.get_file_client("merged_taxi_data.csv")
csv_data = df.to_csv(index=False)
file_client.upload_data(csv_data, overwrite=True)

onelake_path = f"abfss://{workspace_name}@onelake.dfs.fabric.microsoft.com/{lakehouse_name}/Files/uploaded_data/merged_taxi_data.csv"
print(f"✓ Uploaded to OneLake: {onelake_path}")

# Cleanup temp files
import shutil
shutil.rmtree("./temp_output")
print("\n✓ Cleanup complete")
print("\n✅ Data successfully copied from Azure ML to OneLake!")
