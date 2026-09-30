[CmdletBinding()]
param(
    [Parameter()]
    [string]$TerraformDirectory = (Split-Path -Parent $PSScriptRoot),

    [Parameter()]
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path,

    [Parameter()]
    [switch]$SkipSmoke,

    [Parameter()]
    [switch]$SkipPipeline
)

$ErrorActionPreference = "Stop"

function Assert-DeploymentCondition {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "Deployment validation failed: $Message"
    }

    Write-Host "PASS: $Message" -ForegroundColor Green
}

function Invoke-AzJson {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $json = & az @Arguments --output json --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Arguments -join ' ')"
    }

    return $json | ConvertFrom-Json -Depth 100
}

function ConvertTo-ComparableIpRule {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    if ($Value.EndsWith("/32", [System.StringComparison]::Ordinal)) {
        return $Value.Substring(0, $Value.Length - 3)
    }

    return $Value
}

function Wait-ForJobTerminalState {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$ResourceGroup,

        [Parameter(Mandatory)]
        [string]$Workspace,

        [Parameter(Mandatory)]
        [string]$Subscription
    )

    $failureStates = @("Canceled", "CancelRequested", "Failed", "NotResponding")
    for ($attempt = 1; $attempt -le 240; $attempt++) {
        $status = & az ml job show `
            --name $Name `
            --resource-group $ResourceGroup `
            --workspace-name $Workspace `
            --subscription $Subscription `
            --query status `
            --output tsv `
            --only-show-errors
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to read Azure ML job state for $Name."
        }

        Write-Host "Job $Name status: $status"
        if ($status -eq "Completed") {
            return $status
        }
        if ($status -in $failureStates) {
            throw "Azure ML job $Name ended with status $status."
        }

        Start-Sleep -Seconds 30
    }

    throw "Azure ML job $Name did not reach a terminal state within two hours."
}

function Wait-ForComputeState {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string[]]$AcceptedStates,

        [Parameter(Mandatory)]
        [string]$ResourceGroup,

        [Parameter(Mandatory)]
        [string]$Workspace,

        [Parameter(Mandatory)]
        [string]$Subscription
    )

    for ($attempt = 1; $attempt -le 60; $attempt++) {
        $state = & az ml compute show `
            --name $Name `
            --resource-group $ResourceGroup `
            --workspace-name $Workspace `
            --subscription $Subscription `
            --query state `
            --output tsv `
            --only-show-errors

        if ($LASTEXITCODE -ne 0) {
            throw "Unable to read compute state for $Name."
        }

        if ($state -in $AcceptedStates) {
            return $state
        }

        Start-Sleep -Seconds 15
    }

    throw "Compute $Name did not reach one of these states: $($AcceptedStates -join ', ')."
}

$resolvedTerraformDirectory = (Resolve-Path -LiteralPath $TerraformDirectory).Path
$resolvedRepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

$outputJson = & terraform "-chdir=$resolvedTerraformDirectory" output -json
if ($LASTEXITCODE -ne 0) {
    throw "terraform output failed with exit code $LASTEXITCODE."
}
$outputs = $outputJson | ConvertFrom-Json -Depth 100

$expectedSubscription = "5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25"
$expectedResourceGroup = "rg-aml-ws-spark-cc-03"
$expectedWorkspace = "mlwsparkcc03"
$expectedCluster = "aml-cluster-spark-cc03"
$expectedInstance = "aml-instance-spark-cc03"

$subscriptionId = $outputs.subscription_id.value
$resourceGroup = $outputs.resource_group_name.value
$workspaceName = $outputs.workspace_name.value
$workspaceId = $outputs.workspace_id.value
$clusterName = $outputs.compute_cluster.value.name
$instanceName = $outputs.compute_instance.value.name
$expectedCidrs = @($outputs.network_policy.value.allowed_public_ip_cidrs)
$expectedServiceIpRules = @(
    $expectedCidrs | ForEach-Object {
        ConvertTo-ComparableIpRule -Value $_
    }
)

Assert-DeploymentCondition -Condition ($subscriptionId -eq $expectedSubscription) -Message "Deployment uses the confirmed subscription"
Assert-DeploymentCondition -Condition ($resourceGroup -eq $expectedResourceGroup) -Message "Deployment uses the expected resource group"
Assert-DeploymentCondition -Condition ($workspaceName -eq $expectedWorkspace) -Message "Deployment uses the expected workspace"
Assert-DeploymentCondition -Condition ($clusterName -eq $expectedCluster) -Message "Deployment uses the expected compute cluster"
Assert-DeploymentCondition -Condition ($instanceName -eq $expectedInstance) -Message "Deployment uses the expected compute instance"
Assert-DeploymentCondition -Condition ($outputs.linked_resources.value.storage_account_name -eq "stsparkcc03") -Message "Deployment uses the expected Storage account"
Assert-DeploymentCondition -Condition ($outputs.linked_resources.value.key_vault_name -eq "kvsparkcc03") -Message "Deployment uses the expected workspace Key Vault"
Assert-DeploymentCondition -Condition ($outputs.linked_resources.value.container_registry_name -eq "acrsparkcc03") -Message "Deployment uses the expected ACR"
Assert-DeploymentCondition -Condition ($outputs.linked_resources.value.log_analytics_workspace -eq "log-aml-spark-cc03") -Message "Deployment uses the expected Log Analytics workspace"
Assert-DeploymentCondition -Condition ((Split-Path -Leaf $outputs.workspace_identity.value.resource_id) -eq "spark-mi-workspace") -Message "Deployment uses the expected workspace UAMI"
Assert-DeploymentCondition -Condition ((Split-Path -Leaf $outputs.compute_cluster.value.identity_resource_id) -eq "spark-mi-compute") -Message "Deployment uses the expected cluster UAMI"
Assert-DeploymentCondition -Condition ((Split-Path -Leaf $outputs.compute_instance.value.identity_resource_id) -eq "spark-mi-compute-instance") -Message "Deployment uses the expected compute-instance UAMI"
Assert-DeploymentCondition -Condition ((Split-Path -Leaf $outputs.online_endpoint_identity.value.resource_id) -eq "spark-mi-online-endpoint") -Message "Deployment uses the expected endpoint UAMI"
Assert-DeploymentCondition -Condition ((Split-Path -Leaf $outputs.cmk.value.key_vault_id) -eq "kvcmksparkcc03") -Message "Deployment uses the expected CMK Key Vault"

& az account set --subscription $subscriptionId
if ($LASTEXITCODE -ne 0) {
    throw "Unable to select Azure subscription $subscriptionId."
}

try {
$workspace = Invoke-AzJson -Arguments @("rest", "--method", "get", "--uri", "${workspaceId}?api-version=2025-06-01")
Assert-DeploymentCondition -Condition ($workspace.identity.type -like "*UserAssigned*") -Message "Workspace uses a user-assigned managed identity"
Assert-DeploymentCondition -Condition ($workspace.properties.encryption.status -eq "Enabled") -Message "Workspace CMK encryption is enabled"
Assert-DeploymentCondition -Condition ($workspace.properties.publicNetworkAccess -eq "Enabled") -Message "Workspace selected-IP public access is enabled"
Assert-DeploymentCondition -Condition ($workspace.properties.networkAcls.defaultAction -eq "Deny") -Message "Workspace network ACL denies by default"
Assert-DeploymentCondition -Condition ($workspace.properties.managedNetwork.isolationMode -eq "AllowOnlyApprovedOutbound") -Message "Workspace managed network uses AllowOnlyApprovedOutbound"
Assert-DeploymentCondition -Condition ($workspace.properties.managedNetwork.status.status -eq "Active") -Message "Workspace managed network is active"
Assert-DeploymentCondition -Condition ($workspace.properties.managedNetwork.status.sparkReady -eq $true) -Message "Workspace managed network is ready for serverless Spark"
Assert-DeploymentCondition -Condition ($workspace.tags.SecurityControl -eq "Ignore") -Message "Workspace has SecurityControl=Ignore"

$actualWorkspaceCidrs = @($workspace.properties.networkAcls.ipRules | ForEach-Object { $_.value })
foreach ($cidr in $expectedCidrs) {
    Assert-DeploymentCondition -Condition ($cidr -in $actualWorkspaceCidrs) -Message "Workspace allows CIDR $cidr"
}

$storageId = $outputs.linked_resources.value.storage_account_id
$keyVaultId = $outputs.linked_resources.value.key_vault_id
$acrId = $outputs.linked_resources.value.container_registry_id
$cmkVaultId = $outputs.cmk.value.key_vault_id

$managedOutboundRules = Invoke-AzJson -Arguments @(
    "ml", "workspace", "outbound-rule", "list",
    "--subscription", $subscriptionId,
    "--resource-group", $resourceGroup,
    "--workspace-name", $workspaceName
)
$blobRules = @(
    $managedOutboundRules | Where-Object {
        $_.type -eq "PrivateEndpoint" -and
        $_.destination.service_resource_id -eq $storageId -and
        $_.destination.subresource_target -eq "blob"
    }
)
Assert-DeploymentCondition -Condition ($blobRules.Count -eq 1) -Message "Exactly one managed-network Blob rule targets workspace Storage"
Assert-DeploymentCondition -Condition ($blobRules[0].name -eq "SparkStorageBlob") -Message "The documented CLI-created Blob rule is present"
Assert-DeploymentCondition -Condition ($blobRules[0].destination.spark_enabled -eq $true) -Message "The CLI-created Blob rule is Spark-enabled"
Assert-DeploymentCondition -Condition ($blobRules[0].status -eq "Active") -Message "The Spark-enabled Blob rule is active"

$storage = Invoke-AzJson -Arguments @("rest", "--method", "get", "--uri", "${storageId}?api-version=2023-05-01")
$keyVault = Invoke-AzJson -Arguments @("rest", "--method", "get", "--uri", "${keyVaultId}?api-version=2023-07-01")
$acr = Invoke-AzJson -Arguments @("rest", "--method", "get", "--uri", "${acrId}?api-version=2023-07-01")
$cmkVault = Invoke-AzJson -Arguments @("rest", "--method", "get", "--uri", "${cmkVaultId}?api-version=2023-07-01")

Assert-DeploymentCondition -Condition ($storage.properties.publicNetworkAccess -eq "Enabled") -Message "Default storage selected-IP public access is enabled"
Assert-DeploymentCondition -Condition ($storage.properties.networkAcls.defaultAction -eq "Deny") -Message "Default storage firewall denies by default"
Assert-DeploymentCondition -Condition ($storage.properties.allowSharedKeyAccess -eq $false) -Message "Default storage shared-key access is disabled"
Assert-DeploymentCondition -Condition ($keyVault.properties.publicNetworkAccess -eq "Enabled") -Message "Workspace Key Vault selected-IP public access is enabled"
Assert-DeploymentCondition -Condition ($keyVault.properties.networkAcls.defaultAction -eq "Deny") -Message "Workspace Key Vault firewall denies by default"
Assert-DeploymentCondition -Condition (
    $null -eq $keyVault.properties.enablePurgeProtection -or
    $keyVault.properties.enablePurgeProtection -eq $false
) -Message "Workspace Key Vault purge protection is disabled for the demo"
Assert-DeploymentCondition -Condition ($cmkVault.properties.publicNetworkAccess -eq "Enabled") -Message "CMK Key Vault selected-IP public access is enabled"
Assert-DeploymentCondition -Condition ($cmkVault.properties.networkAcls.defaultAction -eq "Deny") -Message "CMK Key Vault firewall denies by default"
Assert-DeploymentCondition -Condition ($cmkVault.properties.enablePurgeProtection -eq $true) -Message "CMK Key Vault purge protection is enabled as required by Azure CMK services"
Assert-DeploymentCondition -Condition ($acr.properties.publicNetworkAccess -eq "Enabled") -Message "ACR public access is enabled only through firewall rules"
Assert-DeploymentCondition -Condition ($acr.properties.networkRuleSet.defaultAction -eq "Deny") -Message "ACR firewall denies by default"
Assert-DeploymentCondition -Condition ($storage.tags.SecurityControl -eq "Ignore") -Message "Storage has SecurityControl=Ignore"
Assert-DeploymentCondition -Condition ($keyVault.tags.SecurityControl -eq "Ignore") -Message "Workspace Key Vault has SecurityControl=Ignore"
Assert-DeploymentCondition -Condition ($cmkVault.tags.SecurityControl -eq "Ignore") -Message "CMK Key Vault has SecurityControl=Ignore"
Assert-DeploymentCondition -Condition ($acr.tags.SecurityControl -eq "Ignore") -Message "ACR has SecurityControl=Ignore"

$workspaceStorageRoles = Invoke-AzJson -Arguments @(
    "role", "assignment", "list",
    "--subscription", $subscriptionId,
    "--assignee-object-id", $outputs.workspace_identity.value.principal_id,
    "--scope", $storageId,
    "--include-inherited"
)
$workspaceStorageRoleNames = @($workspaceStorageRoles | ForEach-Object { $_.roleDefinitionName })
Assert-DeploymentCondition -Condition ("Contributor" -in $workspaceStorageRoleNames) -Message "Workspace UAMI has Storage Contributor for Spark"
Assert-DeploymentCondition -Condition ("Storage Blob Data Contributor" -in $workspaceStorageRoleNames) -Message "Workspace UAMI has Storage Blob Data Contributor"

$resourceCidrs = @{
    "Default storage" = @(
        $storage.properties.networkAcls.ipRules |
            ForEach-Object { ConvertTo-ComparableIpRule -Value $_.value }
    )
    "Workspace Key Vault" = @(
        $keyVault.properties.networkAcls.ipRules |
            ForEach-Object { ConvertTo-ComparableIpRule -Value $_.value }
    )
    "CMK Key Vault" = @(
        $cmkVault.properties.networkAcls.ipRules |
            ForEach-Object { ConvertTo-ComparableIpRule -Value $_.value }
    )
    "ACR" = @(
        $acr.properties.networkRuleSet.ipRules |
            ForEach-Object { ConvertTo-ComparableIpRule -Value $_.value }
    )
}
foreach ($resourceName in $resourceCidrs.Keys) {
    foreach ($ipRule in $expectedServiceIpRules) {
        Assert-DeploymentCondition -Condition ($ipRule -in $resourceCidrs[$resourceName]) -Message "$resourceName allows IP rule $ipRule"
    }
}

$clusterId = $outputs.compute_cluster.value.resource_id
$instanceId = $outputs.compute_instance.value.resource_id
$cluster = Invoke-AzJson -Arguments @("rest", "--method", "get", "--uri", "${clusterId}?api-version=2025-06-01")
$instance = Invoke-AzJson -Arguments @("rest", "--method", "get", "--uri", "${instanceId}?api-version=2025-06-01")

Assert-DeploymentCondition -Condition ($cluster.properties.provisioningState -eq "Succeeded") -Message "Compute cluster provisioning succeeded"
Assert-DeploymentCondition -Condition ($cluster.identity.type -like "*UserAssigned*") -Message "Compute cluster uses a UAMI"
Assert-DeploymentCondition -Condition ($cluster.properties.properties.enableNodePublicIp -eq $false) -Message "Compute cluster node public IPs are disabled"
Assert-DeploymentCondition -Condition ($cluster.properties.properties.scaleSettings.minNodeCount -eq 0) -Message "Compute cluster minimum node count is zero"
Assert-DeploymentCondition -Condition ($cluster.tags.SecurityControl -eq "Ignore") -Message "Compute cluster has SecurityControl=Ignore"
Assert-DeploymentCondition -Condition ($instance.properties.provisioningState -eq "Succeeded") -Message "Compute instance provisioning succeeded"
Assert-DeploymentCondition -Condition ($instance.identity.type -like "*UserAssigned*") -Message "Compute instance uses a UAMI"
Assert-DeploymentCondition -Condition ($instance.properties.properties.enableNodePublicIp -eq $false) -Message "Compute instance public IP is disabled"
Assert-DeploymentCondition -Condition ($instance.properties.properties.sshSettings.sshPublicAccess -eq "Disabled") -Message "Compute instance public SSH is disabled"
Assert-DeploymentCondition -Condition ($instance.tags.SecurityControl -eq "Ignore") -Message "Compute instance has SecurityControl=Ignore"

$resourceGroupDetails = Invoke-AzJson -Arguments @(
    "group", "show",
    "--subscription", $subscriptionId,
    "--name", $resourceGroup
)
Assert-DeploymentCondition -Condition ($resourceGroupDetails.location -eq "canadacentral") -Message "Resource group is in Canada Central"
Assert-DeploymentCondition -Condition ($resourceGroupDetails.tags.SecurityControl -eq "Ignore") -Message "Resource group has SecurityControl=Ignore"

$groupResources = Invoke-AzJson -Arguments @(
    "resource", "list",
    "--subscription", $subscriptionId,
    "--resource-group", $resourceGroup
)
$expectedTaggedTopLevelNames = @(
    "log-aml-spark-cc03",
    "spark-mi-compute",
    "spark-mi-compute-instance",
    "spark-mi-online-endpoint",
    "spark-mi-workspace",
    "mlwinsparkcc03",
    "stsparkcc03",
    "kvsparkcc03",
    "kvcmksparkcc03",
    "acrsparkcc03",
    "mlwsparkcc03"
)
foreach ($expectedName in $expectedTaggedTopLevelNames) {
    $matchingResources = @($groupResources | Where-Object { $_.name -eq $expectedName })
    Assert-DeploymentCondition -Condition ($matchingResources.Count -eq 1) -Message "Expected top-level resource exists: $expectedName"
    Assert-DeploymentCondition -Condition ($matchingResources[0].tags.SecurityControl -eq "Ignore") -Message "$expectedName has SecurityControl=Ignore"
}

if (-not $SkipSmoke) {
    $simpleJobPath = Join-Path $resolvedRepositoryRoot "pipelines\single-workspace-smoke-job.yaml"
    $simpleJobName = & az ml job create `
        --file $simpleJobPath `
        --resource-group $resourceGroup `
        --workspace-name $workspaceName `
        --subscription $subscriptionId `
        --set "compute=azureml:$clusterName" `
        --query name `
        --output tsv `
        --only-show-errors
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($simpleJobName)) {
        throw "Simple command job submission failed."
    }

    $simpleJobStatus = Wait-ForJobTerminalState `
        -Name $simpleJobName `
        -ResourceGroup $resourceGroup `
        -Workspace $workspaceName `
        -Subscription $subscriptionId
    Assert-DeploymentCondition -Condition ($simpleJobStatus -eq "Completed") -Message "Simple command job completed"
}
else {
    Write-Host "SKIP: Simple command job already completed in this validation cycle." -ForegroundColor Yellow
}

if (-not $SkipPipeline) {
    $pipelinePath = Join-Path $resolvedRepositoryRoot "pipelines\single-workspace-integration-pipeline.yaml"
    $pipelineJobName = & az ml job create `
        --file $pipelinePath `
        --resource-group $resourceGroup `
        --workspace-name $workspaceName `
        --subscription $subscriptionId `
        --set "settings.default_compute=azureml:$clusterName" "settings.force_rerun=true" `
        --query name `
        --output tsv `
        --only-show-errors
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($pipelineJobName)) {
        throw "Integration pipeline submission failed."
    }

    $pipelineStatus = Wait-ForJobTerminalState `
        -Name $pipelineJobName `
        -ResourceGroup $resourceGroup `
        -Workspace $workspaceName `
        -Subscription $subscriptionId
    Assert-DeploymentCondition -Condition ($pipelineStatus -eq "Completed") -Message "Registry-free integration pipeline completed"

    $pipelineOutputs = Invoke-AzJson -Arguments @(
        "ml", "job", "show",
        "--name", $pipelineJobName,
        "--resource-group", $resourceGroup,
        "--workspace-name", $workspaceName,
        "--subscription", $subscriptionId,
        "--query", "outputs"
    )
    Assert-DeploymentCondition -Condition (@($pipelineOutputs.PSObject.Properties).Count -gt 0) -Message "Integration pipeline exposes output artifacts"
}
else {
    Write-Host "SKIP: Integration pipeline already completed in this validation cycle." -ForegroundColor Yellow
}

}
finally {
    $instanceState = & az ml compute show `
        --name $instanceName `
        --resource-group $resourceGroup `
        --workspace-name $workspaceName `
        --subscription $subscriptionId `
        --query state `
        --output tsv `
        --only-show-errors
    if ($LASTEXITCODE -eq 0 -and $instanceState -notin @("Stopped", "Deallocated")) {
        & az ml compute stop `
            --name $instanceName `
            --resource-group $resourceGroup `
            --workspace-name $workspaceName `
            --subscription $subscriptionId `
            --only-show-errors
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Unable to stop compute instance $instanceName automatically."
        }
    }
}

$finalInstanceState = Wait-ForComputeState `
    -Name $instanceName `
    -AcceptedStates @("Stopped", "Deallocated") `
    -ResourceGroup $resourceGroup `
    -Workspace $workspaceName `
    -Subscription $subscriptionId
Assert-DeploymentCondition -Condition ($finalInstanceState -in @("Stopped", "Deallocated")) -Message "Compute instance is stopped"

for ($attempt = 1; $attempt -le 40; $attempt++) {
    $nodesJson = & az ml compute list-nodes `
        --name $clusterName `
        --resource-group $resourceGroup `
        --workspace-name $workspaceName `
        --subscription $subscriptionId `
        --output json `
        --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to list nodes for compute cluster $clusterName."
    }
    $nodes = $nodesJson | ConvertFrom-Json -Depth 20
    $nodeCount = @($nodes).Count

    if ($nodeCount -eq 0) {
        break
    }

    Start-Sleep -Seconds 15
}
Assert-DeploymentCondition -Condition ($nodeCount -eq 0) -Message "Compute cluster has scaled down to zero allocated nodes"

Write-Host "Azure deployment validation completed successfully." -ForegroundColor Green
