import argparse
import os
from typing import Dict
from pathlib import Path


def _normalize_slot_name(value: str) -> str:
    return value.strip().lower()


def _determine_slot(traffic: Dict[str, int], default_slot: str, alternate_slot: str) -> str:
    if not traffic:
        return default_slot

    normalized = {name.lower(): weight for name, weight in traffic.items()}
    if default_slot not in normalized:
        return default_slot
    if alternate_slot not in normalized:
        return alternate_slot

    min_weight = min(normalized.values())
    candidates = [name for name, weight in normalized.items() if weight == min_weight]
    if alternate_slot in candidates:
        return alternate_slot
    if default_slot in candidates:
        return default_slot
    return candidates[0]


def main() -> None:
    parser = argparse.ArgumentParser("select_deployment_slot")
    parser.add_argument("--endpoint_name", type=str, required=True, help="Managed online endpoint name")
    parser.add_argument("--default_slot", type=str, default="blue", help="Preferred slot when no deployments exist")
    parser.add_argument("--alternate_slot", type=str, default="green", help="Alternate slot when default is active")
    parser.add_argument("--preferred_slot", type=str, required=False, default="", help="Explicit slot to reuse when provided")
    parser.add_argument("--output_slot", type=str, required=True, help="Path where the selected slot name will be written")

    args = parser.parse_args()

    preferred = args.preferred_slot.strip()
    if preferred:
        selected = _normalize_slot_name(preferred)
        print(f"Using preferred slot override: {selected}")
    else:
        default_slot = _normalize_slot_name(args.default_slot or "blue")
        alternate_slot = _normalize_slot_name(args.alternate_slot or "green")

        from azure.identity import ManagedIdentityCredential
        from azure.ai.ml import MLClient
        from azure.core.exceptions import ResourceNotFoundError
        from azureml.core.run import Run

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
            print("Endpoint does not exist; defaulting to initial slot.")
            selected = default_slot
        else:
            # `endpoint.traffic` only lists active deployments; reuse the slot with the lowest traffic share.
            endpoint_traffic = endpoint.traffic or {}
            selected = _determine_slot(endpoint_traffic, default_slot, alternate_slot)
            print(f"Existing traffic map: {endpoint_traffic}; selected slot: {selected}")

    output_path = Path(args.output_slot)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(selected, encoding="utf-8")
    print(f"Slot selection written to {output_path}")


if __name__ == "__main__":
    main()
