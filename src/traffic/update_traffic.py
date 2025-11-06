import argparse
import errno
import json
import os
from typing import Dict

from azure.identity import ManagedIdentityCredential
from azure.ai.ml import MLClient
from azure.core.exceptions import ResourceNotFoundError
from azureml.core.run import Run


def _normalize_distribution(distribution: Dict[str, int]) -> Dict[str, int]:
    if not distribution:
        return distribution
    total = sum(distribution.values())
    if total == 100:
        return distribution
    diff = 100 - total
    # Adjust the deployment with the highest weight to absorb rounding differences
    max_key = max(distribution, key=lambda k: distribution[k])
    distribution[max_key] += diff
    return distribution


def _load_metadata(state_dir: str) -> Dict:
    if not state_dir:
        return {}
    metadata_path = os.path.join(state_dir, "deployment_state.json")
    if not os.path.exists(metadata_path):
        return {}
    with open(metadata_path, "r") as fh:
        return json.load(fh)


def _str_to_bool(value: str) -> bool:
    if value is None:
        return False
    return str(value).lower() in {"true", "1", "yes", "y"}


def main():
    parser = argparse.ArgumentParser("update_traffic")
    parser.add_argument("--endpoint_name", type=str, required=True, help="Managed online endpoint name")
    parser.add_argument("--deployment_name", type=str, required=True, help="Deployment slot to adjust")
    parser.add_argument("--deployment_name_file", type=str, required=False, help="File containing deployment slot name")
    parser.add_argument("--default_slot", type=str, required=False, help="Fallback slot when no override exists")
    parser.add_argument("--deployment_state", type=str, required=False, help="Folder containing deployment metadata produced by deploy step")
    parser.add_argument("--traffic_percent", type=int, default=30, help="Traffic percentage for the new deployment when promoting")
    parser.add_argument("--mode", type=str, choices=["promote", "rollback"], default="promote", help="Promotion assigns traffic to the new deployment; rollback restores previous mapping")
    parser.add_argument("--delete_on_rollback", type=str, required=False, default="false", help="Delete the new deployment slot after rollback when prior deployments exist (true/false)")
    parser.add_argument("--output_deployment_state", type=str, required=False, help="Writable folder for updated deployment metadata")

    args = parser.parse_args()

    deployment_name = (args.deployment_name or "").strip()
    if not deployment_name and args.deployment_name_file and os.path.exists(args.deployment_name_file):
        with open(args.deployment_name_file, "r", encoding="utf-8") as slot_file:
            deployment_name = slot_file.read().strip()
    if not deployment_name:
        deployment_name = (args.default_slot or "").strip() or "blue"

    metadata = _load_metadata(args.deployment_state)
    previous_traffic = metadata.get("previous_traffic", {})
    has_prior = metadata.get("has_prior_deployment", bool(previous_traffic))
    metadata.setdefault("new_deployment", deployment_name)
    print(f"Loaded metadata: prior traffic={previous_traffic}, has_prior={has_prior}")

    delete_on_rollback = _str_to_bool(args.delete_on_rollback)

    # Authenticate inside the AML run context (managed identity on compute)
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

    try:
        endpoint = ml_client.online_endpoints.get(name=args.endpoint_name)
    except ResourceNotFoundError:
        raise SystemExit(f"Endpoint {args.endpoint_name} does not exist")

    new_traffic: Dict[str, int]

    if args.mode == "promote":
        if has_prior and previous_traffic:
            print("Prior deployment detected. Applying weighted distribution with new deployment share.")
            remaining = max(0, 100 - args.traffic_percent)
            total_prev = sum(previous_traffic.values()) or 0
            new_traffic = {}
            for name, weight in previous_traffic.items():
                if total_prev == 0:
                    new_traffic[name] = remaining // max(1, len(previous_traffic))
                else:
                    new_traffic[name] = int(round(remaining * weight / total_prev))
            new_traffic[deployment_name] = args.traffic_percent
        else:
            print("No prior deployment detected. Routing 100% of traffic to the new deployment.")
            new_traffic = {deployment_name: 100}
    else:  # rollback
        if previous_traffic:
            print("Restoring previous traffic configuration as part of rollback.")
            new_traffic = previous_traffic
        else:
            print("No previous traffic configuration found. Keeping traffic on the new deployment.")
            new_traffic = {deployment_name: 100}

    new_traffic = _normalize_distribution(new_traffic)
    print(f"Resulting traffic distribution: {new_traffic}")

    endpoint.traffic = new_traffic
    ml_client.online_endpoints.begin_create_or_update(endpoint).result()

    if args.mode == "rollback" and delete_on_rollback and has_prior:
        try:
            print(f"Deleting deployment {deployment_name} after rollback.")
            ml_client.online_deployments.begin_delete(endpoint_name=args.endpoint_name, name=deployment_name).result()
            metadata["deleted_new_deployment"] = True
        except ResourceNotFoundError:
            print("Deployment already removed during rollback.")

    target_state_dir = args.output_deployment_state or args.deployment_state
    fallback_dir = os.path.join("outputs", "deployment_state")

    def _persist_state(destination: str) -> None:
        os.makedirs(destination, exist_ok=True)
        metadata["current_traffic"] = new_traffic
        metadata["resolved_deployment"] = deployment_name
        with open(os.path.join(destination, "deployment_state.json"), "w", encoding="utf-8") as fh:
            json.dump(metadata, fh)

    if target_state_dir:
        try:
            _persist_state(target_state_dir)
        except OSError as err:
            if err.errno in {errno.EROFS, errno.EACCES}:
                print(
                    "Deployment state directory was not writable; persisting to ./outputs/deployment_state instead."
                )
                _persist_state(fallback_dir)
            else:
                raise
    else:
        # Default to run outputs to keep metadata traceable for downstream troubleshooting.
        _persist_state(fallback_dir)

    print("Traffic update completed")


if __name__ == "__main__":
    main()