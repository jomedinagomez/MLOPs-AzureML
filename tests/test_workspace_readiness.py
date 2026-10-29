import ast
import json
import os
import shutil
import sys
from pathlib import Path
from types import ModuleType, SimpleNamespace
import __future__
import textwrap

import mltable
import nbformat
import pytest
import requests
import yaml
from azure.ai.ml import load_job
from azure.ai.ml.constants import AssetTypes
from azure.ai.ml.entities import (
    AmlCompute, Data, Environment, IdentityConfiguration,
    ManagedIdentityConfiguration, Model,
)

import test_registry_asset_sharing as sharing_tests


ROOT = Path(__file__).resolve().parents[1]
SUITE = ROOT / "notebooks/workspace_readiness"
FOLDERS = ("01_foundations", "02_jobs_and_pipelines")
ENV_VALUES = {
    "AZURE_SUBSCRIPTION_ID": "test-subscription",
    "AZURE_RESOURCE_GROUP": "test-group",
    "AZUREML_WORKSPACE_NAME": "test-workspace",
    "AZUREML_REGISTRY_NAME": "test-registry",
}


def inline_setup(path, monkeypatch):
    notebook = nbformat.read(path, as_version=4)
    source = next(cell.source for cell in notebook.cells if cell.cell_type == "code")
    module = ModuleType("inline_readiness")
    monkeypatch.setitem(sys.modules, module.__name__, module)
    module.SUITE_ROOT = SUITE
    nodes = []
    for node in ast.parse(source).body:
        if isinstance(node, ast.ImportFrom):
            assert node.module != "readiness"
        if isinstance(node, (ast.Import, ast.ImportFrom, ast.FunctionDef, ast.ClassDef)):
            nodes.append(node)
        elif isinstance(node, ast.Assign) and any(
            isinstance(target, ast.Name) and target.id in {"ENV_KEYS", "ASSET_NAMES"}
            for target in node.targets
        ):
            nodes.append(node)
    exec(
        compile(ast.Module(body=nodes, type_ignores=[]), str(path), "exec"),
        vars(module),
    )
    return module


@pytest.fixture
def readiness(monkeypatch):
    return inline_setup(SUITE / "01_foundations/01_workspace_and_compute.ipynb", monkeypatch)


def write_env(tmp_path, values):
    path = tmp_path / ".env"
    path.write_text(
        "".join(f"{key}={value}\n" for key, value in values.items()), encoding="utf-8"
    )
    return path


def direct_startup(path, tmp_path, monkeypatch, values=ENV_VALUES):
    suite = tmp_path / "workspace_readiness"
    suite.mkdir(exist_ok=True)
    (suite / ".env.example").write_text("# Test configuration\n", encoding="utf-8")
    if values is not None:
        write_env(suite, values)
    notebook = nbformat.read(path, as_version=4)
    source = next(cell.source for cell in notebook.cells if cell.cell_type == "code")
    prefix = source.split("ASSET_NAMES =", 1)[0]

    def client(credential, subscription_id, resource_group_name, workspace_name):
        return SimpleNamespace(
            credential=credential, subscription_id=subscription_id,
            resource_group_name=resource_group_name, workspace_name=workspace_name,
        )

    monkeypatch.setattr("azure.ai.ml.MLClient", client)
    namespace = {"__vsc_ipynb_file__": str(suite / path.name)}
    exec(compile(prefix, str(path), "exec"), namespace)
    return namespace


def test_configuration_is_isolated_from_process_and_parent_environments(
    tmp_path, monkeypatch
):
    monkeypatch.setenv("AZUREML_WORKSPACE_NAME", "wrong-inherited-workspace")
    monkeypatch.setenv("DEPLOY_FOUNDATION_ENDPOINT", "true")
    namespace = direct_startup(
        SUITE / "01_foundations/02_register_data_asset.ipynb", tmp_path, monkeypatch
    )
    assert namespace["ml_client"].workspace_name == "test-workspace"
    assert namespace["REGISTRY_NAME"] == "test-registry"
    assert namespace["ml_client"].resource_group_name == "test-group"
    assert namespace["ml_client"].subscription_id == "test-subscription"
    assert namespace["ml_client"].credential is namespace["credential"]
    assert os.environ["AZUREML_WORKSPACE_NAME"] == "wrong-inherited-workspace"


def test_missing_or_unresolved_configuration_is_explicit(tmp_path, monkeypatch):
    path = SUITE / "01_foundations/02_register_data_asset.ipynb"
    with pytest.raises(FileNotFoundError, match=r"\.env"):
        direct_startup(path, tmp_path, monkeypatch, values=None)
    for bad_value in ("", "<WORKSPACE_NAME>", "${AZUREML_WORKSPACE_NAME}"):
        values = {**ENV_VALUES, "AZUREML_WORKSPACE_NAME": bad_value}
        with pytest.raises(ValueError):
            direct_startup(path, tmp_path, monkeypatch, values)


def test_environment_contains_only_deployment_coordinates(tmp_path, monkeypatch):
    values = {**ENV_VALUES, "DEPLOY_FOUNDATION_ENDPOINT": "true"}
    with pytest.raises(ValueError):
        direct_startup(
            SUITE / "01_foundations/02_register_data_asset.ipynb",
            tmp_path, monkeypatch, values,
        )
    keys = {
        line.split("=", 1)[0]
        for line in (SUITE / ".env.example").read_text(encoding="utf-8").splitlines()
        if line and not line.startswith("#")
    }
    assert keys == set(ENV_VALUES)


def cluster(name, identities):
    return AmlCompute(
        name=name,
        size="Standard_F8s_v2",
        identity=IdentityConfiguration(
            type="UserAssigned",
            user_assigned_identities=[
                ManagedIdentityConfiguration(
                    client_id=identity.client_id, resource_id=identity.resource_id
                )
                for identity in identities
            ],
        ),
    )


def compute_client(computes):
    def get(name):
        return next(item for item in computes if item.name == name)

    return SimpleNamespace(compute=SimpleNamespace(list=lambda: computes, get=get))


def test_cluster_identity_is_discovered_without_environment_overrides(readiness):
    identity = SimpleNamespace(client_id="cluster-client", resource_id="/identities/cluster")
    client = compute_client([cluster("cluster07", [identity])])
    assert readiness.resolve_cluster(client, None) == ("cluster07", "cluster-client")


def test_ambiguous_compute_and_identities_are_not_silently_selected(readiness):
    identity = SimpleNamespace(client_id="cluster-client", resource_id="/identities/cluster")
    computes = [cluster("one", [identity]), cluster("two", [identity])]
    with pytest.raises(ValueError, match="COMPUTE_NAME"):
        readiness.resolve_cluster(compute_client(computes), None)
    assert readiness.resolve_cluster(compute_client(computes), None, "two") == (
        "two", "cluster-client"
    )
    for identities in ([], [identity, identity]):
        with pytest.raises(ValueError, match="one user-assigned"):
            readiness.resolve_cluster(compute_client([cluster("one", identities)]), None)


def test_identity_client_id_can_be_read_from_its_resource(readiness, monkeypatch):
    identity = SimpleNamespace(client_id=None, resource_id="/identities/cluster")
    calls = []

    def arm_get(credential, resource_id, api_version):
        calls.append((credential, resource_id, api_version))
        return {"properties": {"clientId": "resolved-client"}}

    monkeypatch.setattr(readiness, "arm_get", arm_get)
    assert readiness.resolve_cluster(
        compute_client([cluster("one", [identity])]), "credential"
    ) == ("one", "resolved-client")
    assert calls == [("credential", "/identities/cluster", "2023-01-31")]


def test_endpoint_identity_uses_the_selected_workspace_group(readiness, monkeypatch):
    readiness = inline_setup(SUITE / "01_foundations/06_deploy_online_endpoint.ipynb", monkeypatch)
    expected = (
        "/subscriptions/test-subscription/resourceGroups/test-group"
        "/providers/Microsoft.ManagedIdentity/userAssignedIdentities/private-mi-online-endpoint"
    )
    calls = []

    def arm_get(credential, resource_id, api_version):
        calls.append((resource_id, api_version))
        return {"id": resource_id}

    monkeypatch.setattr(readiness, "arm_get", arm_get)
    assert readiness.resolve_endpoint_identity(
        None, "test-subscription", "test-group", "private-mi-online-endpoint"
    ) == expected
    assert calls == [(expected, "2023-01-31")]


def test_all_ten_copies_are_clean_self_contained_and_have_no_run_switches(monkeypatch, tmp_path):
    assert not (SUITE / "readiness.py").exists()
    for folder in FOLDERS:
        originals = sorted((ROOT / "workshop/notebooks" / folder).glob("*.ipynb"))
        copies = sorted((SUITE / folder).glob("*.ipynb"))
        assert [path.name for path in copies] == [path.name for path in originals]
        for path in copies:
            notebook = nbformat.read(path, as_version=4)
            nbformat.validate(notebook)
            setup = next(cell.source for cell in notebook.cells if cell.cell_type == "code")
            assert "class Settings" not in setup
            assert "def load_settings" not in setup
            assert "def connect(" not in setup
            namespace = direct_startup(path, tmp_path, monkeypatch)
            assert namespace["ml_client"].workspace_name == "test-workspace"
            for cell in notebook.cells:
                if cell.cell_type != "code":
                    continue
                assert cell.outputs == []
                assert cell.execution_count is None
                tree = ast.parse(cell.source, filename=str(path))
                assert not any(
                    isinstance(node, ast.Name) and node.id in {
                        "REGISTER", "SUBMIT", "DEPLOY", "PROMOTE", "SHARE", "RUN_JOB"
                    }
                    for node in ast.walk(tree)
                )
                assert not any(
                    isinstance(node, ast.ImportFrom) and (
                        node.level or node.module == "readiness"
                    )
                    for node in ast.walk(tree)
                )
            assert "load_dotenv" not in setup
            assert "os.getenv" not in setup
            assert "os.environ" not in setup


def test_notebook_bootstrap_finds_only_the_suite_from_supported_launch_locations(monkeypatch):
    path = SUITE / "01_foundations/01_workspace_and_compute.ipynb"
    notebook = nbformat.read(path, as_version=4)
    setup = next(cell.source for cell in notebook.cells if cell.cell_type == "code")
    bootstrap = setup.split("env_path =", 1)[0]
    monkeypatch.setattr(sys, "path", list(sys.path))
    for directory in (ROOT, ROOT / "notebooks", SUITE, path.parent):
        monkeypatch.chdir(directory)
        namespace = {}
        exec(compile(bootstrap, str(path), "exec"), namespace)
        assert namespace["SUITE_ROOT"] == SUITE


def test_data_registration_uses_shared_inputs_but_writes_only_suite_outputs(tmp_path):
    path = SUITE / "01_foundations/02_register_data_asset.ipynb"
    notebook = nbformat.read(path, as_version=4)
    preparation = next(
        cell.source for cell in notebook.cells
        if cell.cell_type == "code" and cell.source.startswith("source_csv =")
    )
    calls = []

    def create(data):
        calls.append(data.name)
        return SimpleNamespace(name=data.name, version="1")

    namespace = {
        "SAMPLE_ROOT": ROOT / "workshop",
        "SUITE_ROOT": tmp_path,
        "shutil": shutil,
        "mltable": mltable,
        "Data": Data,
        "AssetTypes": AssetTypes,
        "DATA_NAME": "readiness-test-data",
        "ml_client": SimpleNamespace(data=SimpleNamespace(
            create_or_update=create,
            get=lambda name, version: SimpleNamespace(name=name, version=version),
        )),
    }
    exec(compile(preparation, str(path), "exec"), namespace)
    generated = tmp_path / "outputs/foundation_mltable"
    assert (generated / "MLTable").is_file()
    assert namespace["source_csv"] == ROOT / "workshop/data/taxi/raw/yellowTaxiData.csv"
    assert Path(namespace["data_definition"].path).resolve() == generated.resolve()
    assert calls == ["readiness-test-data"]


@pytest.mark.parametrize("filename,asset_kind,verified_name", [
    ("03_register_environment.ipynb", "environments", "verified_environment"),
    ("04_register_model.ipynb", "models", "verified_model"),
])
def test_asset_notebooks_always_register_and_verify(
    tmp_path, monkeypatch, filename, asset_kind, verified_name
):
    path = SUITE / "01_foundations" / filename
    notebook = nbformat.read(path, as_version=4)
    operation = [cell.source for cell in notebook.cells if cell.cell_type == "code"][1]
    definitions = []

    def create(definition):
        definitions.append(definition)
        return SimpleNamespace(version="7")

    def get(name, version):
        return SimpleNamespace(
            name=name, version=version, image=getattr(definitions[-1], "image", None)
        )

    operations = SimpleNamespace(create_or_update=create, get=get)
    monkeypatch.setattr(requests, "get", lambda *args, **kwargs: SimpleNamespace(status_code=200))
    namespace = {
        "SUITE_ROOT": tmp_path,
        "SAMPLE_ROOT": ROOT / "workshop",
        "ENVIRONMENT_NAME": "readiness-test-environment",
        "MODEL_NAME": "readiness-test-model",
        "ml_client": SimpleNamespace(**{asset_kind: operations}),
        "json": json,
        "textwrap": textwrap,
        "yaml": yaml,
        "Environment": Environment,
        "Model": Model,
        "AssetTypes": AssetTypes,
    }
    exec(compile(operation, str(path), "exec"), namespace)
    assert len(definitions) == 1
    assert namespace[verified_name].version == "7"


def test_integration_submits_the_six_step_registry_pipeline_without_a_flag():
    path = SUITE / "02_jobs_and_pipelines/02_submit_integration_compare.ipynb"
    notebook = nbformat.read(path, as_version=4)
    submission = next(
        cell.source for cell in notebook.cells
        if cell.cell_type == "code" and cell.source.startswith("job = load_job(")
    )
    submitted = []
    streamed = []
    jobs = SimpleNamespace(
        create_or_update=lambda job: (
            submitted.append(job) or SimpleNamespace(name="readiness-pipeline")
        ),
        stream=lambda name: streamed.append(name),
        get=lambda name: SimpleNamespace(status="Completed", outputs={}),
        list=lambda parent_job_name: [
            SimpleNamespace(name="child", display_name="register_job", status="Completed")
        ],
    )
    namespace = {
        "load_job": load_job,
        "pipeline_path": ROOT / "workshop/pipelines/integration-compare-pipeline.yaml",
        "COMPUTE_NAME": "cluster07",
        "COMPUTE_IDENTITY_CLIENT_ID": "cluster-client",
        "OUTPUT_DATASTORE": "workspaceblobstore",
        "REGISTRY_NAME": "registry06",
        "ManagedIdentityConfiguration": ManagedIdentityConfiguration,
        "ml_client": SimpleNamespace(jobs=jobs),
        "pd": __import__("pandas"),
        "display": lambda value: None,
    }
    exec(compile(submission, str(path), "exec"), namespace)
    job = namespace["job"]
    assert job._validate().passed
    assert len(job.jobs) == 6
    assert job.inputs["registry"].result() == "registry06"
    assert job.jobs["register_job"].identity.client_id == "cluster-client"
    assert submitted == [job]
    assert streamed == ["readiness-pipeline"]


@pytest.fixture
def sharing():
    path = SUITE / "01_foundations/08_register_assets_to_registry.ipynb"
    notebook = nbformat.read(path, as_version=4)
    code = "\n".join(cell.source for cell in notebook.cells if cell.cell_type == "code")
    nodes = [
        node for node in ast.parse(code).body
        if isinstance(node, ast.FunctionDef)
        and node.name in {"resolve_workspace_assets", "share_workspace_assets"}
    ]
    namespace = {"ResourceNotFoundError": sharing_tests.AssetNotFoundError}
    exec(
        compile(
            ast.Module(body=nodes, type_ignores=[]), str(path), "exec",
            flags=__future__.annotations.compiler_flag,
        ),
        namespace,
    )
    return namespace


def test_sharing_runs_and_verifies_all_assets_without_a_flag(sharing):
    workspace, registry, settings = sharing_tests.clients_and_settings()
    settings["REGISTRY_MODEL_TARGET_VERSION"] = "release-1"
    assets = sharing["resolve_workspace_assets"](
        workspace, ["model", "environment", "data"], settings
    )
    results = sharing["share_workspace_assets"](workspace, registry, "external", assets)
    assert workspace.models.shares[0]["share_with_version"] == "release-1"
    assert len(workspace.environments.shares) == 1
    assert len(workspace.data.shares) == 1
    assert all(result["status"] == "registered" for result in results)
    assert all(result["id"].startswith("azureml://registries/external/") for result in results)


def test_existing_destination_still_stops_before_any_registration(sharing):
    workspace, registry, settings = sharing_tests.clients_and_settings()
    assets = sharing["resolve_workspace_assets"](workspace, ["model", "environment"], settings)
    registry.environments.assets["workshop-environment", "7"] = SimpleNamespace(
        name="workshop-environment", version="7", id="existing"
    )
    with pytest.raises(ValueError, match="already exist"):
        sharing["share_workspace_assets"](workspace, registry, "external", assets)
    assert workspace.models.shares == []
    assert workspace.environments.shares == []


def test_sharing_permission_errors_are_not_treated_as_missing_assets(sharing):
    workspace, registry, settings = sharing_tests.clients_and_settings()
    assets = sharing["resolve_workspace_assets"](workspace, ["model"], settings)

    def denied(*args, **kwargs):
        raise PermissionError("registry access denied")

    registry.models.get = denied
    with pytest.raises(PermissionError, match="registry access denied"):
        sharing["share_workspace_assets"](workspace, registry, "external", assets)
    assert workspace.models.shares == []


def test_incorrect_sharing_readback_is_still_an_error(sharing):
    workspace, registry, settings = sharing_tests.clients_and_settings()
    assets = sharing["resolve_workspace_assets"](workspace, ["model"], settings)
    workspace.models.corrupt_readback = True
    with pytest.raises(RuntimeError, match="readback"):
        sharing["share_workspace_assets"](workspace, registry, "external", assets)


def test_explicit_source_versions_and_invalid_selections_remain_checked(sharing):
    workspace, _, settings = sharing_tests.clients_and_settings()
    settings["REGISTRY_DATA_SOURCE_VERSION"] = "7"
    assets = sharing["resolve_workspace_assets"](workspace, ["data"], settings)
    assert assets[0]["source_version"] == "7"
    assert workspace.data.reads == [("workshop-data", "7", None)]
    for selection in ([], ["component"], ["model", "model"]):
        with pytest.raises(ValueError):
            sharing["resolve_workspace_assets"](workspace, selection, settings)
