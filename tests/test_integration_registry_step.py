import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace

import nbformat
import pytest
import yaml
from azure.ai.ml import load_job
from azure.ai.ml.constants import AssetTypes
from azure.ai.ml.entities import ManagedIdentityConfiguration


ROOT = Path(__file__).resolve().parents[1]
WORKSHOP = ROOT / "workshop"
PIPELINE = WORKSHOP / "pipelines/integration-compare-pipeline.yaml"
COMPONENT = WORKSHOP / "src/components/register.yaml"
SCRIPT = WORKSHOP / "src/register/register.py"
NOTEBOOK = WORKSHOP / "notebooks/02_jobs_and_pipelines/02_submit_integration_compare.ipynb"


@pytest.fixture
def registration_module():
    spec = importlib.util.spec_from_file_location("integration_register", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ModelOperations:
    def __init__(self):
        self.created = []
        self.reads = []
        self.corrupt_readback = False

    def create_or_update(self, model):
        self.created.append(model)
        return SimpleNamespace(name=model.name, version="7")

    def get(self, name, version):
        self.reads.append((name, version))
        return SimpleNamespace(
            name=name,
            version="wrong" if self.corrupt_readback else version,
            type=AssetTypes.MLFLOW_MODEL,
            id=f"azureml://registries/external/models/{name}/versions/{version}",
        )


def artifacts(tmp_path):
    model_input = tmp_path / "model"
    model_root = model_input / "outputs/mlflow-model"
    model_root.mkdir(parents=True)
    (model_root / "MLmodel").write_text("flavors: {}\n", encoding="utf-8")
    (model_root / "model.pkl").write_bytes(b"test model")
    comparison = tmp_path / "comparison"
    comparison.mkdir()
    (comparison / "predictions.csv").write_text("actual,predicted\n1,1\n", encoding="utf-8")
    return model_input, model_root, comparison


def test_registration_is_a_sixth_pipeline_node():
    pipeline = yaml.safe_load(PIPELINE.read_text(encoding="utf-8"))
    assert set(pipeline["jobs"]) == {
        "merge_job", "transform_job", "train_job", "predict_job",
        "compare_job", "register_job",
    }
    registration = pipeline["jobs"]["register_job"]
    assert registration["component"] == "../src/components/register.yaml"
    assert registration["inputs"] == {
        "model_input": "${{parent.jobs.train_job.outputs.model_output}}",
        "model_name": "${{parent.inputs.model_base}}-${{parent.inputs.environment}}-${{parent.inputs.artifact_id}}",
        "compare_output": "${{parent.jobs.compare_job.outputs.compare_output}}",
        "registry": "${{parent.inputs.registry}}",
    }
    assert registration["outputs"]["register_output"] == "${{parent.outputs.register_metadata}}"
    assert pipeline["settings"]["continue_on_step_failure"] is False
    component = yaml.safe_load(COMPONENT.read_text(encoding="utf-8"))
    assert component["is_deterministic"] is False
    assert component["inputs"]["registry"]["type"] == "string"
    assert not component["inputs"]["registry"].get("optional", False)
    assert (COMPONENT.parent / component["code"]).resolve() == SCRIPT.parent


def test_notebook_binds_registry_and_cluster_identity_without_post_pipeline_registration():
    notebook = nbformat.read(NOTEBOOK, as_version=4)
    nbformat.validate(notebook)
    code = ["".join(cell.source) for cell in notebook.cells if cell.cell_type == "code"]
    for cell in code:
        compile(cell, str(NOTEBOOK), "exec")
    submission = next(cell for cell in code if cell.startswith("job = load_job("))
    namespace = {
        "load_job": load_job,
        "pipeline_path": PIPELINE,
        "COMPUTE_NAME": "test-cluster",
        "COMPUTE_IDENTITY_CLIENT_ID": "11111111-2222-3333-4444-555555555555",
        "OUTPUT_DATASTORE": "workspaceblobstore",
        "REGISTRY_NAME": "external",
        "RUN_JOB": False,
        "ManagedIdentityConfiguration": ManagedIdentityConfiguration,
    }
    exec(compile(submission, str(NOTEBOOK), "exec"), namespace)
    job = namespace["job"]
    assert job.inputs["registry"].result() == "external"
    assert job._validate().passed
    assert len(job.jobs) == 6
    assert all(
        child.identity.client_id == namespace["COMPUTE_IDENTITY_CLIENT_ID"]
        for child in job.jobs.values()
    )
    assert not any("models.create_or_update" in cell or "models.share" in cell for cell in code)


def test_registers_the_mlflow_root_and_writes_verified_metadata(registration_module, tmp_path):
    model_input, model_root, comparison = artifacts(tmp_path)
    operations = ModelOperations()
    output = tmp_path / "registration"
    result = registration_module.register_model(
        SimpleNamespace(models=operations), "external", model_input,
        "taxi-class-dev-m", comparison, output,
    )

    assert len(operations.created) == 1
    model = operations.created[0]
    assert Path(model.path) == model_root
    assert model.type == AssetTypes.MLFLOW_MODEL
    assert model.version is None
    assert operations.reads == [("taxi-class-dev-m", "7")]
    assert result.version == "7"
    assert json.loads((output / "registration.json").read_text(encoding="utf-8")) == {
        "registry_name": "external",
        "model_name": "taxi-class-dev-m",
        "model_version": "7",
        "model_id": result.id,
    }


@pytest.mark.parametrize("model_count", [0, 2])
def test_missing_or_ambiguous_mlflow_roots_stop_registration(
    registration_module, tmp_path, model_count
):
    model_input, model_root, comparison = artifacts(tmp_path)
    (model_root / "MLmodel").unlink()
    for index in range(model_count):
        candidate = model_input / str(index)
        candidate.mkdir()
        (candidate / "MLmodel").write_text("flavors: {}\n", encoding="utf-8")
    operations = ModelOperations()
    with pytest.raises(ValueError, match="exactly one MLmodel"):
        registration_module.register_model(
            SimpleNamespace(models=operations), "external", model_input,
            "taxi", comparison, tmp_path / "registration",
        )
    assert operations.created == []


def test_missing_comparison_output_stops_registration(registration_module, tmp_path):
    model_input, _, comparison = artifacts(tmp_path)
    (comparison / "predictions.csv").unlink()
    operations = ModelOperations()
    with pytest.raises(FileNotFoundError, match="comparison"):
        registration_module.register_model(
            SimpleNamespace(models=operations), "external", model_input,
            "taxi", comparison, tmp_path / "registration",
        )
    assert operations.created == []


def test_bad_registry_readback_does_not_write_success_metadata(registration_module, tmp_path):
    model_input, _, comparison = artifacts(tmp_path)
    operations = ModelOperations()
    operations.corrupt_readback = True
    output = tmp_path / "registration"
    with pytest.raises(RuntimeError, match="readback"):
        registration_module.register_model(
            SimpleNamespace(models=operations), "external", model_input,
            "taxi", comparison, output,
        )
    assert not (output / "registration.json").exists()


def test_registry_permission_errors_are_not_suppressed(registration_module, tmp_path):
    model_input, _, comparison = artifacts(tmp_path)
    operations = ModelOperations()

    def denied(model):
        raise PermissionError("registry access denied")

    operations.create_or_update = denied
    with pytest.raises(PermissionError, match="registry access denied"):
        registration_module.register_model(
            SimpleNamespace(models=operations), "external", model_input,
            "taxi", comparison, tmp_path / "registration",
        )


def test_registration_uses_only_the_job_managed_identity(registration_module, tmp_path, monkeypatch):
    model_input, _, comparison = artifacts(tmp_path)
    calls = {}
    operations = ModelOperations()
    monkeypatch.setenv("DEFAULT_IDENTITY_CLIENT_ID", "cluster-client-id")

    def credential_factory(*, client_id):
        calls["client_id"] = client_id
        return SimpleNamespace(close=lambda: None)

    def client_factory(*, credential, registry_name):
        calls["credential"] = credential
        calls["registry"] = registry_name
        return SimpleNamespace(models=operations)

    monkeypatch.setattr(registration_module, "ManagedIdentityCredential", credential_factory)
    monkeypatch.setattr(registration_module, "MLClient", client_factory)
    registration_module.main([
        "--model_input", str(model_input), "--model_name", "taxi",
        "--compare_output", str(comparison), "--registry", "external",
        "--register_output", str(tmp_path / "registration"),
    ])
    assert calls["client_id"] == "cluster-client-id"
    assert calls["registry"] == "external"
    assert len(operations.created) == 1


def test_missing_managed_identity_cannot_fall_back_to_cli(registration_module, tmp_path, monkeypatch):
    monkeypatch.delenv("DEFAULT_IDENTITY_CLIENT_ID", raising=False)
    with pytest.raises(ValueError, match="DEFAULT_IDENTITY_CLIENT_ID"):
        registration_module.main([
            "--model_input", str(tmp_path), "--model_name", "taxi",
            "--compare_output", str(tmp_path), "--registry", "external",
            "--register_output", str(tmp_path / "registration"),
        ])
