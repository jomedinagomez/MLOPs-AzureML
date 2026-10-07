"""Stage an identity-authenticated, checksum-verified registered model on Spark ADLS."""

from __future__ import annotations

from hashlib import sha256
import json
from pathlib import PurePosixPath
from urllib.parse import urlparse

from azure.ai.ml import MLClient
from azure.ai.ml.entities import AzureBlobDatastore, AzureDataLakeGen2Datastore, Model
from azure.core import MatchConditions
from azure.core.credentials import TokenCredential
from azure.storage.blob import BlobServiceClient
from azure.storage.filedatalake import FileSystemClient


def stage_registered_model(
    ml_client: MLClient,
    model: Model,
    credential: TokenCredential,
    destination: FileSystemClient,
    storage_account: str,
    filesystem: str,
) -> str:
    if not model.id or not model.path or not model.name or not model.version:
        raise ValueError("Staging requires a resolved registered model version")
    parsed = urlparse(model.path)
    parts = [parsed.netloc, *parsed.path.strip("/").split("/")]
    if parsed.scheme != "azureml" or parsed.query or parsed.fragment or "datastores" not in parts:
        raise ValueError("Expected the registered model's Azure ML datastore artifact URI")
    index = parts.index("datastores")
    if len(parts) <= index + 3 or parts[index + 2] != "paths":
        raise ValueError("The registered model URI has no datastore artifact path")
    datastore = ml_client.datastores.get(parts[index + 1], include_secrets=False)
    if isinstance(datastore, AzureBlobDatastore):
        container_name = datastore.container_name
    elif isinstance(datastore, AzureDataLakeGen2Datastore):
        container_name = datastore.filesystem
    else:
        raise TypeError("Registered Spark model artifacts must be in Azure Blob or ADLS storage")
    prefix = "/".join(parts[index + 3:]).rstrip("/")
    if not prefix or ".." in PurePosixPath(prefix).parts:
        raise ValueError("Invalid registered model artifact prefix")
    payloads: dict[str, bytes] = {}
    with BlobServiceClient(
        account_url=f"https://{datastore.account_name}.blob.core.windows.net",
        credential=credential,
    ) as source:
        container = source.get_container_client(container_name)
        for blob in container.list_blobs(name_starts_with=f"{prefix}/"):
            if blob.name.endswith("/"):
                continue
            relative = PurePosixPath(blob.name).relative_to(prefix)
            if ".." in relative.parts:
                raise ValueError(f"Invalid registered model artifact path: {blob.name}")
            payloads[relative.as_posix()] = container.download_blob(blob.name).readall()
    if not any(name.startswith("sparkml-model/metadata/") for name in payloads):
        raise FileNotFoundError("The registered artifact has no saved sparkml-model metadata")
    if "registered_model_manifest.json" in payloads:
        raise ValueError("The registered artifact uses the reserved provenance manifest name")

    files = [
        {"path": name, "size": len(data), "sha256": sha256(data).hexdigest()}
        for name, data in sorted(payloads.items())
    ]
    content_hash = sha256(json.dumps(files, sort_keys=True).encode("utf-8")).hexdigest()
    asset_key = sha256(model.id.encode("utf-8")).hexdigest()[:16]
    target_prefix = f"models/registered/{model.name}/{model.version}/{asset_key}/{content_hash}"
    provenance = {
        "model_asset_id": model.id,
        "registered_artifact_uri": model.path,
        "content_sha256": content_hash,
        "files": files,
    }
    payloads["registered_model_manifest.json"] = json.dumps(
        provenance, sort_keys=True
    ).encode("utf-8")
    directories = {
        parent.as_posix()
        for name in payloads
        for parent in PurePosixPath(f"{target_prefix}/{name}").parents
        if parent.as_posix() != "."
    }
    for name in sorted(directories, key=lambda value: (value.count("/"), value)):
        directory = destination.get_directory_client(name)
        if not directory.exists():
            directory.create_directory()
    for name, data in sorted(payloads.items()):
        remote = destination.get_file_client(f"{target_prefix}/{name}")
        if not remote.exists():
            # The SDK's create-and-upload flag is guarded by an atomic IfMissing condition.
            if data:
                remote.upload_data(
                    data, overwrite=True, match_condition=MatchConditions.IfMissing
                )
            else:
                remote.create_file(match_condition=MatchConditions.IfMissing)
        if sha256(remote.download_file().readall()).digest() != sha256(data).digest():
            raise RuntimeError(f"Registered model copy checksum mismatch: {name}")
    return f"abfss://{filesystem}@{storage_account}.dfs.core.windows.net/{target_prefix}/"
