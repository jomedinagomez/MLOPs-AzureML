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
    [string[]]$DeploymentNames = @("blue", "green"),
    [Parameter(Mandatory = $false)]
    [string]$ModelVersion = "",
    [switch]$SkipProd
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
        [hashtable]$Overrides
    )

    Write-Host "Submitting job using file: $File" -ForegroundColor Cyan
    $overrideArgs = @("--set", "settings.force_rerun=false")
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

function Remove-WorkspaceModelVersions {
    param(
        [string]$ModelName,
        [string]$ResourceGroup,
        [string]$Workspace
    )

    Write-Host "Checking workspace model $ModelName in $Workspace" -ForegroundColor Cyan
    $listJson = az ml model list `
        --name $ModelName `
        --resource-group $ResourceGroup `
        --workspace-name $Workspace `
        -o json --only-show-errors 2>$null

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($listJson)) {
        Write-Host "No model versions found for $ModelName" -ForegroundColor DarkGray
        return
    }

    $models = $listJson | ConvertFrom-Json
    if (-not $models) {
        Write-Host "No model versions found for $ModelName" -ForegroundColor DarkGray
        return
    }

    foreach ($model in $models) {
        $version = $model.version
        if ([string]::IsNullOrWhiteSpace($version)) {
            continue
        }
        Write-Host "Archiving model $ModelName version $version" -ForegroundColor Yellow
        az ml model archive `
            --name $ModelName `
            --version $version `
            --resource-group $ResourceGroup `
            --workspace-name $Workspace `
            --only-show-errors | Out-Null
    }
}

function Remove-RegistryModelVersions {
    param(
        [string]$ModelName,
        [string]$RegistryName
    )

    if ([string]::IsNullOrWhiteSpace($RegistryName)) {
        return
    }

    Write-Host "Checking registry model $ModelName in $RegistryName" -ForegroundColor Cyan
    $listJson = az ml model list `
        --name $ModelName `
        --registry-name $RegistryName `
        -o json --only-show-errors 2>$null

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($listJson)) {
        Write-Host "No registry versions found for $ModelName" -ForegroundColor DarkGray
        return
    }

    $models = $listJson | ConvertFrom-Json
    if (-not $models) {
        Write-Host "No registry versions found for $ModelName" -ForegroundColor DarkGray
        return
    }

    foreach ($model in $models) {
        $version = $model.version
        if ([string]::IsNullOrWhiteSpace($version)) {
            continue
        }
        Write-Host "Archiving registry model $ModelName version $version" -ForegroundColor Yellow
        az ml model archive `
            --name $ModelName `
            --version $version `
            --registry-name $RegistryName `
            --only-show-errors | Out-Null
    }
}

function Remove-Endpoint {
    param(
        [string]$EndpointName,
        [string]$ResourceGroup,
        [string]$Workspace
    )

    Write-Host "Checking endpoint $EndpointName in $Workspace" -ForegroundColor Cyan
    az ml online-endpoint show `
        --name $EndpointName `
        --resource-group $ResourceGroup `
        --workspace-name $Workspace `
        --only-show-errors | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Endpoint $EndpointName not found" -ForegroundColor DarkGray
        return
    }

    Write-Host "Deleting endpoint $EndpointName" -ForegroundColor Yellow
    az ml online-endpoint delete `
        --name $EndpointName `
        --resource-group $ResourceGroup `
        --workspace-name $Workspace `
        --yes `
        --only-show-errors | Out-Null
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

Install-AzMlCliExtension

if (-not $DeploymentNames -or $DeploymentNames.Count -eq 0) {
    throw "At least one deployment name must be supplied"
}

$devModelName = "$ModelBase-$DevEnvironment-$ArtifactId"
$prodModelName = "$ModelBase-$ProdEnvironment-$ArtifactId"
$devEndpointName = "$ModelBase-ws-$DevEnvironment-$ArtifactId-col"
$prodEndpointName = "$ModelBase-ws-$ProdEnvironment-$ArtifactId-col"

Write-Host "Purging dev workspace assets" -ForegroundColor Magenta
Remove-Endpoint -EndpointName $devEndpointName -ResourceGroup $DevResourceGroup -Workspace $DevWorkspace
Remove-WorkspaceModelVersions -ModelName $devModelName -ResourceGroup $DevResourceGroup -Workspace $DevWorkspace

Write-Host "Purging prod workspace assets" -ForegroundColor Magenta
Remove-Endpoint -EndpointName $prodEndpointName -ResourceGroup $ProdResourceGroup -Workspace $ProdWorkspace
Remove-WorkspaceModelVersions -ModelName $prodModelName -ResourceGroup $ProdResourceGroup -Workspace $ProdWorkspace

if (-not [string]::IsNullOrWhiteSpace($Registry)) {
    Write-Host "Purging registry assets" -ForegroundColor Magenta
    Remove-RegistryModelVersions -ModelName $devModelName -RegistryName $Registry
    if ($prodModelName -ne $devModelName) {
        Remove-RegistryModelVersions -ModelName $prodModelName -RegistryName $Registry
    }
}

$selectedDeployment = $DeploymentNames[0]
Write-Host "Using deployment slot $selectedDeployment for initial runs" -ForegroundColor Cyan

$integrationOverrides = @{
    automl_compute        = $DevCompute
    artifact_id           = $ArtifactId
    automl_max_trials     = 1
    enable_vote_ensemble  = 'false'
    enable_stack_ensemble = 'false'
}
if (-not [string]::IsNullOrWhiteSpace($Registry)) {
    $integrationOverrides.registry = $Registry
}
$integrationJob = Invoke-AmlJob -File "pipelines/integration-compare-pipeline.yaml" -ResourceGroup $DevResourceGroup -Workspace $DevWorkspace -Overrides $integrationOverrides

if ([string]::IsNullOrWhiteSpace($ModelVersion)) {
    $ModelVersion = Get-RegisteredModelVersion -JobId $integrationJob -ResourceGroup $DevResourceGroup -Workspace $DevWorkspace
    Write-Host "Deploying registered model version $ModelVersion" -ForegroundColor Cyan
} else {
    Write-Host "Deploying specified model version $ModelVersion" -ForegroundColor Cyan
}

$devOverrides = @{
    deployment_name = $selectedDeployment
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
        deployment_name = $selectedDeployment
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
