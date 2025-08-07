#!/usr/bin/env python3

"""
Submit the taxi fare training pipeline to Azure ML
"""

from azure.ai.ml import MLClient
from azure.ai.ml.entities import Job
from azure.ai.ml import load_job
from azure.identity import DefaultAzureCredential
import yaml
import os

def main():
    # Initialize the ML Client
    credential = DefaultAzureCredential()
    
    ml_client = MLClient(
        credential=credential,
        subscription_id="5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25",
        resource_group_name="rg-aml-ws-dev-cc",
        workspace_name="amldevcc004"
    )
    
    # Load and submit the pipeline
    pipeline_file = "pipelines/taxi-fare-train-pipeline.yaml"
    
    try:
        # Load the pipeline using the correct method that preserves relative paths
        pipeline_job = load_job(source=pipeline_file)
        
        print(f"Submitting pipeline from {pipeline_file}")
        print(f"Pipeline name: {pipeline_job.name if hasattr(pipeline_job, 'name') else 'Not set'}")
        print(f"Pipeline experiment: {pipeline_job.experiment_name if hasattr(pipeline_job, 'experiment_name') else 'Not set'}")
        
        # Submit the pipeline
        submitted_job = ml_client.jobs.create_or_update(pipeline_job)
        
        print(f"Pipeline submitted successfully!")
        print(f"Job name: {submitted_job.name}")
        print(f"Job status: {submitted_job.status}")
        print(f"Studio URL: {submitted_job.studio_url}")
        
        return submitted_job
        
    except Exception as e:
        print(f"Error submitting pipeline: {str(e)}")
        raise

if __name__ == "__main__":
    main()
