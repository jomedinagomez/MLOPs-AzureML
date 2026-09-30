[CmdletBinding()]
param(
    [Parameter()]
    [string]$TerraformDirectory = (Split-Path -Parent $PSScriptRoot),

    [Parameter()]
    [string]$PlanPath = "tfplan"
)

$ErrorActionPreference = "Stop"

function Assert-PlanCondition {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "Plan validation failed: $Message"
    }

    Write-Host "PASS: $Message" -ForegroundColor Green
}

$resolvedTerraformDirectory = (Resolve-Path -LiteralPath $TerraformDirectory).Path
$resolvedPlanPath = if ([System.IO.Path]::IsPathRooted($PlanPath)) {
    (Resolve-Path -LiteralPath $PlanPath).Path
}
else {
    (Resolve-Path -LiteralPath (Join-Path $resolvedTerraformDirectory $PlanPath)).Path
}

$planJson = & terraform "-chdir=$resolvedTerraformDirectory" show -json $resolvedPlanPath
if ($LASTEXITCODE -ne 0) {
    throw "terraform show failed with exit code $LASTEXITCODE."
}

$plan = $planJson | ConvertFrom-Json -Depth 100
$resources = @($plan.resource_changes)

$expectedSubscription = "5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25"
$expectedLocation = "canadacentral"
$expectedPurpose = "spark"
$expectedSuffix = "03"

Assert-PlanCondition -Condition ($plan.variables.subscription_id.value -eq $expectedSubscription) -Message "Plan targets the confirmed subscription"
Assert-PlanCondition -Condition ($plan.variables.location.value -eq $expectedLocation) -Message "Plan targets Canada Central"
Assert-PlanCondition -Condition ($plan.variables.location_code.value -eq "cc") -Message "Plan uses the Canada Central location code"
Assert-PlanCondition -Condition ($plan.variables.purpose.value -eq $expectedPurpose) -Message "Plan purpose is spark"
Assert-PlanCondition -Condition ($plan.variables.naming_suffix.value -eq $expectedSuffix) -Message "Plan suffix is 03"
Assert-PlanCondition -Condition ($plan.variables.tags.value.SecurityControl -eq "Ignore") -Message "SecurityControl=Ignore is mandatory"
Assert-PlanCondition -Condition ($plan.variables.create_compute_resources.value -eq $false) -Message "Phase 1 defers compute creation until Spark networking is ready"

$deleteActions = @($resources | Where-Object { $_.change.actions -contains "delete" })
Assert-PlanCondition -Condition ($deleteActions.Count -eq 0) -Message "Plan contains no delete or replacement actions"

$managedNonCreates = @(
    $resources | Where-Object {
        $_.mode -eq "managed" -and
        $_.change.actions -notcontains "create"
    }
)
Assert-PlanCondition -Condition ($managedNonCreates.Count -eq 0) -Message "Every managed resource action is create-only"

$requiredAddresses = @(
    "azurerm_resource_group.workspace",
    "module.workspace.azapi_resource.aml_workspace",
    "module.workspace.terraform_data.linked_service_network_policy",
    "module.workspace.azurerm_key_vault.cmk[0]",
    "module.workspace.azapi_resource.workspace_cmk[0]",
    "module.workspace.azapi_resource.storage_encryption_scope[0]"
)

foreach ($address in $requiredAddresses) {
    $matchingResource = @($resources | Where-Object { $_.address -eq $address })
    Assert-PlanCondition -Condition ($matchingResource.Count -eq 1) -Message "Required resource is planned: $address"
}

$workspaceResources = @(
    $resources | Where-Object {
        $_.type -eq "azapi_resource" -and
        $_.change.after.type -like "Microsoft.MachineLearningServices/workspaces@*"
    }
)
Assert-PlanCondition -Condition ($workspaceResources.Count -eq 1) -Message "Exactly one Azure ML workspace is planned"

$registryResources = @(
    $resources | Where-Object {
        $_.type -eq "azapi_resource" -and
        $_.change.after.type -like "Microsoft.MachineLearningServices/registries@*"
    }
)
Assert-PlanCondition -Condition ($registryResources.Count -eq 0) -Message "No Azure ML registry is planned"

$forbiddenTypes = @(
    "azurerm_virtual_network",
    "azurerm_subnet",
    "azurerm_private_endpoint",
    "azurerm_private_dns_zone",
    "azurerm_private_dns_zone_virtual_network_link",
    "azurerm_bastion_host",
    "azurerm_windows_virtual_machine",
    "azurerm_linux_virtual_machine"
)

$forbiddenResources = @($resources | Where-Object { $_.type -in $forbiddenTypes })
Assert-PlanCondition -Condition ($forbiddenResources.Count -eq 0) -Message "No customer-managed network, Bastion, or VM resources are planned"

$resourceGroups = @($resources | Where-Object { $_.type -eq "azurerm_resource_group" })
Assert-PlanCondition -Condition ($resourceGroups.Count -eq 1) -Message "Exactly one resource group is planned"
Assert-PlanCondition -Condition ($resourceGroups[0].change.after.name -eq "rg-aml-ws-spark-cc-03") -Message "Expected Spark resource group name is planned"

$allowedCidrs = @($plan.variables.allowed_public_ip_cidrs.value)
Assert-PlanCondition -Condition ($allowedCidrs.Count -gt 0) -Message "At least one selected public IPv4 CIDR is supplied"

$workspace = $resources | Where-Object { $_.address -eq "module.workspace.azapi_resource.aml_workspace" }
Assert-PlanCondition -Condition ($workspace.change.actions -contains "create") -Message "Replacement workspace is created in independent state"
Assert-PlanCondition -Condition ($workspace.change.after.name -eq "mlwsparkcc03") -Message "Expected Spark workspace name is planned"
Assert-PlanCondition -Condition ($workspace.change.after.body.properties.publicNetworkAccess -eq "Disabled") -Message "Workspace creation starts with public access disabled"
Assert-PlanCondition -Condition ($workspace.change.after.body.properties.managedNetwork.isolationMode -eq "AllowOnlyApprovedOutbound") -Message "AML managed network uses AllowOnlyApprovedOutbound"
Assert-PlanCondition -Condition ($workspace.change.after.body.properties.managedNetwork.firewallSku -eq "Standard") -Message "AML managed network uses Azure Firewall Standard for FQDN rules"
Assert-PlanCondition -Condition ($workspace.change.after.body.properties.encryption.status -eq "Enabled") -Message "Workspace CMK encryption is enabled"
Assert-PlanCondition -Condition ($workspace.change.after.body.properties.provisionNetworkNow -eq $false) -Message "Workspace creation defers managed-network provisioning to the visible CLI phase"

$configuredOutboundRules = $workspace.change.after.body.properties.managedNetwork.outboundRules
$configuredFqdnRules = @(
    $configuredOutboundRules.PSObject.Properties | Where-Object {
        $_.Value.type -eq "FQDN"
    }
)
Assert-PlanCondition -Condition ($configuredFqdnRules.Count -gt 0) -Message "Original FQDN outbound rules are retained"

$configuredBlobRules = @(
    $configuredOutboundRules.PSObject.Properties | Where-Object {
        $_.Value.type -eq "PrivateEndpoint" -and
        $_.Value.destination.subresourceTarget -eq "blob"
    }
)
Assert-PlanCondition -Condition ($configuredBlobRules.Count -eq 0) -Message "Phase 1 leaves the Spark-enabled Blob rule to the documented CLI patch"

$embeddedNetworkActions = @(
    $resources | Where-Object {
        $_.address -in @(
            "module.workspace.azapi_resource_action.spark_network_provisioning",
            "module.workspace.azapi_resource_action.workspace_network_acls",
            "module.workspace.terraform_data.spark_network_provisioning",
            "module.workspace.terraform_data.workspace_network_acls"
        )
    }
)
Assert-PlanCondition -Condition ($embeddedNetworkActions.Count -eq 0) -Message "Terraform does not hide Spark provisioning or ACL patching inside the apply"

$sparkStorageRole = $resources | Where-Object { $_.address -eq "module.workspace.azurerm_role_assignment.workspace_storage_contributor_for_spark" }
Assert-PlanCondition -Condition ($sparkStorageRole.change.after.role_definition_name -eq "Contributor") -Message "Workspace UAMI receives Storage Contributor for Spark"

$linkedServicePolicy = $resources | Where-Object { $_.address -eq "module.workspace.terraform_data.linked_service_network_policy" }
Assert-PlanCondition -Condition ($linkedServicePolicy.change.after.input.public_network_access -eq "EnabledForSelectedIPs") -Message "Linked Storage and Key Vault use selected-IP public access"
Assert-PlanCondition -Condition ($linkedServicePolicy.change.after.input.enforcement_source -eq "Terraform") -Message "Linked-service network policy is Terraform-owned"

$workspaceKeyVault = $resources | Where-Object { $_.address -eq "module.workspace.module.keyvault_aml.azurerm_key_vault.kv" }
$cmkKeyVault = $resources | Where-Object { $_.address -eq "module.workspace.azurerm_key_vault.cmk[0]" }
$storage = $resources | Where-Object { $_.address -eq "module.workspace.module.storage_account_default.azurerm_storage_account.storage_account" }
$acr = $resources | Where-Object { $_.address -eq "module.workspace.module.container_registry.azurerm_container_registry.acr" }
Assert-PlanCondition -Condition ($workspaceKeyVault.change.after.purge_protection_enabled -eq $false) -Message "Workspace Key Vault purge protection is disabled for the demo"
Assert-PlanCondition -Condition ($cmkKeyVault.change.after.purge_protection_enabled -eq $true) -Message "CMK Key Vault purge protection is enabled as required by Azure CMK services"
Assert-PlanCondition -Condition ($workspaceKeyVault.change.after.name -eq "kvsparkcc03") -Message "Expected workspace Key Vault name is planned"
Assert-PlanCondition -Condition ($cmkKeyVault.change.after.name -eq "kvcmksparkcc03") -Message "Expected CMK Key Vault name is planned"
Assert-PlanCondition -Condition ($storage.change.after.name -eq "stsparkcc03") -Message "Expected Storage account name is planned"
Assert-PlanCondition -Condition ($acr.change.after.name -eq "acrsparkcc03") -Message "Expected ACR name is planned"
Assert-PlanCondition -Condition ($workspaceKeyVault.change.after.public_network_access_enabled -eq $true) -Message "Workspace Key Vault selected-IP access is enabled"
Assert-PlanCondition -Condition ($cmkKeyVault.change.after.public_network_access_enabled -eq $true) -Message "CMK Key Vault selected-IP access is enabled"
Assert-PlanCondition -Condition ($storage.change.after.public_network_access_enabled -eq $true) -Message "Storage selected-IP access is enabled"
Assert-PlanCondition -Condition ($acr.change.after.public_network_access_enabled -eq $true) -Message "ACR selected-IP access is enabled"
Assert-PlanCondition -Condition ($workspaceKeyVault.change.after.network_acls[0].default_action -eq "Deny") -Message "Workspace Key Vault denies nonselected IPs"
Assert-PlanCondition -Condition ($cmkKeyVault.change.after.network_acls[0].default_action -eq "Deny") -Message "CMK Key Vault denies nonselected IPs"
Assert-PlanCondition -Condition ($storage.change.after.network_rules[0].default_action -eq "Deny") -Message "Storage denies nonselected IPs"
Assert-PlanCondition -Condition ($acr.change.after.network_rule_set[0].default_action -eq "Deny") -Message "ACR denies nonselected IPs"

$computeResources = @(
    $resources | Where-Object {
        $_.address -like "module.workspace.azapi_resource.compute_*"
    }
)
Assert-PlanCondition -Condition ($computeResources.Count -eq 0) -Message "Phase 1 does not create compute before Spark networking is ready"

$expectedNames = @{
    "azurerm_log_analytics_workspace.workspace"                                  = "log-aml-spark-cc03"
    "azurerm_user_assigned_identity.compute_cluster"                             = "spark-mi-compute"
    "azurerm_user_assigned_identity.compute_instance"                            = "spark-mi-compute-instance"
    "azurerm_user_assigned_identity.online_endpoint"                             = "spark-mi-online-endpoint"
    "module.workspace.azurerm_application_insights.aml-appins"                   = "mlwinsparkcc03"
    "module.workspace.azurerm_user_assigned_identity.workspace_identity"          = "spark-mi-workspace"
}
foreach ($entry in $expectedNames.GetEnumerator()) {
    $resource = $resources | Where-Object { $_.address -eq $entry.Key }
    Assert-PlanCondition -Condition ($resource.change.after.name -eq $entry.Value) -Message "Expected resource name is planned: $($entry.Value)"
}

$taggedAddresses = @(
    "azurerm_resource_group.workspace",
    "azurerm_log_analytics_workspace.workspace",
    "azurerm_user_assigned_identity.compute_cluster",
    "azurerm_user_assigned_identity.compute_instance",
    "azurerm_user_assigned_identity.online_endpoint",
    "module.workspace.azurerm_application_insights.aml-appins",
    "module.workspace.azurerm_user_assigned_identity.workspace_identity",
    "module.workspace.module.storage_account_default.azurerm_storage_account.storage_account",
    "module.workspace.module.keyvault_aml.azurerm_key_vault.kv",
    "module.workspace.module.container_registry.azurerm_container_registry.acr",
    "module.workspace.azurerm_key_vault.cmk[0]",
    "module.workspace.azapi_resource.aml_workspace"
)
foreach ($address in $taggedAddresses) {
    $resource = $resources | Where-Object { $_.address -eq $address }
    $tags = if ($null -ne $resource.change.after.tags) {
        $resource.change.after.tags
    }
    else {
        $resource.change.after.body.tags
    }
    Assert-PlanCondition -Condition ($tags.SecurityControl -eq "Ignore") -Message "SecurityControl=Ignore is planned on $address"
}

Write-Host "All Spark workspace Terraform plan invariants passed." -ForegroundColor Green
