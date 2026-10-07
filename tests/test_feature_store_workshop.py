from __future__ import annotations

import ast
import json
import re
from pathlib import Path

import pytest
import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
WORKSHOP = REPO_ROOT / "workshop"
MODULE = WORKSHOP / "notebooks" / "07_feature_store"
SAMPLE = MODULE / "featurestore_sample"
NOTEBOOKS = (
    "00_prepare_sample_data.ipynb",
    "01_develop_feature_set_and_register.ipynb",
    "02_experiment_and_train_models.ipynb",
    "03_recurrent_materialization_batch_inference.ipynb",
    "04_online_store_and_online_inference.ipynb",
)
OFFICIAL_CELLS = {
    "01_develop_feature_set_and_register.ipynb": (
        "create-fs", "init-fs-core-sdk", "develop-txn-fset-locally", "dump-transactions-fs-spec",
        "register-acct-entity", "register-txn-fset", "grant-rbac-to-user-identity",
        "enable-offline-mat-txns-fset", "backfill-txns-fset", "stream-mat-job-logs",
    ),
    "02_experiment_and_train_models.ipynb": (
        "create-compute-cluster", "create-accts-fset-spec", "gen-training-data-locally", "reg-accts-fset",
        "select-reg-features", "export-as-frspec", "run-training-pipeline",
    ),
    "03_recurrent_materialization_batch_inference.ipynb": (
        "enable-recurrent-mat-txns-fset", "run-batch-inf-pipeline", "inspect-batch-inf-output-data",
    ),
    "04_online_store_and_online_inference.ipynb": (
        "redis-settings", "reuse-redis", "attach-online-store", "enable-accounts-material", "start-accounts-backfill",
        "enable-transact-material", "start-transact-material", "init-online-lookup", "online-feat-loockup",
        "define-endpoint", "endpoint-redis-rbac", "endpoint-fs-rbac", "define-online-deployment",
        "test-online-deployment",
    ),
}


def load(name: str) -> dict:
    return json.loads((MODULE / name).read_text(encoding="utf-8"))


def code_cells(name: str) -> list[dict]:
    return [cell for cell in load(name)["cells"] if cell["cell_type"] == "code"]


def named(name: str) -> dict[str, str]:
    return {
        cell["metadata"]["name"]: "".join(cell["source"])
        for cell in code_cells(name)
        if cell.get("metadata", {}).get("name")
    }


def test_notebooks_are_ordered_and_use_the_repository_kernel():
    assert tuple(sorted(path.name for path in MODULE.glob("*.ipynb"))) == NOTEBOOKS
    for name in NOTEBOOKS:
        notebook = load(name)
        assert notebook["nbformat"] == 4
        assert notebook["metadata"]["kernelspec"]["name"] == "mlops-azureml", name
        for cell in code_cells(name):
            ast.parse("".join(cell["source"]), filename=name)


@pytest.mark.parametrize("name", sorted(OFFICIAL_CELLS))
def test_notebooks_keep_the_official_named_cells(name):
    missing = sorted(set(OFFICIAL_CELLS[name]) - set(named(name)))
    assert not missing, f"{name} is missing official cells: {missing}"


def test_local_execution_adaptations_are_minimal_and_secret_free():
    for name in NOTEBOOKS[1:]:
        source = "\n".join("".join(cell["source"]) for cell in code_cells(name))
        assert "AzureMLOnBehalfOfCredential" not in source, name
        assert "DefaultAzureCredential" not in source, name
        assert "azuremlexampledata" not in source, name
        assert "AzureCliCredential()" not in source, name
        assert "AzureCliCredential(process_timeout=60)" in source, name
        assert "local-setup" in named(name), name
        assert not re.search(r"<[A-Z_]+>|<your_user_alias>", source), name
        assert not re.search(r"(?i)account_key|sas_token|password|client_secret", source), name
        uses_spark = "SparkSession.builder" in named(name)["local-setup"]
        assert uses_spark == (name in NOTEBOOKS[1:3]), name


def test_feature_stores_use_the_supported_spark_runtime():
    assert 'ComputeRuntime(spark_runtime_version="3.5")' in named(NOTEBOOKS[1])["create-fs"]
    assert 'ComputeRuntime(spark_runtime_version="3.5")' in named(NOTEBOOKS[4])["attach-online-store"]


def test_online_store_uses_azure_managed_redis_because_azure_cache_creation_is_blocked():
    cells = named(NOTEBOOKS[4])
    assert "Microsoft.Cache/redisEnterprise" in cells["provision-managed-redis"]
    assert '"accessKeysAuthentication": "Enabled"' in cells["provision-managed-redis"]
    assert "redis_arm_id = database" in cells["provision-managed-redis"]
    assert "/databases/default" in cells["reuse-redis"]
    assert "Microsoft.Cache/redisEnterprise/{redis_name}" in cells["endpoint-redis-rbac"]
    assert "acdd72a7-3385-48ef-bd42-f606fba81ae7" in cells["grant-cluster-reader-to-materialization-identity"]
    markdown = "\n".join("".join(cell["source"]) for cell in load(NOTEBOOKS[4])["cells"] if cell["cell_type"] == "markdown")
    assert "RedisManagementClient" in markdown and "Azure Cache for Redis is retiring" in markdown
    assert "provision-redis" not in cells


def test_schedule_and_backfill_times_use_formats_the_service_accepts():
    official_yaml = SAMPLE / "featurestore/featuresets/transactions/featureset_asset_offline_enabled_with_schedule.yaml"
    assert 'start_time: "2023-04-15T00:04:10"' in official_yaml.read_text(encoding="utf-8")
    schedule = named(NOTEBOOKS[3])["enable-recurrent-mat-txns-fset"]
    online = named(NOTEBOOKS[4])
    assert 'start_time="2023-04-15T00:04:10"' in schedule
    assert 'schedule.start_time = "2023-04-15T00:04:10"' in online["enable-transact-material"]
    for source in (schedule, online["enable-transact-material"]):
        assert "print(fs_poller.result())" not in [line.strip() for line in source.splitlines()]
    for name in ("start-accounts-backfill", "start-transact-material"):
        assert "datetime.now(timezone.utc)" in online[name], name
    assert "timedelta(hours=4)" in online["start-transact-material"]


def test_online_deployment_can_import_the_sdk_and_read_feature_set_specs():
    cells = named(NOTEBOOKS[4])
    assert 'image="mcr.microsoft.com/azureml/openmpi4.1.0-ubuntu22.04"' in cells["define-online-deployment"]
    storage_rbac = cells["endpoint-fs-storage-rbac"]
    assert "2a2b9908-6ea1-4ae2-8e65-a410df84e7d1" in storage_rbac and ".storage_account" in storage_rbac
    assert "principal_id=model_endpoint_msi_principal_id" in storage_rbac


def test_saved_notebook_outputs_have_no_errors():
    for name in NOTEBOOKS:
        errors = [
            cell.get("metadata", {}).get("name", "")
            for cell in code_cells(name)
            if any(output.get("output_type") == "error" for output in cell.get("outputs", []))
        ]
        assert not errors, f"{name} has failed cells: {errors}"


def test_training_cluster_uses_the_workspace_compute_identity():
    cells = named(NOTEBOOKS[2])
    assert "identity=compute_identity" in cells["create-compute-cluster"]
    assert 'AZUREML_COMPUTE_NAME' in cells["create-compute-cluster"]
    assert "AzureDataLakeGen2Datastore" in cells["register-spark-output-datastore"]
    assert "2a2b9908-6ea1-4ae2-8e65-a410df84e7d1" in cells["register-spark-output-datastore"]


def test_local_spark_reads_local_data_and_registered_specs_use_adls():
    develop = named(NOTEBOOKS[1])
    assert "local_data_root" in develop["explore-txn-src-data"]
    assert "cloud_data_root" in develop["use-cloud-source-path"]
    assert "transactions_source_data_path" in develop["use-local-source-path"]
    spec = yaml.safe_load((SAMPLE / "featurestore/featuresets/transactions/spec/FeatureSetSpec.yaml").read_text())
    assert spec["source"]["path"].startswith("abfss://")


def test_official_sample_assets_are_present_with_documented_changes():
    assert (SAMPLE / "LICENSE").read_text(encoding="utf-8").strip().startswith("MIT License")
    for relative in (
        "featurestore/featuresets/transactions/transformation_code/transaction_transform.py",
        "featurestore/setup/setup_storage_uai.py",
        "project/fraud_model/pipelines/training_pipeline.yaml",
        "project/fraud_model/pipelines/batch_inference_pipeline.yaml",
        "project/fraud_model/online_inference/src/scoring.py",
    ):
        assert (SAMPLE / relative).is_file(), relative
    text = "\n".join(path.read_text(encoding="utf-8") for path in SAMPLE.rglob("*.y*ml"))
    assert "azuremlexampledata" not in text
    for pipeline in ("training_pipeline.yaml", "batch_inference_pipeline.yaml"):
        definition = yaml.safe_load((SAMPLE / "project/fraud_model/pipelines" / pipeline).read_text(encoding="utf-8"))
        spark_steps = [job for job in definition["jobs"].values() if job.get("type") == "spark"]
        assert spark_steps and all(job["resources"]["runtime_version"] == "3.5" for job in spark_steps), pipeline
        assert all("azureml-featurestore==1.2.2" in job["conf"]["spark.synapse.library.python.env"] for job in spark_steps)
        assert all(
            job["outputs"]["output_data"]["path"].startswith("azureml://datastores/featurestore_adls/")
            for job in spark_steps
        ), pipeline
    conda = (SAMPLE / "project/fraud_model/online_inference/conda.yml").read_text(encoding="utf-8")
    version = re.search(r"azureml-featurestore\[online\]==(\d+)\.(\d+)\.(\d+)", conda).groups()
    assert tuple(map(int, version)) >= (1, 2, 1)


def test_environment_example_has_feature_store_settings_only():
    example = (WORKSHOP / ".env.example").read_text(encoding="utf-8")
    for key in (
        "AZURE_USER_OBJECT_ID", "AZUREML_FEATURE_STORE_NAME", "AZUREML_FEATURE_STORE_LOCATION",
        "FEATURE_STORE_SOURCE_STORAGE_ACCOUNT", "FEATURE_STORE_SOURCE_FILESYSTEM", "FEATURE_STORE_REDIS_NAME",
        "FEATURE_STORE_ONLINE_ENDPOINT_NAME",
    ):
        assert re.search(rf"^{key}=", example, re.MULTILINE), key
    for obsolete in ("CREATE_FEATURE_STORE", "START_FEATURE_STORE_BACKFILL", "FEATURE_STORE_SPARK_PACKAGES"):
        assert obsolete not in example
    requirements = (WORKSHOP / "requirements.txt").read_text(encoding="utf-8")
    for package in ("azure-mgmt-authorization==", "azure-mgmt-msi==", "azure-mgmt-storage==", "azureml-featurestore[online]=="):
        assert package in requirements, package


def test_talk_track_links_and_extracted_images_resolve():
    talk_track = (MODULE / "FEATURE_STORE_TALK_TRACK.md").read_text(encoding="utf-8")
    assert len(re.findall(r"^#### Slide \d+ ", talk_track, re.MULTILINE)) == 32
    assert len(re.findall(r"^### R\d ", talk_track, re.MULTILINE)) == 8
    links = re.findall(r"\]\(<?([^)>]+)>?\)", talk_track)
    local = {link for link in links if not re.match(r"^[a-z]+://|^#|^mailto:", link)}
    assert local and all((MODULE / link).exists() for link in local)
    manifest = json.loads((MODULE / "AzureMLDocumentation/extracted/manifest.json").read_text(encoding="utf-8"))
    figures = [item for entry in manifest for item in entry["images"] if "file" in item]
    assert len(manifest) == 8 and len(figures) == 13
    assert sum(len(entry["pages"]) for entry in manifest) == 69
    assert all((MODULE / "AzureMLDocumentation" / item["file"]).is_file() for item in figures)
