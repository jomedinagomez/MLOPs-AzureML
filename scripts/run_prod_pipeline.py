"""Submit the production end-to-end Azure ML pipeline.

This helper lets you run `pipelines/prod-e2e-pipeline.yaml` from a local workstation
or CI job without duplicating Azure CLI logic. It relies on default Azure
credentials, so make sure one of the supported credential types (service
principal, managed identity, Azure CLI login, etc.) is available in the
current environment.
"""

from __future__ import annotations

import argparse
import os
from typing import Any, Dict

from azure.identity import DefaultAzureCredential
from azure.ai.ml import MLClient, load_job
from azure.ai.ml.entities import PipelineJob
from azure.core.exceptions import HttpResponseError


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Submit the prod e2e Azure ML pipeline")
    parser.add_argument(
        "--subscription-id",
        default=os.getenv("AZURE_SUBSCRIPTION_ID"),
        help="Azure subscription ID (defaults to AZURE_SUBSCRIPTION_ID env var)",
    )
    parser.add_argument(
        "--resource-group",
        default=os.getenv("PROD_RESOURCE_GROUP", os.getenv("AML_PROD_RESOURCE_GROUP")),
        required=False,
        help="Resource group that hosts the prod workspace (env fallback: PROD_RESOURCE_GROUP)",
    )
    parser.add_argument(
        "--workspace-name",
        default=os.getenv("PROD_WORKSPACE_NAME", os.getenv("AML_PROD_WORKSPACE")),
        required=False,
        help="Production AML workspace name (env fallback: PROD_WORKSPACE_NAME)",
    )
    parser.add_argument(
        "--job-yaml",
        required=True,
        help="Path to the pipeline YAML file to run",
    )
    parser.add_argument(
        "--environment",
        default=os.getenv("PIPELINE_ENVIRONMENT", "prod"),
        help="Value for the pipeline's `environment` input (default: prod)",
    )
    parser.add_argument(
        "--model-base",
        default=os.getenv("PIPELINE_MODEL_BASE", "taxi-class"),
        help="Value for the `model_base` input",
    )
    parser.add_argument(
        "--artifact-id",
        default=os.getenv("PIPELINE_ARTIFACT_ID", "m"),
        help="Value for the `artifact_id` input",
    )
    parser.add_argument(
        "--deployment-name",
        default=os.getenv("PIPELINE_DEPLOYMENT_NAME", "green"),
        help="Value for the `deployment_name` input",
    )
    parser.add_argument(
        "--registry",
        default=os.getenv("PROD_REGISTRY_NAME", os.getenv("AML_PROD_REGISTRY")),
        help="Registry name to pass into the pipeline",
    )
    parser.add_argument(
        "--automl-compute",
        default=os.getenv("PROD_AUTOML_COMPUTE", "aml-cluster-prod-cc01"),
        help="Compute cluster for AutoML training in the pipeline",
    )
    parser.add_argument(
        "--conda-file",
        default=os.getenv("PIPELINE_CONDA_FILE", "custom_prod.yaml"),
        help="Conda file reference for the create_env step",
    )
    parser.add_argument(
        "--default-compute",
        default=os.getenv("PIPELINE_DEFAULT_COMPUTE", "azureml:aml-cluster-prod-cc01"),
        help="Override the pipeline's default compute target",
    )
    parser.add_argument(
        "--stream-logs",
        action="store_true",
        help="If set, stream pipeline logs until completion",
    )
    parser.add_argument(
        "--force-rerun",
        action="store_true",
        help="Set pipeline settings.force_rerun to true",
    )
    return parser.parse_args()


def apply_input_overrides(job: PipelineJob, args: argparse.Namespace) -> None:
    overrides: Dict[str, Any] = {
        "environment": args.environment,
        "model_base": args.model_base,
        "artifact_id": args.artifact_id,
        "deployment_name": args.deployment_name,
        "registry": args.registry,
        "automl_compute": args.automl_compute,
        "conda_file": args.conda_file,
    }

    for key, value in overrides.items():
        if value is not None:
            if key not in job.inputs:
                raise ValueError(f"Pipeline input '{key}' not found in {args.job_yaml}")
            job.inputs[key] = value

    if args.default_compute:
        job.settings.default_compute = args.default_compute
    if args.force_rerun:
        job.settings.force_rerun = True


def main() -> None:
    args = parse_args()

    missing = [
        name
        for name, value in (
            ("subscription", args.subscription_id),
            ("resource group", args.resource_group),
            ("workspace", args.workspace_name),
        )
        if not value
    ]
    if missing:
        raise SystemExit(f"Missing required arguments: {', '.join(missing)}")

    credential = DefaultAzureCredential(exclude_interactive_browser_credential=True)
    ml_client = MLClient(
        credential=credential,
        subscription_id=args.subscription_id,
        resource_group_name=args.resource_group,
        workspace_name=args.workspace_name,
    )

    job = load_job(source=args.job_yaml)
    apply_input_overrides(job, args)

    print("Submitting pipeline job ...")
    try:
        submitted_job = ml_client.jobs.create_or_update(job)
    except HttpResponseError as exc:
        raise SystemExit(f"Failed to submit pipeline: {exc}") from exc

    print(f"Job submitted: {submitted_job.name}")
    if submitted_job.services and "Studio" in submitted_job.services:
        print(f"Studio link: {submitted_job.services['Studio'].endpoint}")

    if args.stream_logs:
        print("Streaming logs ...\n")
        ml_client.jobs.stream(submitted_job.name)


if __name__ == "__main__":
    main()
