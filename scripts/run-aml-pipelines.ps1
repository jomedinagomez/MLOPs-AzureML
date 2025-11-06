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
    [string]$ArtifactId = "m-local",
    [Parameter(Mandatory = $false)]
    [string]$DeploymentName = "",
    [Parameter(Mandatory = $false)]
    [int]$TrafficPercent = 30,
    [Parameter(Mandatory = $false)]
    [string]$ModelVersion = "",
    [switch]$SkipProd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
        if ($null -ne $Overrides[$key] -and $Overrides[$key] -ne "") {
            $overrideArgs += @("--set", "inputs.$key=$($Overrides[$key])")
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
        --workspace-name $Workspace

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
            --name $jobId `
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

Write-Host "Ensuring Azure ML CLI extension is available" -ForegroundColor Cyan
az extension add --name ml --yes | Out-Null

$integrationOverrides = @{
    automl_compute = $DevCompute
    artifact_id     = $ArtifactId
}
if ($Registry) {
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
    deployment_name  = $DeploymentName
    traffic_percent  = $TrafficPercent
    artifact_id      = $ArtifactId
    model_version    = $ModelVersion
}
if ($Registry) {
    $devOverrides.registry = $Registry
}
$devJob = Invoke-AmlJob -File "pipelines/dev-deploy-validation.yaml" -ResourceGroup $DevResourceGroup -Workspace $DevWorkspace -Overrides $devOverrides

$prodJob = $null
if (-not $SkipProd.IsPresent) {
    $prodOverrides = @{
        deployment_name = $DeploymentName
        traffic_percent = $TrafficPercent
        artifact_id     = $ArtifactId
        model_version   = $ModelVersion
    }
    if ($Registry) {
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
