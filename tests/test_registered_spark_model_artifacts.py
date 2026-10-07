from __future__ import annotations

import importlib.util
import json
from pathlib import Path, PurePosixPath
from types import SimpleNamespace
from unittest.mock import Mock

from azure.ai.ml.entities import AzureBlobDatastore
from azure.core import MatchConditions
import pytest


ROOT = Path(__file__).resolve().parents[1]
MODULE = (
    ROOT / "workshop" / "notebooks" / "06_spark_jobs_pipelines"
    / "src" / "registered_model_artifacts.py"
)


@pytest.fixture
def staging(monkeypatch):
    spec = importlib.util.spec_from_file_location("registered_model_artifacts", MODULE)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    payloads = {
        "sparkml-model/metadata/part-00000": b'{"class":"org.apache.spark.ml.PipelineModel"}',
        "sparkml-model/stages/data/model.bin": b"registered-spark-model",
        "sparkml-model/stages/data/_SUCCESS": b"",
    }
    prefix = "LocalUpload/immutable/pipeline_model"
    calls = []

    class Source:
        def __init__(self, **kwargs):
            calls.append(kwargs)

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

        def get_container_client(self, name):
            assert name == "models"
            return self

        def list_blobs(self, *, name_starts_with):
            assert name_starts_with == f"{prefix}/"
            return [SimpleNamespace(name=f"{prefix}/{name}") for name in payloads]

        def download_blob(self, name):
            relative = PurePosixPath(name).relative_to(prefix).as_posix()
            return SimpleNamespace(readall=lambda: payloads[relative])

    class Destination:
        def __init__(self):
            self.files = {}
            self.directories = set()
            self.uploads = 0

        def get_directory_client(self, name):
            def create():
                parent = PurePosixPath(name).parent.as_posix()
                assert parent == "." or parent in self.directories
                self.directories.add(name)

            return SimpleNamespace(
                exists=lambda: name in self.directories,
                create_directory=create,
            )

        def get_file_client(self, name):
            def upload(data, *, overwrite, match_condition):
                assert overwrite is True
                assert match_condition == MatchConditions.IfMissing
                assert name not in self.files
                assert PurePosixPath(name).parent.as_posix() in self.directories
                self.files[name] = data
                self.uploads += 1

            def create(*, match_condition):
                assert match_condition == MatchConditions.IfMissing
                assert name not in self.files
                assert PurePosixPath(name).parent.as_posix() in self.directories
                self.files[name] = b""
                self.uploads += 1

            return SimpleNamespace(
                exists=lambda: name in self.files,
                upload_data=upload,
                create_file=create,
                download_file=lambda: SimpleNamespace(readall=lambda: self.files[name]),
            )

    monkeypatch.setattr(module, "BlobServiceClient", Source)
    model = SimpleNamespace(
        name="titanic", version="1", id="azureml:titanic:1",
        path=f"azureml://datastores/registered_models/paths/{prefix}",
    )
    datastore = AzureBlobDatastore(
        name="registered_models", account_name="modelstorage", container_name="models"
    )
    client = SimpleNamespace(datastores=SimpleNamespace(get=Mock(return_value=datastore)))
    credential = Mock()
    destination = Destination()

    def run():
        return module.stage_registered_model(
            client, model, credential, destination, "sparkstorage", "spark"
        )

    return SimpleNamespace(
        run=run, payloads=payloads, calls=calls, model=model, client=client,
        credential=credential, destination=destination,
    )


def test_registered_copy_is_identity_based_verified_and_reused_without_overwriting(staging):
    uri = staging.run()
    assert uri.startswith("abfss://spark@sparkstorage.dfs.core.windows.net/models/registered/titanic/1/")
    staging.client.datastores.get.assert_called_with("registered_models", include_secrets=False)
    assert staging.calls[0]["credential"] is staging.credential
    assert staging.calls[0]["account_url"] == "https://modelstorage.blob.core.windows.net"
    manifest_name = next(
        name for name in staging.destination.files if name.endswith("registered_model_manifest.json")
    )
    manifest = json.loads(staging.destination.files[manifest_name])
    assert manifest["model_asset_id"] == staging.model.id
    assert manifest["registered_artifact_uri"] == staging.model.path
    assert len(manifest["content_sha256"]) == 64
    assert {entry["path"] for entry in manifest["files"]} == set(staging.payloads)
    assert any(name.endswith("/_SUCCESS") for name in staging.destination.files)
    uploads = staging.destination.uploads
    assert staging.run() == uri
    assert staging.destination.uploads == uploads


def test_registered_copy_rejects_corrupted_existing_bytes(staging):
    staging.run()
    target = next(name for name in staging.destination.files if name.endswith("model.bin"))
    staging.destination.files[target] = b"not-the-registered-model"
    with pytest.raises(RuntimeError, match="checksum mismatch"):
        staging.run()


def test_registered_copy_rejects_missing_spark_metadata_before_upload(staging):
    staging.payloads.pop("sparkml-model/metadata/part-00000")
    with pytest.raises(FileNotFoundError, match="sparkml-model metadata"):
        staging.run()
    assert staging.destination.uploads == 0


def test_registered_copy_rejects_unsafe_source_paths(staging):
    staging.payloads["../outside-model"] = b"invalid"
    with pytest.raises(ValueError, match="Invalid registered model artifact path"):
        staging.run()
    assert staging.destination.uploads == 0


def test_installed_datalake_sdk_serializes_atomic_missing_condition():
    from azure.storage.filedatalake import DataLakeFileClient

    client = DataLakeFileClient(
        account_url="https://sparkstorage.dfs.core.windows.net",
        file_system_name="spark", file_path="model/metadata",
    )
    options = client._upload_options(
        b"model-bytes", overwrite=True, match_condition=MatchConditions.IfMissing
    )
    assert options["modified_access_conditions"].if_none_match == "*"
    assert "etag" not in options
    assert "match_condition" not in options
    client.close()
