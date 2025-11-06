import argparse
import json
import os
from typing import Dict

from azure.ai.ml import MLClient
from azure.ai.ml.entities import (
    ManagedOnlineDeployment,
    ManagedOnlineEndpoint,
    ProbeSettings,
    DataCollector,
    DeploymentCollection,
)
from azure.core.exceptions import ResourceNotFoundError
from azure.identity import ManagedIdentityCredential
from azureml.core.run import Run


parser = argparse.ArgumentParser("deploy")
parser.add_argument("--model_name", type=str, help="Model_name_to_register")
parser.add_argument("--endpoint_name", type=str, help="Name of Endpoint")
parser.add_argument("--deployment_name", type=str, required=False, help="Name of Deployment")
parser.add_argument("--deployment_name_file", type=str, required=False, help="File containing deployment slot name to use")
parser.add_argument("--default_slot", type=str, required=False, help="Fallback slot name when no deployment exists")
parser.add_argument("--register_job_status", type=str, required=False, help="Placeholder for enforcing dependency ordering")
parser.add_argument("--registry", type=str, required=False, help="Registry name to get model from")
parser.add_argument("--model_version", type=str, required=False, help="Specific model version to deploy")
parser.add_argument("--deploy_status", type=str, required=False, help="Dummy output folder for dependency enforcement")
parser.add_argument(
    "--initial_traffic_percent",
    type=int,
    required=False,
    default=None,
    help="Initial traffic percentage for the new deployment when no previous deployment exists",
)

args = parser.parse_args()


def _read_slot_from_file(path: str) -> str:
    if not path:
        return ""
    if not os.path.exists(path):
        print(f"Deployment name file {path} not found; ignoring")
        return ""
    with open(path, "r", encoding="utf-8") as handle:
        value = handle.read().strip()
    if not value:
        print("Deployment name file was empty; ignoring")
    return value


def _list_models(client: MLClient, name: str):
    return list(client.models.list(name=name))


def _select_latest_model(models):
    if not models:
        return None

    def _version_key(model):
        version = str(model.version)
        try:
            return (0, int(version))
        except (ValueError, TypeError):
            return (1, version)

    return max(models, key=_version_key)


preferred_slot = (args.deployment_name or "").strip()
file_slot = _read_slot_from_file(args.deployment_name_file)
default_slot = (args.default_slot or "").strip() or "blue"

resolved_slot = preferred_slot or file_slot or default_slot

#### Registering model
print("Registering model")

lines = [
    f"Model name: {args.model_name}",
    f"Endpoint name: {args.endpoint_name}",
    f"Requested deployment name: {preferred_slot}",
    f"Deployment name file: {args.deployment_name_file}",
    f"Resolved deployment slot: {resolved_slot}",
]

for line in lines:
    print(line)

#### Client Getting ML Client
print("Initializing MLclient")

msi_client_id = os.environ.get("DEFAULT_IDENTITY_CLIENT_ID")
credential = ManagedIdentityCredential(client_id=msi_client_id)
credential.get_token("https://management.azure.com/.default")
run = Run.get_context(allow_offline=False)
ws = run.experiment.workspace
ml_client = MLClient(
    credential=credential,
    subscription_id=ws._subscription_id,
    resource_group_name=ws._resource_group,
    workspace_name=ws._workspace_name,
)
####

model_name = args.model_name
print("Model Name: ", model_name)

# Determine which client to use for model retrieval
if args.registry:
    print(f"Using external registry: {args.registry}")
    ml_client_model = MLClient(credential=credential, registry_name=args.registry)
    print(f"Getting model from registry: {args.registry}")
else:
    print("Using workspace for model retrieval")
    ml_client_model = ml_client

model_source_client = ml_client_model
target_version = (args.model_version or "").strip()

if target_version:
    print(f"Requested model version: {target_version}")
    try:
        model = model_source_client.models.get(name=model_name, version=target_version)
        latest_model_version = str(model.version)
        print(f"Found model version {latest_model_version} using primary source")
    except ResourceNotFoundError:
        if args.registry:
            print("Requested version not found in registry; trying workspace fallback")
            try:
                model_source_client = ml_client
                model = model_source_client.models.get(name=model_name, version=target_version)
                latest_model_version = str(model.version)
                print(f"Found version {latest_model_version} in workspace")
            except ResourceNotFoundError as exc:
                raise SystemExit(
                    "Specified model version was not found in registry or workspace. "
                    "Verify the integration pipeline successfully registered the model."
                ) from exc
        else:
            raise SystemExit(
                "Specified model version was not found in the workspace. "
                "Verify the integration pipeline successfully registered the model."
            )
else:
    models = _list_models(model_source_client, model_name)

    if not models and args.registry:
        print("No models found in registry; trying workspace fallback")
        model_source_client = ml_client
        models = _list_models(model_source_client, model_name)

    latest_model = _select_latest_model(models)

    if latest_model is None:
        raise SystemExit(
            "No registered model versions found in registry or workspace. "
            "Run the training/register pipeline before deploying."
        )

    latest_model_version = str(latest_model.version)

    print("Latest Model Version: ", latest_model_version)

    model = model_source_client.models.get(name=model_name, version=latest_model_version)

print("Selected Model Version: ", latest_model_version)

# Helper to ensure dictionary sums to 100
def _normalize_distribution(distribution: Dict[str, int]) -> Dict[str, int]:
    total = sum(distribution.values())
    if total == 100:
        return distribution
    if not distribution:
        return distribution
    diff = 100 - total
    # adjust the max entry to absorb rounding differences
    max_key = max(distribution, key=lambda k: distribution[k])
    distribution[max_key] += diff
    return distribution

try:
    endpoint = ml_client.online_endpoints.get(name=args.endpoint_name)
    print(
        f'Endpoint "{endpoint.name}" found with provisioning state "{endpoint.provisioning_state}"'
    )
except ResourceNotFoundError:
    print("Endpoint not found. Creating a new endpoint.")
    endpoint = ManagedOnlineEndpoint(
        name=args.endpoint_name,
        description="this is an online endpoint",
        auth_mode="key",
        tags={
            "training_dataset": "credit_defaults",
        },
    )
    endpoint = ml_client.online_endpoints.begin_create_or_update(endpoint).result()
    endpoint = ml_client.online_endpoints.get(name=args.endpoint_name)

previous_traffic = endpoint.traffic or {}
print(f"Existing traffic configuration: {previous_traffic}")

###Creating Deployment
collections = {
    "model_inputs": DeploymentCollection(enabled=True),
    "model_outputs": DeploymentCollection(enabled=True),
}

data_collector = DataCollector(collections=collections, sampling_rate=1.0)

deployment = ManagedOnlineDeployment(
    name=resolved_slot,
    endpoint_name=args.endpoint_name,
    model=model,
    instance_type="Standard_F8S_V2",
    instance_count=1,
    data_collector=data_collector,
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

print("Deployment created or updated")

updated_traffic = previous_traffic.copy()
if previous_traffic:
    print("Prior deployment detected. Keeping previous traffic weights and initializing new deployment at 0% for validation.")
    updated_traffic[resolved_slot] = 0
else:
    initial_percent = args.initial_traffic_percent
    if initial_percent is None:
        initial_percent = 100
    print(f"No prior deployment found. Assigning {initial_percent}% traffic to the new deployment.")
    updated_traffic = {resolved_slot: initial_percent}

updated_traffic = _normalize_distribution(updated_traffic)
endpoint.traffic = updated_traffic
ml_client.begin_create_or_update(endpoint).result()
print(f"Endpoint traffic configuration updated: {updated_traffic}")

# Write deployment logs and a dummy file to the deploy_status output folder to enforce dependency and provide traceability
if args.deploy_status:
    os.makedirs(args.deploy_status, exist_ok=True)
    # Write a dummy file
    with open(os.path.join(args.deploy_status, "done.txt"), "w") as f:
        f.write("Deployment complete.")
    # Write deployment logs
    with open(os.path.join(args.deploy_status, "deployment_log.txt"), "w") as logf:
        logf.write("Model name: {}\n".format(args.model_name))
        logf.write("Endpoint name: {}\n".format(args.endpoint_name))
        logf.write("Deployment name: {}\n".format(resolved_slot))
        logf.write("Registry: {}\n".format(args.registry if args.registry else "(workspace)"))
        logf.write("Latest model version: {}\n".format(latest_model_version))
        logf.write("Endpoint provisioning state: {}\n".format(endpoint.provisioning_state))
        logf.write(f"Traffic configuration after deployment: {updated_traffic}\n")

    metadata = {
        "previous_traffic": previous_traffic,
        "updated_traffic": updated_traffic,
        "new_deployment": resolved_slot,
        "endpoint_name": args.endpoint_name,
        "has_prior_deployment": bool(previous_traffic),
        "model_name": model_name,
        "model_version": latest_model_version,
        "model_source": "registry" if args.registry else "workspace",
    }
    with open(os.path.join(args.deploy_status, "deployment_state.json"), "w") as meta_file:
        json.dump(metadata, meta_file)