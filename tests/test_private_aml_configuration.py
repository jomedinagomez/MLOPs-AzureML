import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
ROOT = REPO_ROOT / "infra/AzureMLManagedVnet"


def hcl_block(text: str, kind: str, name: str) -> str:
    match = re.search(
        rf'{kind}\s+"{name}"\s*\{{(.*?)^\}}', text, re.MULTILINE | re.DOTALL
    )
    assert match is not None, f"Missing {kind} {name}"
    return match.group(1)


def test_registry_exceptions_do_not_implicitly_include_a_human_deployer():
    registry = hcl_block((ROOT / "main.tf").read_text(encoding="utf-8"), "module", "registry")
    assert "data.azurerm_client_config.current.object_id" not in registry
    assert "module.workspace.workspace_uami_principal_id" in registry
    assert "var.registry_managed_rg_assigned_principal_ids" in registry


def test_default_purpose_satisfies_its_validation():
    purpose = hcl_block(
        (ROOT / "variables.tf").read_text(encoding="utf-8"), "variable", "purpose"
    )
    default = re.search(r'default\s*=\s*"([^"]+)"', purpose).group(1)
    pattern = re.search(r'regex\("([^"]+)"', purpose).group(1)
    assert re.fullmatch(pattern, default)


def test_compute_names_fit_limits_at_maximum_input_lengths():
    workspace = hcl_block((ROOT / "main.tf").read_text(encoding="utf-8"), "module", "workspace")
    for field in ("compute_cluster_name", "compute_instance_name"):
        template = re.search(rf'{field}\s*=\s*"([^"]+)"', workspace).group(1)
        name = template.replace("${var.location_code}", "x" * 6).replace(
            "${var.naming_suffix}", "x" * 8
        )
        assert "${" not in name
        assert re.fullmatch(r"[a-z][a-z0-9]{2,15}", name)


def test_development_vault_has_soft_delete_without_purge_protection():
    main = (ROOT / "main.tf").read_text(encoding="utf-8")
    workspace = hcl_block(main, "module", "workspace")
    assert re.search(r"key_vault_purge_protection_enabled\s*=\s*false", workspace)
    assert re.search(r"enable_auto_purge\s*=\s*false", workspace)
    assert re.search(r"provision_cmk_prerequisites\s*=\s*false", workspace)
    assert re.search(r'workspace_encryption\s*=\s*"pmk"', workspace)
    assert re.search(r"purge_soft_delete_on_destroy\s*=\s*false", main)

    variables = (
        REPO_ROOT / "infra/mlops/modules/key-vault/variables.tf"
    ).read_text(encoding="utf-8")
    retention = hcl_block(variables, "variable", "soft_delete_retention_days")
    assert re.search(r"default\s*=\s*7\b", retention)


def test_workspace_destroy_does_not_run_an_implicit_purge():
    main = (
        REPO_ROOT / "infra/mlops/modules/aml-managed-umi/main.tf"
    ).read_text(encoding="utf-8")
    workspace = hcl_block(main, 'resource "azapi_resource"', "aml_workspace")
    assert "--permanently-delete" not in workspace
    assert 'provisioner "local-exec"' not in workspace


def test_managed_vnet_root_does_not_request_public_access_exceptions():
    main = (ROOT / "main.tf").read_text(encoding="utf-8")
    workspace = hcl_block(main, "module", "workspace")
    assert re.search(r"allowed_public_ip_cidrs\s*=\s*\[\]", workspace)
    assert re.search(r"asset_sharing_registry_ids\s*=\s*\[\]", workspace)
    assert "network_security_perimeter" not in main
    assert "policy_exemption" not in main


def test_private_storage_provisioning_avoids_data_plane_calls():
    main = (ROOT / "main.tf").read_text(encoding="utf-8")
    provider = hcl_block(main, "provider", "azurerm")
    assert re.search(r"data_plane_available\s*=\s*false", provider)
    workspace = hcl_block(main, "module", "workspace")
    assert re.search(r"enable_legacy_queue_logging\s*=\s*false", workspace)

    storage = (
        REPO_ROOT / "infra/mlops/modules/storage-account/main.tf"
    ).read_text(encoding="utf-8")
    legacy = hcl_block(
        storage, 'resource "azurerm_storage_account_queue_properties"', "logging"
    )
    assert re.search(r"count\s*=\s*var.enable_legacy_queue_logging\s*\?\s*1\s*:\s*0", legacy)
    diagnostics = hcl_block(
        storage, 'resource "azurerm_monitor_diagnostic_setting"', "diag-queue"
    )
    for category in ("StorageRead", "StorageWrite", "StorageDelete"):
        assert category in diagnostics


def test_customer_subnet_nsg_is_managed_in_the_same_terraform_root():
    main = (ROOT / "main.tf").read_text(encoding="utf-8")
    nsg = hcl_block(main, 'resource "azurerm_network_security_group"', "private_endpoints")
    assert "azurerm_resource_group.platform.name" in nsg
    association = hcl_block(
        main, 'resource "azurerm_subnet_network_security_group_association"', "private_endpoints"
    )
    assert "azurerm_subnet.private_endpoints.id" in association
    assert "azurerm_network_security_group.private_endpoints.id" in association


def test_managed_network_kind_is_inside_the_documented_network_settings():
    main = (
        REPO_ROOT / "infra/mlops/modules/aml-managed-umi/main.tf"
    ).read_text(encoding="utf-8")
    workspace = hcl_block(main, 'resource "azapi_resource"', "aml_workspace")
    assert re.search(
        r'managedNetwork\s*=\s*\{[^}]*managedNetworkKind\s*=\s*"V1"',
        workspace,
    )
    assert re.search(
        r"schema_validation_enabled\s*=\s*var.validate_workspace_schema", workspace
    )
    root_workspace = hcl_block(
        (ROOT / "main.tf").read_text(encoding="utf-8"), "module", "workspace"
    )
    assert re.search(r"validate_workspace_schema\s*=\s*true", root_workspace)


def test_single_workspace_and_registry_share_one_project_resource_group():
    main = (ROOT / "main.tf").read_text(encoding="utf-8")
    groups = re.findall(r'resource\s+"azurerm_resource_group"\s+"([^"]+)"', main)
    assert groups == ["platform"]
    group = hcl_block(main, 'resource "azurerm_resource_group"', "platform")
    assert "for_each" not in group
    assert re.search(r'name\s*=\s*"rg-\$\{local.name\}"', group)
    for name in ("workspace", "registry"):
        module = hcl_block(main, "module", name)
        assert re.search(
            r"resource_group_name\s*=\s*azurerm_resource_group\.platform\.name",
            module,
        )
    assert "registry_reader" not in main


def test_development_opt_out_tag_is_explicit_in_the_variable_example():
    example = (ROOT / "terraform.tfvars.example").read_text(encoding="utf-8")
    assert re.search(r'SecurityControl\s*=\s*"Ignore"', example)
    variables = (ROOT / "variables.tf").read_text(encoding="utf-8")
    assert "SecurityControl" not in hcl_block(variables, "variable", "tags")


def test_provider_supports_the_workspace_api_without_changing_shared_defaults():
    main = (ROOT / "main.tf").read_text(encoding="utf-8")
    requirement = re.search(
        r'azapi\s*=\s*\{[^}]*version\s*=\s*"([^"]+)"', main
    ).group(1)
    minimum = tuple(int(value) for value in re.search(r"\d+\.\d+", requirement).group().split("."))
    assert minimum >= (2, 13)
    variables = (
        REPO_ROOT / "infra/mlops/modules/aml-managed-umi/variables.tf"
    ).read_text(encoding="utf-8")
    validation = hcl_block(variables, "variable", "validate_workspace_schema")
    assert re.search(r"default\s*=\s*false", validation)


def test_registry_backing_resources_are_verified_without_protected_writes():
    main = (ROOT / "main.tf").read_text(encoding="utf-8")
    for name in ("registry_storage_network", "registry_acr_network"):
        assert not re.search(
            rf'resource\s+"azapi_update_resource"\s+"{name}"', main
        )
        reader = hcl_block(main, 'data "azapi_resource"', name)
        assert "postcondition" in reader
        assert re.search(
            r'self.output.properties.publicNetworkAccess\s*==\s*"Disabled"',
            reader,
        )
    for name in ("registry_network_approver", "registry_managed_reader"):
        assert not re.search(
            rf'resource\s+"azurerm_role_assignment"\s+"{name}"', main
        )


def test_registry_outbound_avoids_duplicate_backing_destinations():
    outbound = hcl_block(
        (ROOT / "main.tf").read_text(encoding="utf-8"),
        'resource "azapi_resource"',
        "registry_outbound",
    )
    destinations = re.search(
        r"for_each\s*=\s*\{(.*?)^\s{2}\}", outbound, re.MULTILINE | re.DOTALL
    ).group(1)
    keys = re.findall(r"^\s+(\w+)\s*=", destinations, re.MULTILINE)
    assert keys == ["registry"], (
        "The registry target resolves its backing endpoints; separate blob/ACR "
        "rules cause Azure's duplicate-destination validation error."
    )
    assert re.search(
        r'registry\s*=\s*\{\s*id\s*=\s*module\.registry\.registry_id,\s*'
        r'target\s*=\s*"amlregistry"\s*\}',
        destinations,
    )


def test_private_workspace_defers_network_provisioning_until_after_its_endpoint():
    root = hcl_block(
        (ROOT / "main.tf").read_text(encoding="utf-8"), "module", "workspace"
    )
    assert re.search(r"provision_network_now\s*=\s*false", root)
    shared = (
        REPO_ROOT / "infra/mlops/modules/aml-managed-umi/main.tf"
    ).read_text(encoding="utf-8")
    workspace = hcl_block(shared, 'resource "azapi_resource"', "aml_workspace")
    assert re.search(r"provisionNetworkNow\s*=\s*var.provision_network_now", workspace)
    for name in ("compute_cluster_uami", "compute_instance_uami"):
        compute = hcl_block(shared, 'resource "azapi_resource"', name)
        assert "module.private_endpoint_aml_workspace" in compute
    variables = (
        REPO_ROOT / "infra/mlops/modules/aml-managed-umi/variables.tf"
    ).read_text(encoding="utf-8")
    assert re.search(
        r"default\s*=\s*true",
        hcl_block(variables, "variable", "provision_network_now"),
    )
