import __future__
import ast
import json
from pathlib import Path
from types import SimpleNamespace

import pytest


ROOT = Path(__file__).resolve().parents[1]
NOTEBOOK = (
    ROOT
    / "workshop/notebooks/01_foundations/08_register_assets_to_registry.ipynb"
)


class AssetNotFoundError(Exception):
    pass


class Operations:
    def __init__(self, collection):
        self.collection = collection
        self.assets = {}
        self.reads = []
        self.shares = []
        self.destination = None
        self.corrupt_readback = False

    def get(self, name, version=None, label=None):
        self.reads.append((name, version, label))
        if label == "latest":
            matches = [
                asset for (asset_name, _), asset in self.assets.items()
                if asset_name == name
            ]
            if matches:
                return matches[-1]
        if (name, version) not in self.assets:
            raise AssetNotFoundError(name)
        return self.assets[name, version]

    def share(self, **kwargs):
        self.shares.append(kwargs)
        version = kwargs["share_with_version"]
        asset = SimpleNamespace(
            name=kwargs["share_with_name"],
            version="wrong" if self.corrupt_readback else version,
            id=(
                f"azureml://registries/{kwargs['registry_name']}/"
                f"{self.collection}/{kwargs['share_with_name']}/versions/{version}"
            ),
        )
        self.destination.assets[kwargs["share_with_name"], version] = asset
        return asset


def notebook_functions():
    notebook = json.loads(NOTEBOOK.read_text(encoding="utf-8"))
    code = "\n".join(
        "".join(cell["source"])
        for cell in notebook["cells"]
        if cell["cell_type"] == "code"
    )
    functions = [
        node for node in ast.parse(code).body
        if isinstance(node, ast.FunctionDef)
    ]
    namespace = {"ResourceNotFoundError": AssetNotFoundError}
    exec(
        compile(
            ast.Module(body=functions, type_ignores=[]),
            str(NOTEBOOK),
            "exec",
            flags=__future__.annotations.compiler_flag,
        ),
        namespace,
    )
    return namespace


def clients_and_settings():
    workspace = SimpleNamespace()
    registry = SimpleNamespace()
    settings = {}
    for kind, collection in (
        ("model", "models"),
        ("environment", "environments"),
        ("data", "data"),
    ):
        source = Operations(collection)
        destination = Operations(collection)
        source.destination = destination
        name = f"workshop-{kind}"
        source.assets[name, "7"] = SimpleNamespace(
            name=name,
            version="7",
            id=f"azureml://workspaces/source/{collection}/{name}/versions/7",
        )
        setattr(workspace, collection, source)
        setattr(registry, collection, destination)
        settings[f"WORKSHOP_{kind.upper()}_NAME"] = name
    return workspace, registry, settings


def test_share_uses_resolved_versions_and_verifies_each_asset():
    functions = notebook_functions()
    workspace, registry, settings = clients_and_settings()
    settings["REGISTRY_MODEL_TARGET_VERSION"] = "release-1"
    assets = functions["resolve_workspace_assets"](
        workspace, ["model", "environment", "data"], settings
    )

    results = functions["share_workspace_assets"](
        workspace, registry, "external", assets, enabled=True
    )

    assert workspace.models.reads == [("workshop-model", None, "latest")]
    assert workspace.models.shares == [{
        "name": "workshop-model",
        "version": "7",
        "registry_name": "external",
        "share_with_name": "workshop-model",
        "share_with_version": "release-1",
    }]
    assert len(workspace.environments.shares) == 1
    assert len(workspace.data.shares) == 1
    assert len(registry.models.reads) == 2
    assert len(registry.environments.reads) == 2
    assert len(registry.data.reads) == 2
    assert all(result["status"] == "registered" for result in results)
    assert all(result["id"].startswith("azureml://registries/external/") for result in results)


def test_preview_never_registers_assets():
    functions = notebook_functions()
    workspace, registry, settings = clients_and_settings()
    assets = functions["resolve_workspace_assets"](workspace, ["model"], settings)

    results = functions["share_workspace_assets"](
        workspace, registry, "external", assets, enabled=False
    )

    assert workspace.models.shares == []
    assert results[0]["status"] == "ready"


def test_existing_destination_stops_before_any_registration():
    functions = notebook_functions()
    workspace, registry, settings = clients_and_settings()
    assets = functions["resolve_workspace_assets"](
        workspace, ["model", "environment"], settings
    )
    registry.environments.assets["workshop-environment", "7"] = SimpleNamespace(
        name="workshop-environment", version="7", id="existing"
    )

    with pytest.raises(ValueError, match="already exist"):
        functions["share_workspace_assets"](
            workspace, registry, "external", assets, enabled=True
        )

    assert workspace.models.shares == []
    assert workspace.environments.shares == []


def test_permission_errors_are_not_treated_as_missing_assets():
    functions = notebook_functions()
    workspace, registry, settings = clients_and_settings()
    assets = functions["resolve_workspace_assets"](workspace, ["model"], settings)

    def denied(*args, **kwargs):
        raise PermissionError("registry access denied")

    registry.models.get = denied
    with pytest.raises(PermissionError, match="registry access denied"):
        functions["share_workspace_assets"](
            workspace, registry, "external", assets, enabled=True
        )
    assert workspace.models.shares == []


def test_incorrect_readback_is_an_error():
    functions = notebook_functions()
    workspace, registry, settings = clients_and_settings()
    assets = functions["resolve_workspace_assets"](workspace, ["model"], settings)
    workspace.models.corrupt_readback = True

    with pytest.raises(RuntimeError, match="readback"):
        functions["share_workspace_assets"](
            workspace, registry, "external", assets, enabled=True
        )


def test_explicit_source_version_and_invalid_selections():
    functions = notebook_functions()
    workspace, _, settings = clients_and_settings()
    settings["REGISTRY_DATA_SOURCE_VERSION"] = "7"
    assets = functions["resolve_workspace_assets"](workspace, ["data"], settings)
    assert assets[0]["source_version"] == "7"
    assert workspace.data.reads == [("workshop-data", "7", None)]

    for selection in ([], ["component"], ["model", "model"]):
        with pytest.raises(ValueError):
            functions["resolve_workspace_assets"](workspace, selection, settings)


def test_notebook_is_clean_and_syntax_valid():
    notebook = json.loads(NOTEBOOK.read_text(encoding="utf-8"))
    for index, cell in enumerate(notebook["cells"]):
        if cell["cell_type"] == "code":
            assert cell["execution_count"] is None
            assert cell["outputs"] == []
            compile("".join(cell["source"]), f"cell-{index}", "exec")
    example = (ROOT / "workshop/.env.example").read_text(encoding="utf-8")
    assert "SHARE_FOUNDATION_ASSETS=false" in example
    assert "AZUREML_REGISTRY_NAME=" in example
