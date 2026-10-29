from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Optional, Sequence

from azure.ai.ml import MLClient
from azure.ai.ml.constants import AssetTypes
from azure.ai.ml.entities import Model
from azure.identity import ManagedIdentityCredential


def register_model(
    registry_client: MLClient,
    registry_name: str,
    model_input: Path,
    model_name: str,
    compare_output: Path,
    register_output: Path,
) -> Model:
    if not (compare_output / "predictions.csv").is_file():
        raise FileNotFoundError(
            f"Expected completed comparison output at {compare_output / 'predictions.csv'}"
        )
    manifests = sorted(path for path in model_input.rglob("MLmodel") if path.is_file())
    if len(manifests) != 1:
        raise ValueError(
            f"Expected exactly one MLmodel beneath {model_input}, found {len(manifests)}"
        )

    model = Model(
        name=model_name,
        path=str(manifests[0].parent),
        type=AssetTypes.MLFLOW_MODEL,
        description="Taxi model from the workshop integration compare pipeline",
        tags={"workshop": "azureml-h2o", "operation": "integration-compare"},
    )
    registered = registry_client.models.create_or_update(model)
    if not registered.version:
        raise RuntimeError("The registry did not return a registered model version.")
    verified = registry_client.models.get(model_name, version=registered.version)
    if (
        verified.name != model_name
        or verified.version != registered.version
        or verified.type != AssetTypes.MLFLOW_MODEL
        or not verified.id
    ):
        raise RuntimeError("Registry model readback did not match the registration.")

    metadata = {
        "registry_name": registry_name,
        "model_name": verified.name,
        "model_version": verified.version,
        "model_id": verified.id,
    }
    register_output.mkdir(parents=True, exist_ok=True)
    metadata_path = register_output / "registration.json"
    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(f"Registered model: {verified.name}:{verified.version}")
    print(f"Registry model ID: {verified.id}")
    print(f"Registration metadata: {metadata_path}")
    return verified


def main(argv: Optional[Sequence[str]] = None) -> None:
    parser = argparse.ArgumentParser(description="Register the pipeline model in an external registry")
    parser.add_argument("--model_input", required=True, type=Path)
    parser.add_argument("--model_name", required=True)
    parser.add_argument("--compare_output", required=True, type=Path)
    parser.add_argument("--registry", required=True)
    parser.add_argument("--register_output", required=True, type=Path)
    args = parser.parse_args(argv)

    client_id = os.getenv("DEFAULT_IDENTITY_CLIENT_ID", "").strip()
    if not client_id:
        raise ValueError(
            "DEFAULT_IDENTITY_CLIENT_ID must identify the compute cluster's assigned managed identity. "
            "This component does not fall back to Azure CLI or user credentials."
        )
    print(f"Registration identity: compute cluster UAMI {client_id}")
    credential = ManagedIdentityCredential(client_id=client_id)
    try:
        registry_client = MLClient(credential=credential, registry_name=args.registry)
        register_model(
            registry_client, args.registry, args.model_input, args.model_name,
            args.compare_output, args.register_output,
        )
    finally:
        credential.close()


if __name__ == "__main__":
    main()
