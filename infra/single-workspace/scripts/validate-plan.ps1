[CmdletBinding()]
param(
    [Parameter()]
    [string]$TerraformDirectory = (Split-Path -Parent $PSScriptRoot),

    [Parameter()]
    [string]$PlanPath = "tfplan",

    [Parameter()]
    [string]$ExpectedSubscription = "5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25",

    [Parameter()]
    [string]$ExpectedLocation = "canadacentral",

    [Parameter()]
    [string]$ExpectedLocationCode = "cc",

    [Parameter()]
    [ValidateSet("spark", "public")]
    [string]$ExpectedPurpose = "spark",

    [Parameter()]
    [ValidatePattern("^[0-9]{2}$")]
    [string]$ExpectedSuffix = "03",

    [Parameter()]
    [ValidateSet("managed", "public")]
    [string]$ExpectedNetworkProfile = "managed",

    [Parameter()]
    [bool]$ExpectedCreateCompute = $false
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

function Get-PlannedResource {
    param(
        [Parameter(Mandatory)]
        [object[]]$Resources,

        [Parameter(Mandatory)]
        [string]$Address
    )

    $matches = @($Resources | Where-Object { $_.address -eq $Address })
    Assert-PlanCondition -Condition ($matches.Count -eq 1) -Message "Required resource is planned: $Address"
    return $matches[0]
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
$expectedResourceGroup = "rg-aml-ws-$ExpectedPurpose-$ExpectedLocationCode-$ExpectedSuffix"
$expectedWorkspace = "mlw$ExpectedPurpose$ExpectedLocationCode$ExpectedSuffix"
$expectedStorage = "st$ExpectedPurpose$ExpectedLocationCode$ExpectedSuffix"
$expectedAcr = "acr$ExpectedPurpose$ExpectedLocationCode$ExpectedSuffix"
$expectedWorkspaceVault = "kv$ExpectedPurpose$ExpectedLocationCode$ExpectedSuffix"
$expectedCmkVault = "kvcmk$ExpectedPurpose$ExpectedLocationCode$ExpectedSuffix"
$expectedLogAnalytics = "log-aml-$ExpectedPurpose-$ExpectedLocationCode$ExpectedSuffix"
$expectedAppInsights = "mlwin$ExpectedPurpose$ExpectedLocationCode$ExpectedSuffix"
$expectedSparkStorage = ("st{0}dl{1}04" -f $ExpectedPurpose, $ExpectedLocationCode).ToLower()
$expectedComputeInstance = if ([string]::IsNullOrWhiteSpace($plan.variables.compute_instance_name.value)) {
    "aml-instance-$ExpectedPurpose-$ExpectedLocationCode$ExpectedSuffix"
}
else {
    $plan.variables.compute_instance_name.value
}

Assert-PlanCondition -Condition ($plan.variables.subscription_id.value -eq $ExpectedSubscription) -Message "Plan targets the confirmed subscription"
Assert-PlanCondition -Condition ($plan.variables.location.value -eq $ExpectedLocation) -Message "Plan targets $ExpectedLocation"
Assert-PlanCondition -Condition ($plan.variables.location_code.value -eq $ExpectedLocationCode) -Message "Plan uses location code $ExpectedLocationCode"
Assert-PlanCondition -Condition ($plan.variables.purpose.value -eq $ExpectedPurpose) -Message "Plan purpose is $ExpectedPurpose"
Assert-PlanCondition -Condition ($plan.variables.naming_suffix.value -eq $ExpectedSuffix) -Message "Plan suffix is $ExpectedSuffix"
Assert-PlanCondition -Condition ($plan.variables.network_profile.value -eq $ExpectedNetworkProfile) -Message "Plan uses $ExpectedNetworkProfile network profile"
Assert-PlanCondition -Condition ($plan.variables.create_compute_resources.value -eq $ExpectedCreateCompute) -Message "Compute creation matches the approved phase"
Assert-PlanCondition -Condition ($plan.variables.tags.value.SecurityControl -eq "Ignore") -Message "SecurityControl=Ignore is mandatory"

$deleteActions = @($resources | Where-Object { $_.change.actions -contains "delete" })
Assert-PlanCondition -Condition ($deleteActions.Count -eq 0) -Message "Plan contains no delete or replacement actions"

$managedNonCreates = @(
    $resources | Where-Object {
        $_.mode -eq "managed" -and
        $_.change.actions -notcontains "create"
    }
)
Assert-PlanCondition -Condition ($managedNonCreates.Count -eq 0) -Message "Every managed resource action is create-only"

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

$registryResources = @(
    $resources | Where-Object {
        $_.type -eq "azapi_resource" -and
        $_.change.after.type -like "Microsoft.MachineLearningServices/registries@*"
    }
)
Assert-PlanCondition -Condition ($registryResources.Count -eq 0) -Message "No Azure ML registry is planned"

$resourceGroup = Get-PlannedResource -Resources $resources -Address "azurerm_resource_group.workspace"
Assert-PlanCondition -Condition ($resourceGroup.change.after.name -eq $expectedResourceGroup) -Message "Expected resource group name is planned"
Assert-PlanCondition -Condition ($resourceGroup.change.after.location -eq $ExpectedLocation) -Message "Resource group uses the expected location"

$workspace = Get-PlannedResource -Resources $resources -Address "module.workspace.azapi_resource.aml_workspace"
Assert-PlanCondition -Condition ($workspace.change.after.name -eq $expectedWorkspace) -Message "Expected Azure ML workspace name is planned"
Assert-PlanCondition -Condition ($workspace.change.after.location -eq $ExpectedLocation) -Message "Azure ML workspace uses the expected location"
Assert-PlanCondition -Condition ($workspace.change.after.body.properties.encryption.status -eq "Enabled") -Message "Workspace CMK encryption is enabled"
Assert-PlanCondition -Condition ($workspace.change.after.body.properties.systemDatastoresAuthMode -eq "identity") -Message "Workspace system datastores use identity authentication"

$linkedServicePolicy = Get-PlannedResource -Resources $resources -Address "module.workspace.terraform_data.linked_service_network_policy"
Assert-PlanCondition -Condition ($linkedServicePolicy.change.after.input.enforcement_source -eq "Terraform") -Message "Linked-service network policy is Terraform-owned"

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
Assert-PlanCondition -Condition ($embeddedNetworkActions.Count -eq 0) -Message "Terraform does not hide network provisioning or ACL patching inside the apply"

$workspaceKeyVault = Get-PlannedResource -Resources $resources -Address "module.workspace.module.keyvault_aml.azurerm_key_vault.kv"
$cmkKeyVault = Get-PlannedResource -Resources $resources -Address "module.workspace.azurerm_key_vault.cmk[0]"
$storage = Get-PlannedResource -Resources $resources -Address "module.workspace.module.storage_account_default.azurerm_storage_account.storage_account"
$acr = Get-PlannedResource -Resources $resources -Address "module.workspace.module.container_registry.azurerm_container_registry.acr"
$logAnalytics = Get-PlannedResource -Resources $resources -Address "azurerm_log_analytics_workspace.workspace"
$appInsights = Get-PlannedResource -Resources $resources -Address "module.workspace.azurerm_application_insights.aml-appins"
$sparkStorage = Get-PlannedResource -Resources $resources -Address "azurerm_storage_account.spark_data_lake"
$sparkFilesystem = Get-PlannedResource -Resources $resources -Address "azurerm_storage_data_lake_gen2_filesystem.spark"

Assert-PlanCondition -Condition ($workspaceKeyVault.change.after.name -eq $expectedWorkspaceVault) -Message "Expected workspace Key Vault name is planned"
Assert-PlanCondition -Condition ($cmkKeyVault.change.after.name -eq $expectedCmkVault) -Message "Expected CMK Key Vault name is planned"
Assert-PlanCondition -Condition ($storage.change.after.name -eq $expectedStorage) -Message "Expected default Storage name is planned"
Assert-PlanCondition -Condition ($acr.change.after.name -eq $expectedAcr) -Message "Expected ACR name is planned"
Assert-PlanCondition -Condition ($logAnalytics.change.after.name -eq $expectedLogAnalytics) -Message "Expected Log Analytics name is planned"
Assert-PlanCondition -Condition ($appInsights.change.after.name -eq $expectedAppInsights) -Message "Expected Application Insights name is planned"
Assert-PlanCondition -Condition ($sparkStorage.change.after.name -eq $expectedSparkStorage) -Message "Expected Spark ADLS name is planned"
Assert-PlanCondition -Condition ($sparkFilesystem.change.after.name -eq "spark") -Message "Spark filesystem is planned"
Assert-PlanCondition -Condition ($workspaceKeyVault.change.after.purge_protection_enabled -eq $false) -Message "Workspace Key Vault purge protection is disabled for the POC"
Assert-PlanCondition -Condition ($cmkKeyVault.change.after.purge_protection_enabled -eq $true) -Message "CMK Key Vault purge protection is enabled"
Assert-PlanCondition -Condition ($storage.change.after.shared_access_key_enabled -eq $false) -Message "Default Storage shared-key access is disabled"
Assert-PlanCondition -Condition ($sparkStorage.change.after.shared_access_key_enabled -eq $false) -Message "Spark ADLS shared-key access is disabled"
Assert-PlanCondition -Condition ($sparkStorage.change.after.is_hns_enabled -eq $true) -Message "Spark Storage has hierarchical namespace enabled"

if ($ExpectedNetworkProfile -eq "public") {
    Assert-PlanCondition -Condition ($workspace.change.after.body.properties.publicNetworkAccess -eq "Enabled") -Message "Workspace public access is enabled"
    Assert-PlanCondition -Condition ($workspace.change.after.body.properties.managedNetwork.isolationMode -eq "Disabled") -Message "AML managed-network isolation is disabled"
    Assert-PlanCondition -Condition ($linkedServicePolicy.change.after.input.public_network_access -eq "Enabled") -Message "Linked services use open public access"
    Assert-PlanCondition -Condition ($workspaceKeyVault.change.after.network_acls[0].default_action -eq "Allow") -Message "Workspace Key Vault allows public network access"
    Assert-PlanCondition -Condition ($cmkKeyVault.change.after.network_acls[0].default_action -eq "Allow") -Message "CMK Key Vault allows public network access"
    Assert-PlanCondition -Condition ($storage.change.after.network_rules[0].default_action -eq "Allow") -Message "Default Storage allows public network access"
    Assert-PlanCondition -Condition ($acr.change.after.network_rule_set[0].default_action -eq "Allow") -Message "ACR allows public network access"
    Assert-PlanCondition -Condition (@($sparkStorage.change.after.network_rules).Count -eq 0) -Message "Spark ADLS uses Azure's implicit open firewall configuration"
}
else {
    Assert-PlanCondition -Condition ($workspace.change.after.body.properties.publicNetworkAccess -eq "Disabled") -Message "Managed workspace creation starts with public access disabled"
    Assert-PlanCondition -Condition ($workspace.change.after.body.properties.managedNetwork.isolationMode -eq "AllowOnlyApprovedOutbound") -Message "AML managed network uses AllowOnlyApprovedOutbound"
    Assert-PlanCondition -Condition ($linkedServicePolicy.change.after.input.public_network_access -eq "EnabledForSelectedIPs") -Message "Linked services use selected-IP public access"
}

$computeResources = @(
    $resources | Where-Object {
        $_.address -like "module.workspace.azapi_resource.compute_*"
    }
)
if ($ExpectedCreateCompute) {
    Assert-PlanCondition -Condition ($computeResources.Count -eq 2) -Message "Exactly one cluster and one compute instance are planned"
    $cluster = Get-PlannedResource -Resources $resources -Address "module.workspace.azapi_resource.compute_cluster_uami[0]"
    $instance = Get-PlannedResource -Resources $resources -Address "module.workspace.azapi_resource.compute_instance_uami[0]"
    Assert-PlanCondition -Condition ($cluster.change.after.name -eq "aml-cluster-$ExpectedPurpose-$ExpectedLocationCode$ExpectedSuffix") -Message "Expected compute cluster name is planned"
    Assert-PlanCondition -Condition ($instance.change.after.name -eq $expectedComputeInstance) -Message "Expected compute instance name is planned"
    Assert-PlanCondition -Condition ($instance.change.after.name.Length -le 24) -Message "Compute instance name satisfies the Azure ML 24-character limit"
    Assert-PlanCondition -Condition ($cluster.change.after.body.properties.properties.enableNodePublicIp -eq ($ExpectedNetworkProfile -eq "public")) -Message "Cluster node public-IP setting matches the network profile"
    Assert-PlanCondition -Condition ($cluster.change.after.body.properties.properties.remoteLoginPortPublicAccess -eq "Disabled") -Message "Cluster remote login is disabled"
    Assert-PlanCondition -Condition ($cluster.change.after.body.properties.properties.scaleSettings.minNodeCount -eq 0) -Message "Cluster scales down to zero"
    Assert-PlanCondition -Condition ($instance.change.after.body.properties.properties.enableNodePublicIp -eq ($ExpectedNetworkProfile -eq "public")) -Message "Compute-instance public-IP setting matches the network profile"
    Assert-PlanCondition -Condition ($instance.change.after.body.properties.properties.sshSettings.sshPublicAccess -eq "Disabled") -Message "Compute-instance SSH public access is disabled"
}
else {
    Assert-PlanCondition -Condition ($computeResources.Count -eq 0) -Message "Compute creation is deferred"
}

$expectedNames = @{
    "azurerm_user_assigned_identity.compute_cluster"                            = "$ExpectedPurpose-mi-compute"
    "azurerm_user_assigned_identity.compute_instance"                           = "$ExpectedPurpose-mi-compute-instance"
    "azurerm_user_assigned_identity.online_endpoint"                            = "$ExpectedPurpose-mi-online-endpoint"
    "module.workspace.azurerm_user_assigned_identity.workspace_identity"         = "$ExpectedPurpose-mi-workspace"
}
foreach ($entry in $expectedNames.GetEnumerator()) {
    $resource = Get-PlannedResource -Resources $resources -Address $entry.Key
    Assert-PlanCondition -Condition ($resource.change.after.name -eq $entry.Value) -Message "Expected resource name is planned: $($entry.Value)"
}

$sparkStorageRole = Get-PlannedResource -Resources $resources -Address "module.workspace.azurerm_role_assignment.workspace_storage_contributor_for_spark"
Assert-PlanCondition -Condition ($sparkStorageRole.change.after.role_definition_name -eq "Contributor") -Message "Workspace UAMI receives Storage Contributor for Spark"

$taggedAddresses = @(
    "azurerm_resource_group.workspace",
    "azurerm_log_analytics_workspace.workspace",
    "azurerm_storage_account.spark_data_lake",
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
    $resource = Get-PlannedResource -Resources $resources -Address $address
    $tags = if ($null -ne $resource.change.after.tags) {
        $resource.change.after.tags
    }
    else {
        $resource.change.after.body.tags
    }
    Assert-PlanCondition -Condition ($tags.SecurityControl -eq "Ignore") -Message "SecurityControl=Ignore is planned on $address"
}

Write-Host "All Azure ML workspace Terraform plan invariants passed." -ForegroundColor Green
