[CmdletBinding()]
param(
    [Parameter()]
    [string]$TerraformDirectory = (Split-Path -Parent $PSScriptRoot),

    [Parameter()]
    [string]$StatePath = "terraform.tfstate.d\public-ncus\terraform.tfstate",

    [Parameter()]
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path,

    [Parameter()]
    [string]$ExpectedSubscription = "5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25",

    [Parameter()]
    [string]$ExpectedLocation = "northcentralus",

    [Parameter()]
    [string]$ExpectedLocationCode = "ncus",

    [Parameter()]
    [ValidatePattern("^[0-9]{2}$")]
    [string]$ExpectedSuffix = "04",

    [Parameter()]
    [string]$ExpectedInstanceName = "ci-public-ncus04",

    [Parameter()]
    [switch]$SkipSmoke
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
    for ($attempt = 1; $attempt -le 120; $attempt++) {
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

    throw "Azure ML job $Name did not reach a terminal state within one hour."
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
$resolvedStatePath = if ([System.IO.Path]::IsPathRooted($StatePath)) {
    $StatePath
}
else {
    Join-Path $resolvedTerraformDirectory $StatePath
}

$outputJson = & terraform "-chdir=$resolvedTerraformDirectory" output "-state=$resolvedStatePath" -json
if ($LASTEXITCODE -ne 0) {
    throw "terraform output failed with exit code $LASTEXITCODE."
}
$outputs = $outputJson | ConvertFrom-Json -Depth 100

$expectedPurpose = "public"
$expectedResourceGroup = "rg-aml-ws-$expectedPurpose-$ExpectedLocationCode-$ExpectedSuffix"
$expectedWorkspace = "mlw$expectedPurpose$ExpectedLocationCode$ExpectedSuffix"
$expectedCluster = "aml-cluster-$expectedPurpose-$ExpectedLocationCode$ExpectedSuffix"
$expectedInstance = $ExpectedInstanceName
$expectedStorage = "st$expectedPurpose$ExpectedLocationCode$ExpectedSuffix"
$expectedSparkStorage = "st${expectedPurpose}dl${ExpectedLocationCode}04"
$expectedAcr = "acr$expectedPurpose$ExpectedLocationCode$ExpectedSuffix"
$expectedWorkspaceVault = "kv$expectedPurpose$ExpectedLocationCode$ExpectedSuffix"
$expectedCmkVault = "kvcmk$expectedPurpose$ExpectedLocationCode$ExpectedSuffix"
$expectedLogAnalytics = "log-aml-$expectedPurpose-$ExpectedLocationCode$ExpectedSuffix"

$subscriptionId = $outputs.subscription_id.value
$resourceGroup = $outputs.resource_group_name.value
$workspaceName = $outputs.workspace_name.value
$workspaceId = $outputs.workspace_id.value
$clusterName = $outputs.compute_cluster.value.name
$instanceName = $outputs.compute_instance.value.name

Assert-DeploymentCondition -Condition ($subscriptionId -eq $ExpectedSubscription) -Message "Deployment uses the confirmed subscription"
Assert-DeploymentCondition -Condition ($resourceGroup -eq $expectedResourceGroup) -Message "Deployment uses the expected resource group"
Assert-DeploymentCondition -Condition ($workspaceName -eq $expectedWorkspace) -Message "Deployment uses the expected workspace"
Assert-DeploymentCondition -Condition ($clusterName -eq $expectedCluster) -Message "Deployment uses the expected compute cluster"
Assert-DeploymentCondition -Condition ($instanceName -eq $expectedInstance) -Message "Deployment uses the expected compute instance"
Assert-DeploymentCondition -Condition ($outputs.linked_resources.value.storage_account_name -eq $expectedStorage) -Message "Deployment uses the expected default Storage"
Assert-DeploymentCondition -Condition ($outputs.spark_data_lake.value.account_name -eq $expectedSparkStorage) -Message "Deployment uses the expected Spark ADLS"
Assert-DeploymentCondition -Condition ($outputs.linked_resources.value.key_vault_name -eq $expectedWorkspaceVault) -Message "Deployment uses the expected workspace Key Vault"
Assert-DeploymentCondition -Condition ($outputs.linked_resources.value.container_registry_name -eq $expectedAcr) -Message "Deployment uses the expected ACR"
Assert-DeploymentCondition -Condition ($outputs.linked_resources.value.log_analytics_workspace -eq $expectedLogAnalytics) -Message "Deployment uses the expected Log Analytics workspace"
Assert-DeploymentCondition -Condition ((Split-Path -Leaf $outputs.cmk.value.key_vault_id) -eq $expectedCmkVault) -Message "Deployment uses the expected CMK Key Vault"
Assert-DeploymentCondition -Condition ($outputs.network_policy.value.managed_network_mode -eq "Disabled") -Message "Terraform output reports disabled managed-network isolation"

& az account set --subscription $subscriptionId
if ($LASTEXITCODE -ne 0) {
    throw "Unable to select Azure subscription $subscriptionId."
}

$workspace = Invoke-AzJson -Arguments @("rest", "--method", "get", "--uri", "${workspaceId}?api-version=2025-06-01")
Assert-DeploymentCondition -Condition ($workspace.location -eq $ExpectedLocation) -Message "Workspace is in North Central US"
Assert-DeploymentCondition -Condition ($workspace.identity.type -like "*UserAssigned*") -Message "Workspace uses a user-assigned managed identity"
Assert-DeploymentCondition -Condition ($workspace.properties.encryption.status -eq "Enabled") -Message "Workspace CMK encryption is enabled"
Assert-DeploymentCondition -Condition ($workspace.properties.publicNetworkAccess -eq "Enabled") -Message "Workspace public access is enabled"
Assert-DeploymentCondition -Condition ($workspace.properties.managedNetwork.isolationMode -eq "Disabled") -Message "Workspace managed-network isolation is disabled"
Assert-DeploymentCondition -Condition ($workspace.tags.SecurityControl -eq "Ignore") -Message "Workspace has SecurityControl=Ignore"

$storageId = $outputs.linked_resources.value.storage_account_id
$keyVaultId = $outputs.linked_resources.value.key_vault_id
$acrId = $outputs.linked_resources.value.container_registry_id
$cmkVaultId = $outputs.cmk.value.key_vault_id
$sparkStorageId = $outputs.spark_data_lake.value.account_id

$storage = Invoke-AzJson -Arguments @("rest", "--method", "get", "--uri", "${storageId}?api-version=2023-05-01")
$keyVault = Invoke-AzJson -Arguments @("rest", "--method", "get", "--uri", "${keyVaultId}?api-version=2023-07-01")
$acr = Invoke-AzJson -Arguments @("rest", "--method", "get", "--uri", "${acrId}?api-version=2023-07-01")
$cmkVault = Invoke-AzJson -Arguments @("rest", "--method", "get", "--uri", "${cmkVaultId}?api-version=2023-07-01")
$sparkStorage = Invoke-AzJson -Arguments @("rest", "--method", "get", "--uri", "${sparkStorageId}?api-version=2023-05-01")

foreach ($resource in @($storage, $keyVault, $acr, $cmkVault, $sparkStorage)) {
    Assert-DeploymentCondition -Condition ($resource.location -eq $ExpectedLocation) -Message "$($resource.name) is in North Central US"
    Assert-DeploymentCondition -Condition ($resource.tags.SecurityControl -eq "Ignore") -Message "$($resource.name) has SecurityControl=Ignore"
}

Assert-DeploymentCondition -Condition ($storage.properties.publicNetworkAccess -eq "Enabled") -Message "Default Storage public access is enabled"
Assert-DeploymentCondition -Condition ($storage.properties.networkAcls.defaultAction -eq "Allow") -Message "Default Storage firewall allows public access"
Assert-DeploymentCondition -Condition ($storage.properties.allowSharedKeyAccess -eq $false) -Message "Default Storage shared-key access is disabled"
Assert-DeploymentCondition -Condition ($sparkStorage.properties.publicNetworkAccess -eq "Enabled") -Message "Spark ADLS public access is enabled"
Assert-DeploymentCondition -Condition ($sparkStorage.properties.networkAcls.defaultAction -eq "Allow") -Message "Spark ADLS firewall allows public access"
Assert-DeploymentCondition -Condition ($sparkStorage.properties.allowSharedKeyAccess -eq $false) -Message "Spark ADLS shared-key access is disabled"
Assert-DeploymentCondition -Condition ($sparkStorage.properties.isHnsEnabled -eq $true) -Message "Spark Storage has hierarchical namespace enabled"
Assert-DeploymentCondition -Condition ($keyVault.properties.publicNetworkAccess -eq "Enabled") -Message "Workspace Key Vault public access is enabled"
Assert-DeploymentCondition -Condition (
    $null -eq $keyVault.properties.networkAcls -or
    $keyVault.properties.networkAcls.defaultAction -eq "Allow"
) -Message "Workspace Key Vault firewall allows public access"
Assert-DeploymentCondition -Condition ($cmkVault.properties.publicNetworkAccess -eq "Enabled") -Message "CMK Key Vault public access is enabled"
Assert-DeploymentCondition -Condition (
    $null -eq $cmkVault.properties.networkAcls -or
    $cmkVault.properties.networkAcls.defaultAction -eq "Allow"
) -Message "CMK Key Vault firewall allows public access"
Assert-DeploymentCondition -Condition ($cmkVault.properties.enablePurgeProtection -eq $true) -Message "CMK Key Vault purge protection is enabled"
Assert-DeploymentCondition -Condition ($acr.properties.publicNetworkAccess -eq "Enabled") -Message "ACR public access is enabled"
Assert-DeploymentCondition -Condition ($acr.properties.networkRuleSet.defaultAction -eq "Allow") -Message "ACR firewall allows public access"

$workspaceStorageRoles = Invoke-AzJson -Arguments @(
    "role", "assignment", "list",
    "--subscription", $subscriptionId,
    "--assignee-object-id", $outputs.workspace_identity.value.principal_id,
    "--scope", $storageId,
    "--include-inherited"
)
$workspaceStorageRoleNames = @($workspaceStorageRoles | ForEach-Object { $_.roleDefinitionName })
Assert-DeploymentCondition -Condition ("Contributor" -in $workspaceStorageRoleNames) -Message "Workspace UAMI has Storage Contributor"
Assert-DeploymentCondition -Condition ("Storage Blob Data Contributor" -in $workspaceStorageRoleNames) -Message "Workspace UAMI has Storage Blob Data Contributor"

$clusterId = $outputs.compute_cluster.value.resource_id
$instanceId = $outputs.compute_instance.value.resource_id
$cluster = Invoke-AzJson -Arguments @("rest", "--method", "get", "--uri", "${clusterId}?api-version=2025-06-01")
$instance = Invoke-AzJson -Arguments @("rest", "--method", "get", "--uri", "${instanceId}?api-version=2025-06-01")

Assert-DeploymentCondition -Condition ($cluster.properties.provisioningState -eq "Succeeded") -Message "Compute cluster provisioning succeeded"
Assert-DeploymentCondition -Condition ($cluster.identity.type -like "*UserAssigned*") -Message "Compute cluster uses a UAMI"
Assert-DeploymentCondition -Condition ($cluster.properties.properties.enableNodePublicIp -eq $true) -Message "Compute cluster node public IPs are enabled for the open profile"
Assert-DeploymentCondition -Condition ($cluster.properties.properties.remoteLoginPortPublicAccess -eq "Disabled") -Message "Compute cluster remote login is disabled"
Assert-DeploymentCondition -Condition ($cluster.properties.properties.scaleSettings.minNodeCount -eq 0) -Message "Compute cluster minimum node count is zero"
Assert-DeploymentCondition -Condition ($cluster.tags.SecurityControl -eq "Ignore") -Message "Compute cluster has SecurityControl=Ignore"
Assert-DeploymentCondition -Condition ($instance.properties.provisioningState -eq "Succeeded") -Message "Compute instance provisioning succeeded"
Assert-DeploymentCondition -Condition ($instance.identity.type -like "*UserAssigned*") -Message "Compute instance uses a UAMI"
Assert-DeploymentCondition -Condition ($instance.properties.properties.enableNodePublicIp -eq $true) -Message "Compute instance public IP is enabled for the open profile"
Assert-DeploymentCondition -Condition ($instance.properties.properties.sshSettings.sshPublicAccess -eq "Disabled") -Message "Compute instance public SSH is disabled"
Assert-DeploymentCondition -Condition ($instance.tags.SecurityControl -eq "Ignore") -Message "Compute instance has SecurityControl=Ignore"

$resourceGroupDetails = Invoke-AzJson -Arguments @(
    "group", "show",
    "--subscription", $subscriptionId,
    "--name", $resourceGroup
)
Assert-DeploymentCondition -Condition ($resourceGroupDetails.location -eq $ExpectedLocation) -Message "Resource group is in North Central US"
Assert-DeploymentCondition -Condition ($resourceGroupDetails.tags.SecurityControl -eq "Ignore") -Message "Resource group has SecurityControl=Ignore"

try {
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

Write-Host "Public Azure ML deployment validation completed successfully." -ForegroundColor Green
