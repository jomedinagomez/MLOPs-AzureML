param(
    [Parameter(Mandatory = $true)]
    [string]$DevResourceGroup,
    [Parameter(Mandatory = $true)]
    [string]$DevWorkspace,
    [Parameter(Mandatory = $true)]
    [string]$DevCompute,
    [Parameter(Mandatory = $true)]
    [string]$ProdResourceGroup,
    [Parameter(Mandatory = $true)]
    [string]$ProdWorkspace,
    [Parameter(Mandatory = $false)]
    [string]$Registry = "",
    [Parameter(Mandatory = $false)]
    [string]$ArtifactId = "m",
    [Parameter(Mandatory = $false)]
    [int]$TrafficPercent = 30,
    [Parameter(Mandatory = $false)]
    [string]$ModelBase = "taxi-class",
    [Parameter(Mandatory = $false)]
    [string]$DevEnvironment = "dev",
    [Parameter(Mandatory = $false)]
    [string]$ProdEnvironment = "prod",
    [Parameter(Mandatory = $false)]
    [string]$DevDeploymentName = "",
    [Parameter(Mandatory = $false)]
    [string]$ProdDeploymentName = "",
    [Parameter(Mandatory = $false)]
    [string[]]$DeploymentCandidates = @("blue", "green"),
    [Parameter(Mandatory = $false)]
    [string]$ModelVersion = "",
    [switch]$SkipProd,
    [switch]$ForceIntegrationRerun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Install-AzMlCliExtension {
    Write-Host "Ensuring Azure ML CLI extension is available" -ForegroundColor Cyan
    az extension show --name ml --only-show-errors | Out-Null
    if ($LASTEXITCODE -ne 0) {
        az extension add --name ml --yes --only-show-errors | Out-Null
    }
}

function Invoke-AmlJob {
    param(
        [string]$File,
        [string]$ResourceGroup,
        [string]$Workspace,
        [hashtable]$Overrides,
        [bool]$ForceRerun = $false
    )

    Write-Host "Submitting job using file: $File" -ForegroundColor Cyan
    $forceSetting = if ($ForceRerun) { "true" } else { "false" }
    $overrideArgs = @("--set", "settings.force_rerun=$forceSetting")
    foreach ($key in $Overrides.Keys) {
        $value = $Overrides[$key]
        if ($null -ne $value -and $value -ne "") {
            $overrideArgs += @("--set", "inputs.$key=$value")
        }
    }

    $jobId = az ml job create `
        --file $File `
        --resource-group $ResourceGroup `
        --workspace-name $Workspace `
        @overrideArgs `
        --query name -o tsv

    if ([string]::IsNullOrWhiteSpace($jobId)) {
        throw "Failed to submit job for $File"
    }

    Write-Host "Submitted job id: $jobId" -ForegroundColor Green

    Write-Host "Streaming logs..." -ForegroundColor Cyan
    az ml job stream `
        --name $jobId `
        --resource-group $ResourceGroup `
        --workspace-name $Workspace | Out-Null

    $status = az ml job show `
        --name $jobId `
        --resource-group $ResourceGroup `
        --workspace-name $Workspace `
        --query status -o tsv

    Write-Host "Job $jobId finished with status: $status" -ForegroundColor Yellow
    if ($status -ne "Completed") {
        throw "Job $jobId failed with status $status"
    }

    return $jobId
}

function Get-EndpointState {
    param(
        [string]$EndpointName,
        [string]$ResourceGroup,
        [string]$Workspace
    )

    $result = [pscustomobject]@{
        Exists  = $false
        Traffic = @{}
    }

    $endpointJson = az ml online-endpoint show `
        --name $EndpointName `
        --resource-group $ResourceGroup `
        --workspace-name $Workspace `
        -o json --only-show-errors 2>$null

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($endpointJson)) {
        return $result
    }

    $endpoint = $endpointJson | ConvertFrom-Json
    $traffic = @{}
    if ($endpoint -and $endpoint.traffic) {
        foreach ($entry in $endpoint.traffic.PSObject.Properties) {
            $traffic[$entry.Name] = [int]$entry.Value
        }
    }

    return [pscustomobject]@{
        Exists  = $true
        Traffic = $traffic
    }
}

function Test-DeploymentExists {
    param(
        [string]$DeploymentName,
        [string]$EndpointName,
        [string]$ResourceGroup,
        [string]$Workspace
    )

    if ([string]::IsNullOrWhiteSpace($DeploymentName)) {
        return $false
    }

    az ml online-deployment show `
        --name $DeploymentName `
        --endpoint-name $EndpointName `
        --resource-group $ResourceGroup `
        --workspace-name $Workspace `
        --query name -o tsv --only-show-errors 2>$null | Out-Null

    return ($LASTEXITCODE -eq 0)
}

function Get-DeploymentSlot {
    param(
        [string]$EndpointName,
        [string]$ResourceGroup,
        [string]$Workspace,
        [string[]]$Candidates
    )

    if (-not $Candidates -or $Candidates.Count -eq 0) {
        throw "Deployment candidate list cannot be empty"
    }

    $state = Get-EndpointState -EndpointName $EndpointName -ResourceGroup $ResourceGroup -Workspace $Workspace

    if (-not $state.Exists) {
        Write-Host "Endpoint $EndpointName not found; selecting first candidate" -ForegroundColor DarkGray
        return $Candidates[0]
    }

    foreach ($candidate in $Candidates) {
        if (-not (Test-DeploymentExists -DeploymentName $candidate -EndpointName $EndpointName -ResourceGroup $ResourceGroup -Workspace $Workspace)) {
            Write-Host "Deployment slot $candidate is unused on $EndpointName" -ForegroundColor DarkGray
            return $candidate
        }
    }

    $selected = $Candidates[0]
    $currentTraffic = 101
    foreach ($candidate in $Candidates) {
        $trafficValue = 0
        if ($state.Traffic.ContainsKey($candidate)) {
            $trafficValue = [int]$state.Traffic[$candidate]
        }
        if ($trafficValue -lt $currentTraffic) {
            $currentTraffic = $trafficValue
            $selected = $candidate
        }
    }

    Write-Host "All slots busy; reusing lowest traffic slot $selected" -ForegroundColor DarkGray
    return $selected
}

function Get-RegisteredModelVersion {
    param(
        [string]$JobId,
        [string]$ResourceGroup,
        [string]$Workspace
    )

    $tempPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("register-" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tempPath | Out-Null

    try {
        az ml job download `
            --name $JobId `
            --resource-group $ResourceGroup `
            --workspace-name $Workspace `
            --output-name register_metadata `
            --download-path $tempPath `
            --only-show-errors | Out-Null

        $metadataFile = Get-ChildItem -Path $tempPath -Recurse -Filter "model_versions.json" | Select-Object -First 1
        if (-not $metadataFile) {
            throw "model_versions.json not found in register metadata output for job $JobId"
        }

        $metadata = Get-Content $metadataFile.FullName | ConvertFrom-Json
        if ($metadata.registry_version) {
            return [string]$metadata.registry_version
        }
        if ($metadata.workspace_version) {
            return [string]$metadata.workspace_version
        }
        throw "No model version information found in register metadata output for job $JobId"
    }
    finally {
        if (Test-Path $tempPath) {
            Remove-Item $tempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-ModelVersionAvailable {
    param(
        [string]$ModelName,
        [string]$ModelVersion,
        [string]$ResourceGroup,
        [string]$Workspace,
        [string]$Registry
    )

    if ([string]::IsNullOrWhiteSpace($ModelVersion)) {
        return $false
    }

    if (-not [string]::IsNullOrWhiteSpace($Registry)) {
        az ml model show `
            --name $ModelName `
            --version $ModelVersion `
            --registry-name $Registry `
            --query id -o tsv --only-show-errors 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            return $true
        }
    }

    az ml model show `
        --name $ModelName `
        --version $ModelVersion `
        --resource-group $ResourceGroup `
        --workspace-name $Workspace `
        --query id -o tsv --only-show-errors 2>$null | Out-Null

    return ($LASTEXITCODE -eq 0)
}

Install-AzMlCliExtension

if (-not $DeploymentCandidates -or $DeploymentCandidates.Count -eq 0) {
    throw "DeploymentCandidates cannot be empty"
}

$devEndpointName = "$ModelBase-ws-$DevEnvironment-$ArtifactId-col"
$prodEndpointName = "$ModelBase-ws-$ProdEnvironment-$ArtifactId-col"
$modelName = "$ModelBase-$DevEnvironment-$ArtifactId"

if ([string]::IsNullOrWhiteSpace($DevDeploymentName)) {
    $DevDeploymentName = Get-DeploymentSlot -EndpointName $devEndpointName -ResourceGroup $DevResourceGroup -Workspace $DevWorkspace -Candidates $DeploymentCandidates
} else {
    Write-Host "Using provided dev deployment slot $DevDeploymentName" -ForegroundColor Cyan
}

Write-Host "Selected dev deployment slot: $DevDeploymentName" -ForegroundColor Cyan

if (-not $SkipProd.IsPresent) {
    if ([string]::IsNullOrWhiteSpace($ProdDeploymentName)) {
        $ProdDeploymentName = Get-DeploymentSlot -EndpointName $prodEndpointName -ResourceGroup $ProdResourceGroup -Workspace $ProdWorkspace -Candidates $DeploymentCandidates
    } else {
        Write-Host "Using provided prod deployment slot $ProdDeploymentName" -ForegroundColor Cyan
    }
    Write-Host "Selected prod deployment slot: $ProdDeploymentName" -ForegroundColor Cyan
}

$integrationOverrides = @{
    automl_compute        = $DevCompute
    artifact_id           = $ArtifactId
    automl_max_trials     = 5
    enable_vote_ensemble  = 'true'
    enable_stack_ensemble = 'true'
}
if (-not [string]::IsNullOrWhiteSpace($Registry)) {
    $integrationOverrides.registry = $Registry
}
$initialForce = $ForceIntegrationRerun.IsPresent
$integrationJob = Invoke-AmlJob -File "pipelines/integration-compare-pipeline.yaml" -ResourceGroup $DevResourceGroup -Workspace $DevWorkspace -Overrides $integrationOverrides -ForceRerun:$initialForce

$ModelVersionProvided = -not [string]::IsNullOrWhiteSpace($ModelVersion)
$resolvedModelVersion = $ModelVersion
if (-not $ModelVersionProvided) {
    $resolvedModelVersion = Get-RegisteredModelVersion -JobId $integrationJob -ResourceGroup $DevResourceGroup -Workspace $DevWorkspace
    Write-Host "Deploying registered model version $resolvedModelVersion" -ForegroundColor Cyan
} else {
    Write-Host "Deploying specified model version $resolvedModelVersion" -ForegroundColor Cyan
}

if (-not (Test-ModelVersionAvailable -ModelName $modelName -ModelVersion $resolvedModelVersion -ResourceGroup $DevResourceGroup -Workspace $DevWorkspace -Registry $Registry)) {
    if ($ModelVersionProvided) {
        throw "Specified model version $resolvedModelVersion for $modelName was not found in registry or workspace."
    }

    Write-Host "Model version $resolvedModelVersion for $modelName not found; rerunning integration pipeline with force_rerun=true" -ForegroundColor Yellow
    $integrationJob = Invoke-AmlJob -File "pipelines/integration-compare-pipeline.yaml" -ResourceGroup $DevResourceGroup -Workspace $DevWorkspace -Overrides $integrationOverrides -ForceRerun:$true
    $resolvedModelVersion = Get-RegisteredModelVersion -JobId $integrationJob -ResourceGroup $DevResourceGroup -Workspace $DevWorkspace
    Write-Host "New registered model version $resolvedModelVersion" -ForegroundColor Cyan

    if (-not (Test-ModelVersionAvailable -ModelName $modelName -ModelVersion $resolvedModelVersion -ResourceGroup $DevResourceGroup -Workspace $DevWorkspace -Registry $Registry)) {
        throw "Model version $resolvedModelVersion for $modelName was not found after forcing integration rerun. Verify the integration pipeline registration step succeeded."
    }
}

$ModelVersion = $resolvedModelVersion

$devOverrides = @{
    deployment_name = $DevDeploymentName
    traffic_percent = $TrafficPercent
    artifact_id     = $ArtifactId
    model_version   = $ModelVersion
}
if (-not [string]::IsNullOrWhiteSpace($Registry)) {
    $devOverrides.registry = $Registry
}
$devJob = Invoke-AmlJob -File "pipelines/dev-deploy-validation.yaml" -ResourceGroup $DevResourceGroup -Workspace $DevWorkspace -Overrides $devOverrides

$prodJob = $null
if (-not $SkipProd.IsPresent) {
    $prodOverrides = @{
        deployment_name = $ProdDeploymentName
        traffic_percent = $TrafficPercent
        artifact_id     = $ArtifactId
        model_version   = $ModelVersion
    }
    if (-not [string]::IsNullOrWhiteSpace($Registry)) {
        $prodOverrides.registry = $Registry
    }
    $prodJob = Invoke-AmlJob -File "pipelines/prod-deploy-pipeline.yaml" -ResourceGroup $ProdResourceGroup -Workspace $ProdWorkspace -Overrides $prodOverrides
    Write-Host "Prod job completed: $prodJob" -ForegroundColor Green
} else {
    Write-Host "Skipping prod pipeline as requested." -ForegroundColor Magenta
}

Write-Host "Integration job: $integrationJob" -ForegroundColor Green
Write-Host "Dev validation job: $devJob" -ForegroundColor Green
if ($prodJob) {
    Write-Host "Prod deployment job: $prodJob" -ForegroundColor Green
}
