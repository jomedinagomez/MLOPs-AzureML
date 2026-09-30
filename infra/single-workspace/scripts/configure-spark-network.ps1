[CmdletBinding()]
param(
    [string]$TerraformDirectory = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

function Invoke-AzCli {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Arguments -join ' ')"
    }
}

function Get-TerraformOutput {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $value = & terraform "-chdir=$TerraformDirectory" output -json $Name
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read Terraform output '$Name'."
    }

    return $value | ConvertFrom-Json
}

$subscriptionId = Get-TerraformOutput -Name "subscription_id"
$resourceGroup = Get-TerraformOutput -Name "resource_group_name"
$workspaceName = Get-TerraformOutput -Name "workspace_name"
$workspaceId = Get-TerraformOutput -Name "workspace_id"
$linkedResources = Get-TerraformOutput -Name "linked_resources"
$networkPolicy = Get-TerraformOutput -Name "network_policy"

$allowedCidrs = @($networkPolicy.allowed_public_ip_cidrs)
if ($allowedCidrs.Count -eq 0) {
    throw "At least one selected-IP CIDR is required before public access can be restored."
}

$networkAcls = $allowedCidrs -join ","

Write-Host "[$(Get-Date -Format T)] Selecting subscription $subscriptionId"
Invoke-AzCli -Arguments @("account", "set", "--subscription", $subscriptionId)

Write-Host "[$(Get-Date -Format T)] Keeping workspace public access disabled during managed-network provisioning"
Invoke-AzCli -Arguments @(
    "ml", "workspace", "update",
    "--subscription", $subscriptionId,
    "--resource-group", $resourceGroup,
    "--name", $workspaceName,
    "--public-network-access", "disabled",
    "--output", "none",
    "--only-show-errors"
)

$workspace = & az rest `
    --method get `
    --uri "${workspaceId}?api-version=2025-06-01" `
    --output json `
    --only-show-errors | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw "Unable to verify workspace public access."
}
if ($workspace.properties.publicNetworkAccess -ne "Disabled") {
    throw "Workspace public access must be Disabled before managed-network provisioning."
}

$outboundRulesJson = & az ml workspace outbound-rule list `
    --subscription $subscriptionId `
    --resource-group $resourceGroup `
    --workspace-name $workspaceName `
    --output json `
    --only-show-errors
if ($LASTEXITCODE -ne 0) {
    throw "Unable to list managed-network outbound rules."
}
$outboundRules = @($outboundRulesJson | ConvertFrom-Json)

$blobRules = @(
    $outboundRules | Where-Object {
        $_.type -ieq "PrivateEndpoint" -and
        $_.destination.subresource_target -ieq "blob" -and
        $_.destination.service_resource_id -ieq $linkedResources.storage_account_id
    }
)
if ($blobRules.Count -gt 1) {
    throw "Multiple Blob outbound rules target the default Storage account."
}
$blobRuleName = if ($blobRules.Count -eq 1) { $blobRules[0].name } else { "SparkStorageBlob" }
if ($blobRules.Count -eq 0 -or -not $blobRules[0].destination.spark_enabled) {
    Write-Host "[$(Get-Date -Format T)] Setting Spark-enabled Blob rule $blobRuleName"
    Invoke-AzCli -Arguments @(
        "ml", "workspace", "outbound-rule", "set",
        "--subscription", $subscriptionId,
        "--resource-group", $resourceGroup,
        "--workspace-name", $workspaceName,
        "--rule", $blobRuleName,
        "--type", "private_endpoint",
        "--service-resource-id", $linkedResources.storage_account_id,
        "--subresource-target", "blob",
        "--spark-enabled", "true",
        "--output", "none",
        "--only-show-errors"
    )
}
else {
    Write-Host "[$(Get-Date -Format T)] Reusing Spark-enabled Blob rule $blobRuleName"
}

$workspaceRules = @(
    $outboundRules | Where-Object {
        $_.type -ieq "PrivateEndpoint" -and
        $_.destination.subresource_target -ieq "amlworkspace" -and
        $_.destination.service_resource_id -ieq $workspaceId
    }
)
if ($workspaceRules.Count -gt 1) {
    throw "Multiple workspace-self outbound rules target the AML workspace."
}
$workspaceRuleName = if ($workspaceRules.Count -eq 1) { $workspaceRules[0].name } else { "WorkspaceSelf" }
if ($workspaceRules.Count -eq 0) {
    Write-Host "[$(Get-Date -Format T)] Adding workspace-self private-endpoint rule $workspaceRuleName"
    Invoke-AzCli -Arguments @(
        "ml", "workspace", "outbound-rule", "set",
        "--subscription", $subscriptionId,
        "--resource-group", $resourceGroup,
        "--workspace-name", $workspaceName,
        "--rule", $workspaceRuleName,
        "--type", "private_endpoint",
        "--service-resource-id", $workspaceId,
        "--subresource-target", "amlworkspace",
        "--spark-enabled", "false",
        "--output", "none",
        "--only-show-errors"
    )
}
else {
    Write-Host "[$(Get-Date -Format T)] Reusing workspace-self rule $workspaceRuleName"
}

Write-Host "[$(Get-Date -Format T)] Current managed-network outbound rules"
Invoke-AzCli -Arguments @(
    "ml", "workspace", "outbound-rule", "list",
    "--subscription", $subscriptionId,
    "--resource-group", $resourceGroup,
    "--workspace-name", $workspaceName,
    "--output", "table"
)

Write-Host "[$(Get-Date -Format T)] Provisioning the managed network with serverless Spark support"
Write-Host "This is a long-running Azure operation. Keep this terminal open."
Invoke-AzCli -Arguments @(
    "ml", "workspace", "provision-network",
    "--subscription", $subscriptionId,
    "--resource-group", $resourceGroup,
    "--name", $workspaceName,
    "--include-spark",
    "--verbose"
)

$workspace = & az ml workspace show `
    --subscription $subscriptionId `
    --resource-group $resourceGroup `
    --name $workspaceName `
    --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw "Unable to verify the provisioned workspace."
}

if ($workspace.managed_network.status.status -ne "Active" -or -not $workspace.managed_network.status.spark_ready) {
    throw "Managed network provisioning returned without Active/sparkReady=true."
}

Write-Host "[$(Get-Date -Format T)] Managed network is Active and Spark-ready"
Write-Host "[$(Get-Date -Format T)] Restoring selected-IP public access for local job submission"
Invoke-AzCli -Arguments @(
    "ml", "workspace", "update",
    "--subscription", $subscriptionId,
    "--resource-group", $resourceGroup,
    "--name", $workspaceName,
    "--public-network-access", "Enabled",
    "--network-acls", $networkAcls,
    "--output", "none",
    "--only-show-errors"
)

Write-Host "[$(Get-Date -Format T)] Spark network configuration completed successfully"
