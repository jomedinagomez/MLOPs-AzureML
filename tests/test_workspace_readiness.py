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
from azure.ai.ml import Input, Output, command, load_job
from azure.ai.ml.constants import AssetTypes, ListViewType, ManagedServiceIdentityType
from azure.ai.ml.entities import (
    AmlCompute, Data, Environment, IdentityConfiguration,
    ManagedIdentityConfiguration, Model,
    CodeConfiguration, ManagedOnlineDeployment, ManagedOnlineEndpoint,
)
from azure.core.exceptions import ResourceNotFoundError

import test_registry_asset_sharing as sharing_tests


ROOT = Path(__file__).resolve().parents[1]
SUITE = ROOT / "notebooks/workspace_readiness"
FOLDERS = ("01_foundations", "02_jobs_and_pipelines")
ENV_VALUES = {
    "AZURE_SUBSCRIPTION_ID": "test-subscription",
    "AZURE_RESOURCE_GROUP": "test-group",
    "AZUREML_WORKSPACE_NAME": "test-workspace",
    "AZUREML_REGISTRY_NAME": "test-registry",
    "USE_MANAGED_IDENTITY": "true",
}
COMPUTE_CLIENT_ID = "00000000-0000-0000-0000-000000000001"
COMMAND_ENV_VALUES = {
    **ENV_VALUES,
    "AZUREML_COMPUTE_NAME": "ccncus07",
    "AZUREML_COMPUTE_IDENTITY_CLIENT_ID": COMPUTE_CLIENT_ID,
}
COMPUTE_NOTEBOOKS = (
    "01_foundations/01_workspace_and_compute.ipynb",
)
JOB_NOTEBOOKS = (
    SUITE / "01_foundations/05_submit_command_job.ipynb",
    SUITE / "02_jobs_and_pipelines/01_submit_single_step_merge.ipynb",
    SUITE / "02_jobs_and_pipelines/02_submit_integration_compare.ipynb",
)
SYSTEM_ENDPOINT_NOTEBOOKS = (
    SUITE / "01_foundations/06_deploy_online_endpoint.ipynb",
    SUITE / "01_foundations/09_deploy_registry_online_endpoint.ipynb",
)


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
            datastores=SimpleNamespace(
                get_default=lambda: SimpleNamespace(name="workspaceblobstore"),
            ),
        )

    monkeypatch.setattr("azure.ai.ml.MLClient", client)
    namespace = {"__vsc_ipynb_file__": str(suite / path.relative_to(SUITE))}
    exec(compile(prefix, str(path), "exec"), namespace)
    return namespace


def test_configuration_is_isolated_from_process_and_parent_environments(
    tmp_path, monkeypatch
):
    monkeypatch.setenv("AZUREML_WORKSPACE_NAME", "wrong-inherited-workspace")
    monkeypatch.setenv("AZUREML_COMPUTE_NAME", "wrong-inherited-compute")
    monkeypatch.setenv("AZUREML_COMPUTE_IDENTITY_CLIENT_ID", "wrong-inherited-client")
    monkeypatch.setenv("DEPLOY_FOUNDATION_ENDPOINT", "true")
    namespace = direct_startup(
        SUITE / "01_foundations/02_register_data_asset.ipynb", tmp_path, monkeypatch
    )
    assert namespace["ml_client"].workspace_name == "test-workspace"
    assert namespace["REGISTRY_NAME"] == "test-registry"
    assert namespace["ml_client"].resource_group_name == "test-group"
    assert namespace["ml_client"].subscription_id == "test-subscription"
    assert namespace["ml_client"].credential is namespace["credential"]
    assert namespace["COMPUTE_NAME"] is None
    assert namespace["COMPUTE_IDENTITY_CLIENT_ID"] is None
    assert os.environ["AZUREML_WORKSPACE_NAME"] == "wrong-inherited-workspace"
    assert os.environ["AZUREML_COMPUTE_NAME"] == "wrong-inherited-compute"
    assert os.environ["AZUREML_COMPUTE_IDENTITY_CLIENT_ID"] == "wrong-inherited-client"


@pytest.mark.parametrize("configured_name,expected", [
    ("ccncus07", "ccncus07"),
    (" ccncus07 ", "ccncus07"),
    ("", None),
    ("   ", None),
    (None, None),
])
def test_notebooks_accept_an_optional_compute_name(
    tmp_path, monkeypatch, configured_name, expected
):
    values = dict(ENV_VALUES)
    if configured_name is not None:
        values["AZUREML_COMPUTE_NAME"] = configured_name
    for folder in FOLDERS:
        for path in sorted((SUITE / folder).glob("*.ipynb")):
            if path in JOB_NOTEBOOKS or path in SYSTEM_ENDPOINT_NOTEBOOKS:
                continue
            namespace = direct_startup(path, tmp_path, monkeypatch, values)
            assert namespace["COMPUTE_NAME"] == expected, str(path)


def test_notebooks_accept_the_configured_identity_client_id(tmp_path, monkeypatch):
    values = {
        **ENV_VALUES, "AZUREML_COMPUTE_IDENTITY_CLIENT_ID": f" {COMPUTE_CLIENT_ID} ",
    }
    for folder in FOLDERS:
        for path in sorted((SUITE / folder).glob("*.ipynb")):
            if path in SYSTEM_ENDPOINT_NOTEBOOKS:
                continue
            settings = {**values, "AZUREML_COMPUTE_NAME": "ccncus07"}
            namespace = direct_startup(path, tmp_path, monkeypatch, settings)
            assert namespace["COMPUTE_IDENTITY_CLIENT_ID"] == COMPUTE_CLIENT_ID, str(path)


@pytest.mark.parametrize("flag", ["true", "false"])
def test_authentication_toggle_applies_to_every_notebook(tmp_path, monkeypatch, flag):
    managed, cli = object(), object()
    monkeypatch.setattr("azure.identity.ManagedIdentityCredential", lambda **kwargs: managed)
    monkeypatch.setattr("azure.identity.AzureCliCredential", lambda **kwargs: cli)
    values = {**COMMAND_ENV_VALUES, "USE_MANAGED_IDENTITY": flag}
    for folder in FOLDERS:
        for path in sorted((SUITE / folder).glob("*.ipynb")):
            namespace = direct_startup(path, tmp_path, monkeypatch, values)
            assert namespace["credential"] is (managed if flag == "true" else cli), str(path)


@pytest.mark.parametrize("flag", ["", "yes", "1", "None"])
def test_invalid_authentication_toggle_is_explicit(tmp_path, monkeypatch, flag):
    values = {**COMMAND_ENV_VALUES, "USE_MANAGED_IDENTITY": flag}
    for folder in FOLDERS:
        for path in sorted((SUITE / folder).glob("*.ipynb")):
            with pytest.raises(ValueError, match="USE_MANAGED_IDENTITY"):
                direct_startup(path, tmp_path, monkeypatch, values)


@pytest.mark.parametrize("placeholder", [
    "<COMPUTE_NAME>",
    "${AZUREML_COMPUTE_NAME}",
])
def test_compute_placeholders_are_rejected(tmp_path, monkeypatch, placeholder):
    with pytest.raises(ValueError, match="placeholders"):
        direct_startup(
            SUITE / "01_foundations/01_workspace_and_compute.ipynb",
            tmp_path, monkeypatch,
            {**ENV_VALUES, "AZUREML_COMPUTE_NAME": placeholder},
        )


@pytest.mark.parametrize("placeholder", [
    "<CLIENT_ID>",
    "${AZUREML_COMPUTE_IDENTITY_CLIENT_ID}",
])
def test_identity_client_id_placeholders_are_rejected(tmp_path, monkeypatch, placeholder):
    with pytest.raises(ValueError, match="placeholders"):
        direct_startup(
            SUITE / "01_foundations/01_workspace_and_compute.ipynb",
            tmp_path, monkeypatch,
            {**ENV_VALUES, "AZUREML_COMPUTE_IDENTITY_CLIENT_ID": placeholder},
        )


@pytest.mark.parametrize("missing_key", [
    "AZURE_SUBSCRIPTION_ID", "AZURE_RESOURCE_GROUP", "AZUREML_WORKSPACE_NAME",
    "AZUREML_COMPUTE_NAME", "AZUREML_COMPUTE_IDENTITY_CLIENT_ID",
])
@pytest.mark.parametrize("empty_value", [None, "", "   "])
def test_required_coordinates_remain_required(
    tmp_path, monkeypatch, missing_key, empty_value
):
    values = dict(COMMAND_ENV_VALUES)
    if empty_value is None:
        values.pop(missing_key)
    else:
        values[missing_key] = empty_value
    with pytest.raises(ValueError, match=r"\.env"):
        direct_startup(
            SUITE / "01_foundations/05_submit_command_job.ipynb",
            tmp_path, monkeypatch, values,
        )


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
    assert keys == set(ENV_VALUES) | {
        "AZUREML_COMPUTE_NAME", "AZUREML_COMPUTE_IDENTITY_CLIENT_ID",
    }


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


@pytest.mark.parametrize("relative_path", COMPUTE_NOTEBOOKS)
@pytest.mark.parametrize("configured_name", ["ccncus07", None])
def test_compute_configuration_reaches_cluster_selection(
    tmp_path, monkeypatch, relative_path, configured_name
):
    path = SUITE / relative_path
    values = {**ENV_VALUES, "AZUREML_COMPUTE_IDENTITY_CLIENT_ID": COMPUTE_CLIENT_ID}
    if configured_name is not None:
        values["AZUREML_COMPUTE_NAME"] = configured_name
    namespace = direct_startup(path, tmp_path, monkeypatch, values)
    compute = cluster("ccncus07", [])
    listed = []
    requested = []

    def list_computes():
        listed.append(True)
        return [compute]

    def get_compute(name):
        requested.append(name)
        assert name == "ccncus07"
        return compute

    namespace["ml_client"].compute = SimpleNamespace(
        list=list_computes, get=get_compute,
    )
    namespace["ml_client"].datastores = SimpleNamespace(
        get_default=lambda: SimpleNamespace(name="workspaceblobstore"),
    )
    notebook = nbformat.read(path, as_version=4)
    source = next(cell.source for cell in notebook.cells if cell.cell_type == "code")
    remaining_setup = "ASSET_NAMES =" + source.split("ASSET_NAMES =", 1)[1]
    exec(compile(remaining_setup, str(path), "exec"), namespace)
    assert namespace["COMPUTE_NAME"] == "ccncus07"
    assert namespace["COMPUTE_IDENTITY_CLIENT_ID"] == COMPUTE_CLIENT_ID
    assert requested == ["ccncus07"]
    assert listed == ([] if configured_name else [True])


@pytest.mark.parametrize("path", JOB_NOTEBOOKS, ids=lambda path: path.stem)
def test_command_setup_is_short_and_uses_configured_inputs(tmp_path, monkeypatch, path):
    namespace = direct_startup(path, tmp_path, monkeypatch, COMMAND_ENV_VALUES)
    assert namespace["COMPUTE_NAME"] == "ccncus07"
    assert namespace["COMPUTE_IDENTITY_CLIENT_ID"] == COMPUTE_CLIENT_ID
    if path.name == "02_submit_integration_compare.ipynb":
        assert namespace["OUTPUT_DATASTORE"] == "workspaceblobstore"
    assert namespace["SUITE_ROOT"] == tmp_path / "workspace_readiness"
    notebook = nbformat.read(path, as_version=4)
    source = next(cell.source for cell in notebook.cells if cell.cell_type == "code")
    assert len(source.splitlines()) <= 35
    assert not any(
        isinstance(node, (ast.Assert, ast.FunctionDef)) for node in ast.walk(ast.parse(source))
    )
    assert "arm_get" not in source
    assert ".compute.get(" not in source
    assert ".compute.list(" not in source


def test_command_job_preparation_uses_configured_identity_without_submission(tmp_path):
    path = SUITE / "01_foundations/05_submit_command_job.ipynb"
    notebook = nbformat.read(path, as_version=4)
    preparation = next(
        cell.source for cell in notebook.cells
        if cell.cell_type == "code" and cell.source.startswith("generated_code_dir =")
    )
    namespace = {
        "SUITE_ROOT": tmp_path,
        "SAMPLE_ROOT": ROOT / "workshop",
        "EXPERIMENT_NAME": "workspace-readiness",
        "COMPUTE_NAME": "ccncus07",
        "COMPUTE_IDENTITY_CLIENT_ID": COMPUTE_CLIENT_ID,
        "ast": ast,
        "textwrap": textwrap,
        "command": command,
        "Input": Input,
        "Output": Output,
        "AssetTypes": AssetTypes,
        "ManagedIdentityConfiguration": ManagedIdentityConfiguration,
    }
    exec(compile(preparation, str(path), "exec"), namespace)
    job = namespace["job"]
    assert job.compute == "ccncus07"
    assert job.identity.client_id == COMPUTE_CLIENT_ID
    assert job._validate().passed


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


def test_compute_identity_permission_errors_are_not_bypassed(readiness, monkeypatch):
    identity = SimpleNamespace(client_id=None, resource_id="/identities/cluster")

    def denied(*args, **kwargs):
        raise requests.HTTPError("403 Forbidden")

    monkeypatch.setattr(readiness, "arm_get", denied)
    with pytest.raises(requests.HTTPError, match="403 Forbidden"):
        readiness.resolve_cluster(
            compute_client([cluster("ccncus07", [identity])]), None, "ccncus07"
        )


@pytest.mark.parametrize("path", SYSTEM_ENDPOINT_NOTEBOOKS, ids=lambda path: path.stem)
def test_endpoint_definitions_are_private_system_assigned(path):
    notebook = nbformat.read(path, as_version=4)
    nbformat.validate(notebook)
    preparation = next(
        cell.source for cell in notebook.cells
        if cell.cell_type == "code" and "endpoint_definition = ManagedOnlineEndpoint(" in cell.source
    )
    assignment = next(
        node for node in ast.parse(preparation).body
        if isinstance(node, ast.Assign)
        and any(isinstance(target, ast.Name) and target.id == "endpoint_definition"
                for target in node.targets)
    )
    namespace = {
        "ENDPOINT_NAME": "test-readiness-sami",
        "PUBLIC_ACCESS": "disabled",
        "ManagedOnlineEndpoint": ManagedOnlineEndpoint,
        "IdentityConfiguration": IdentityConfiguration,
        "ManagedServiceIdentityType": ManagedServiceIdentityType,
    }
    exec(compile(ast.Module(body=[assignment], type_ignores=[]), str(path), "exec"), namespace)
    endpoint = namespace["endpoint_definition"]
    assert endpoint.identity.type == "system_assigned"
    assert endpoint.identity._to_online_endpoint_rest_object().type == ManagedServiceIdentityType.SYSTEM_ASSIGNED
    assert not endpoint.identity.user_assigned_identities
    assert endpoint.auth_mode == "aad_token"
    assert endpoint.public_network_access == "disabled"


@pytest.mark.parametrize("path", SYSTEM_ENDPOINT_NOTEBOOKS, ids=lambda path: path.stem)
def test_existing_user_assigned_endpoint_is_not_modified(path):
    notebook = nbformat.read(path, as_version=4)
    creation = next(
        cell.source for cell in notebook.cells
        if cell.cell_type == "code" and cell.source.startswith("try:\n")
    )
    existing = SimpleNamespace(
        name="test-readiness-sami",
        identity=SimpleNamespace(type=ManagedServiceIdentityType.USER_ASSIGNED)
    )
    namespace = {
        "ENDPOINT_NAME": "test-readiness-sami",
        "ManagedServiceIdentityType": ManagedServiceIdentityType,
        "ResourceNotFoundError": ResourceNotFoundError,
        "ml_client": SimpleNamespace(
            online_endpoints=SimpleNamespace(get=lambda name: existing)
        ),
    }
    with pytest.raises(ValueError, match="new ENDPOINT_NAME"):
        exec(compile(creation, str(path), "exec"), namespace)


@pytest.mark.parametrize("path", SYSTEM_ENDPOINT_NOTEBOOKS, ids=lambda path: path.stem)
@pytest.mark.parametrize("input_type,readback_type", [
    ("system_assigned", "system_assigned"),
    (ManagedServiceIdentityType.SYSTEM_ASSIGNED, "systemassigned"),
])
def test_system_assigned_endpoint_sdk_readback_is_accepted(path, input_type, readback_type):
    notebook = nbformat.read(path, as_version=4)
    creation = next(
        cell.source for cell in notebook.cells
        if cell.cell_type == "code" and cell.source.startswith("try:\n")
    )
    definition = IdentityConfiguration(type=input_type)
    identity = IdentityConfiguration._from_online_endpoint_rest_object(
        definition._to_online_endpoint_rest_object()
    )
    assert identity.type == readback_type
    existing = SimpleNamespace(name="test-readiness-sami", identity=identity)
    namespace = {
        "ENDPOINT_NAME": existing.name,
        "ResourceNotFoundError": ResourceNotFoundError,
        "ml_client": SimpleNamespace(
            online_endpoints=SimpleNamespace(get=lambda name: existing)
        ),
    }
    exec(compile(creation, str(path), "exec"), namespace)
    assert namespace["endpoint"] is existing


def test_registry_endpoint_pins_both_external_assets(tmp_path):
    path = SUITE / "01_foundations/09_deploy_registry_online_endpoint.ipynb"
    notebook = nbformat.read(path, as_version=4)
    sources = [cell.source for cell in notebook.cells if cell.cell_type == "code"]
    assets = next(source for source in sources if "registry_client = MLClient(" in source)
    preparation = next(source for source in sources if source.startswith("generated_dir ="))
    reads = []

    def get_model(name, label):
        reads.append(("model", name, label))
        return SimpleNamespace(version="12")

    def get_environment(name, label):
        reads.append(("environment", name, label))
        return SimpleNamespace(version="8")

    registry = SimpleNamespace(
        models=SimpleNamespace(get=get_model),
        environments=SimpleNamespace(get=get_environment),
    )
    namespace = {
        "WORKSPACE_NAME": "test-workspace",
        "REGISTRY_NAME": "external-registry",
        "credential": object(),
        "MLClient": lambda **kwargs: registry,
        "SUITE_ROOT": tmp_path,
        "ast": ast,
        "json": json,
        "textwrap": textwrap,
        "ManagedServiceIdentityType": ManagedServiceIdentityType,
        "IdentityConfiguration": IdentityConfiguration,
        "ManagedOnlineEndpoint": ManagedOnlineEndpoint,
        "ManagedOnlineDeployment": ManagedOnlineDeployment,
        "CodeConfiguration": CodeConfiguration,
    }
    exec(compile(assets, str(path), "exec"), namespace)
    exec(compile(preparation, str(path), "exec"), namespace)
    payload = namespace["deployment_definition"]._to_dict()
    assert payload["model"] == (
        "azureml://registries/external-registry/models/readiness-taxi-model/versions/12"
    )
    assert payload["environment"] == (
        "azureml://registries/external-registry/environments/readiness-taxi-environment/versions/8"
    )
    assert reads == [
        ("model", "readiness-taxi-model", "latest"),
        ("environment", "readiness-taxi-environment", "latest"),
    ]


@pytest.mark.parametrize("status", [
    "Starting", "Running", "Failed", "Canceled", "NotResponding", "Completed",
])
def test_command_output_retrieval_never_resubmits(tmp_path, status, capsys, monkeypatch):
    path = SUITE / "01_foundations/05_submit_command_job.ipynb"
    notebook = nbformat.read(path, as_version=4)
    outputs = next(
        cell.source for cell in notebook.cells
        if cell.cell_type == "code" and "ml_client.jobs.download(" in cell.source
    )
    final_job = SimpleNamespace(
        name="existing-run", status=status,
        outputs={"output_data": SimpleNamespace(path=None)},
    )
    downloads = []
    states = iter([status, "Completed"])

    def get_job(name):
        final_job.status = next(states, "Completed")
        return final_job

    monkeypatch.setattr("time.sleep", lambda seconds: None)

    def download(name, output_name, download_path):
        downloads.append((name, output_name))
        target = download_path / "named-outputs/output_data/summary.json"
        target.parent.mkdir(parents=True)
        target.write_text('{"row_count": 2, "column_count": 1, "columns": ["x"]}')

    namespace = {
        "JOB_NAME": "existing-run",
        "SUITE_ROOT": tmp_path,
        "json": json,
        "ml_client": SimpleNamespace(jobs=SimpleNamespace(
            get=get_job, download=download,
        )),
    }
    if status in {"Failed", "Canceled", "NotResponding"}:
        with pytest.raises(RuntimeError, match=status):
            exec(compile(outputs, str(path), "exec"), namespace)
        assert downloads == []
    else:
        exec(compile(outputs, str(path), "exec"), namespace)
        assert downloads == [("existing-run", "output_data")]
        assert namespace["summary"] == {
            "row_count": 2, "column_count": 1, "columns": ["x"],
        }
        assert "Output URI: None" not in capsys.readouterr().out


@pytest.mark.parametrize("path", JOB_NOTEBOOKS, ids=lambda path: path.stem)
def test_job_status_and_output_cells_never_stream_or_submit(path):
    notebook = nbformat.read(path, as_version=4)
    sources = [cell.source for cell in notebook.cells if cell.cell_type == "code"]
    assert "jobs.stream(" not in "\n".join(sources)
    submission = [source for source in sources if "jobs.create_or_update(" in source]
    assert len(submission) == 1
    assert len(submission[0].splitlines()) == 2
    for source in sources:
        if "jobs.get(" in source or "jobs.download(" in source:
            assert "jobs.create_or_update(" not in source


def test_all_eleven_copies_are_clean_self_contained_and_have_no_run_switches(monkeypatch, tmp_path):
    assert not (SUITE / "readiness.py").exists()
    for folder in FOLDERS:
        originals = sorted((ROOT / "workshop/notebooks" / folder).glob("*.ipynb"))
        copies = sorted((SUITE / folder).glob("*.ipynb"))
        expected = {path.name for path in originals}
        if folder == "01_foundations":
            expected.add("09_deploy_registry_online_endpoint.ipynb")
        assert {path.name for path in copies} == expected
        for path in copies:
            notebook = nbformat.read(path, as_version=4)
            nbformat.validate(notebook)
            setup = next(cell.source for cell in notebook.cells if cell.cell_type == "code")
            assert "class Settings" not in setup
            assert "def load_settings" not in setup
            assert "def connect(" not in setup
            namespace = direct_startup(path, tmp_path, monkeypatch, COMMAND_ENV_VALUES)
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
    preparation = next(
        cell.source for cell in notebook.cells
        if cell.cell_type == "code" and cell.source.startswith("job = load_job(")
    )
    submission = next(
        cell.source for cell in notebook.cells
        if cell.cell_type == "code" and cell.source.startswith("submitted_job =")
    )
    submitted = []
    jobs = SimpleNamespace(
        create_or_update=lambda job: (
            submitted.append(job) or SimpleNamespace(name="readiness-pipeline")
        ),
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
    }
    exec(compile(preparation, str(path), "exec"), namespace)
    assert submitted == []
    exec(compile(submission, str(path), "exec"), namespace)
    job = namespace["job"]
    assert job._validate().passed
    assert len(job.jobs) == 6
    assert job.inputs["registry"].result() == "registry06"
    assert job.jobs["register_job"].identity.client_id == "cluster-client"
    assert submitted == [job]


@pytest.fixture
def sharing(monkeypatch):
    path = SUITE / "01_foundations/08_register_assets_to_registry.ipynb"
    notebook = nbformat.read(path, as_version=4)
    code = "\n".join(cell.source for cell in notebook.cells if cell.cell_type == "code")
    nodes = [
        node for node in ast.parse(code).body
        if isinstance(node, ast.FunctionDef)
        and node.name in {"next_registry_version", "resolve_workspace_assets", "share_workspace_assets"}
    ]
    def list_versions(self, name, list_view_type):
        assert list_view_type == ListViewType.ALL
        return [
            asset for (asset_name, _), asset in self.assets.items()
            if asset_name == name
        ]

    monkeypatch.setattr(sharing_tests.Operations, "list", list_versions, raising=False)
    namespace = {
        "ResourceNotFoundError": sharing_tests.AssetNotFoundError,
        "ListViewType": ListViewType,
    }
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
    assets = sharing["resolve_workspace_assets"](
        workspace, ["model", "environment", "data"], settings
    )
    results = sharing["share_workspace_assets"](workspace, registry, "external", assets)
    assert workspace.models.shares[0]["share_with_version"] == "1"
    assert len(workspace.environments.shares) == 1
    assert len(workspace.data.shares) == 1
    assert all(result["status"] == "registered" for result in results)
    assert all(result["id"].startswith("azureml://registries/external/") for result in results)


def test_existing_destination_increments_versions_on_every_registration(sharing):
    workspace, registry, settings = sharing_tests.clients_and_settings()
    assets = sharing["resolve_workspace_assets"](workspace, ["model", "environment"], settings)
    registry.environments.assets["workshop-environment", "7"] = SimpleNamespace(
        name="workshop-environment", version="7", id="existing"
    )
    results = sharing["share_workspace_assets"](workspace, registry, "external", assets)
    assert [result["target_version"] for result in results] == ["1", "8"]
    results = sharing["share_workspace_assets"](workspace, registry, "external", assets)
    assert [result["target_version"] for result in results] == ["2", "9"]
    assert registry.environments.assets["workshop-environment", "7"].id == "existing"


@pytest.mark.parametrize("versions,expected", [
    ([], "1"),
    (["1", "9", "2"], "10"),
    (["release-1", "4", "v99"], "5"),
    (["release-1"], "1"),
])
def test_registry_next_version_is_numeric_and_above_existing(sharing, versions, expected):
    operations = SimpleNamespace(
        list=lambda **kwargs: [SimpleNamespace(version=version) for version in versions]
    )
    assert sharing["next_registry_version"](operations, "model") == expected


def test_missing_registry_asset_starts_at_one(sharing):
    def missing(**kwargs):
        raise sharing_tests.AssetNotFoundError("new asset")

    assert sharing["next_registry_version"](SimpleNamespace(list=missing), "model") == "1"


def test_sharing_permission_errors_are_not_treated_as_missing_assets(sharing):
    workspace, registry, settings = sharing_tests.clients_and_settings()
    assets = sharing["resolve_workspace_assets"](workspace, ["model"], settings)

    def denied(*args, **kwargs):
        raise PermissionError("registry access denied")

    registry.models.list = denied
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
