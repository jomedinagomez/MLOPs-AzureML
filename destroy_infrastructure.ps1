# Destroy Azure ML Infrastructure
# This script safely destroys the Terraform-managed Azure ML platform

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("mlops", "non-networking", "single-workspace", "spark-workspace")]
    [string]$Stack = "non-networking"
)

# Exit on error
$ErrorActionPreference = "Stop"

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Azure ML Infrastructure Destruction Script: $Stack" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$infraDir = Join-Path $scriptDir "infra\$Stack"

Write-Host "Checking infrastructure directory..." -ForegroundColor Yellow
if (-not (Test-Path $infraDir)) {
    Write-Error "Infrastructure directory not found: $infraDir"
    exit 1
}

Set-Location $infraDir
Write-Host "✓ Changed to: $infraDir" -ForegroundColor Green
Write-Host ""

# Check if terraform.tfstate exists
if (-not (Test-Path "terraform.tfstate")) {
    Write-Warning "No terraform.tfstate file found. Infrastructure may not be deployed."
    $continue = Read-Host "Continue anyway? (y/N)"
    if ($continue -ne 'y') {
        Write-Host "Aborted." -ForegroundColor Yellow
        exit 0
    }
}

# Read required deployment variables from terraform.tfvars
Write-Host "Reading configuration..." -ForegroundColor Yellow
if (-not (Test-Path "terraform.tfvars")) {
    Write-Error "terraform.tfvars is required to destroy '$Stack' because Terraform must receive the same deployment inputs."
    exit 1
}

$tfvarsContent = Get-Content "terraform.tfvars" -Raw
$namingSuffix = ""
$deploymentLocation = "canadacentral"
$subscriptionId = az account show --query id -o tsv
if ($tfvarsContent -match 'naming_suffix\s*=\s*"([^"]+)"') {
    $namingSuffix = $matches[1]
    Write-Host "✓ Found naming suffix: $namingSuffix" -ForegroundColor Green
}
if ($tfvarsContent -match 'location\s*=\s*"([^"]+)"') {
    $deploymentLocation = $matches[1]
}
if ($tfvarsContent -match 'subscription_id\s*=\s*"([^"]+)"') {
    $subscriptionId = $matches[1]
}

if ([string]::IsNullOrWhiteSpace($namingSuffix)) {
    Write-Error "terraform.tfvars must contain a non-empty naming_suffix."
    exit 1
}

$workspaceKeyVaultName = $null
$cmkKeyVaultName = $null
if ($Stack -in @("single-workspace", "spark-workspace")) {
    try {
        $linkedResources = terraform output -json linked_resources 2>$null | ConvertFrom-Json
        $workspaceKeyVaultName = $linkedResources.key_vault_name
        $cmkResources = terraform output -json cmk 2>$null | ConvertFrom-Json
        if ($cmkResources.key_vault_id) {
            $cmkKeyVaultName = Split-Path -Leaf $cmkResources.key_vault_id
        }
    } catch {
        Write-Warning "Unable to resolve Key Vault output names before destroy."
    }
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Red
Write-Host "WARNING: DESTRUCTIVE OPERATION" -ForegroundColor Red
Write-Host "================================================" -ForegroundColor Red
Write-Host ""
Write-Host "This will PERMANENTLY DELETE all resources with suffix: $namingSuffix" -ForegroundColor Yellow
Write-Host ""
Write-Host "Resources to be destroyed include:" -ForegroundColor Yellow
Write-Host "  - Azure ML workspace resources managed by '$Stack'" -ForegroundColor Yellow
Write-Host "  - Storage Accounts" -ForegroundColor Yellow
Write-Host "  - Container Registries" -ForegroundColor Yellow
Write-Host "  - Key Vaults" -ForegroundColor Yellow
Write-Host "  - Identities and role assignments" -ForegroundColor Yellow
Write-Host "  - Networking resources managed by the selected stack, if any" -ForegroundColor Yellow
Write-Host "  - All associated resource groups" -ForegroundColor Yellow
Write-Host ""

$confirmation = Read-Host "Type 'DESTROY' to confirm (case-sensitive)"
if ($confirmation -ne 'DESTROY') {
    Write-Host "Destruction cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Starting destruction process..." -ForegroundColor Red
Write-Host ""

# Initialize Terraform (in case it's not initialized)
Write-Host "Step 1: Initializing Terraform..." -ForegroundColor Cyan
terraform init
if ($LASTEXITCODE -ne 0) {
    Write-Error "Terraform init failed"
    exit 1
}
Write-Host "✓ Terraform initialized" -ForegroundColor Green
Write-Host ""

# Show destroy plan
Write-Host "Step 2: Generating destroy plan..." -ForegroundColor Cyan
terraform plan -destroy -var naming_suffix=$namingSuffix -out=destroy.tfplan
if ($LASTEXITCODE -ne 0) {
    Write-Error "Terraform plan failed"
    exit 1
}
Write-Host "✓ Destroy plan generated" -ForegroundColor Green
Write-Host ""

# Final confirmation
Write-Host "================================================" -ForegroundColor Yellow
Write-Host "FINAL CONFIRMATION" -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Yellow
$finalConfirm = Read-Host "Execute destroy plan? (yes/NO)"
if ($finalConfirm -ne 'yes') {
    Write-Host "Destruction cancelled. Destroy plan saved as destroy.tfplan" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Step 3: Executing destroy..." -ForegroundColor Red
Write-Host "This may take 10-15 minutes..." -ForegroundColor Yellow
Write-Host ""

# Execute destroy with auto-approve since we already confirmed
terraform apply destroy.tfplan
$destroyExitCode = $LASTEXITCODE

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Destruction Results" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

if ($destroyExitCode -eq 0) {
    Write-Host "✓ Infrastructure destroyed successfully!" -ForegroundColor Green
    Write-Host ""

    if ($Stack -in @("single-workspace", "spark-workspace") -and $workspaceKeyVaultName) {
        Write-Host "Purging unprotected workspace Key Vault: $workspaceKeyVaultName" -ForegroundColor Yellow
        $workspaceVaultPurged = $false
        for ($attempt = 1; $attempt -le 12; $attempt++) {
            az keyvault purge `
                --name $workspaceKeyVaultName `
                --location $deploymentLocation `
                --subscription $subscriptionId `
                --only-show-errors 2>$null
            if ($LASTEXITCODE -eq 0) {
                $workspaceVaultPurged = $true
                break
            }
            Start-Sleep -Seconds 10
        }
        if ($workspaceVaultPurged) {
            Write-Host "✓ Workspace Key Vault purged" -ForegroundColor Green
        } else {
            Write-Warning "Workspace Key Vault could not be purged automatically: $workspaceKeyVaultName"
        }
    }

    if ($Stack -in @("single-workspace", "spark-workspace") -and $cmkKeyVaultName) {
        Write-Warning "Azure-required purge protection keeps CMK vault '$cmkKeyVaultName' recoverable until its retention period ends."
    }
    
    # Verify resource groups are gone
    Write-Host "Verifying cleanup..." -ForegroundColor Yellow
    Write-Host "Checking for remaining resource groups with suffix '$namingSuffix'..." -ForegroundColor Yellow
    
    $remainingRGs = az group list --query "[?contains(name, '-$namingSuffix') && starts_with(name, 'rg-aml-')].name" -o tsv 2>$null
    
    if ([string]::IsNullOrEmpty($remainingRGs)) {
        Write-Host "✓ No resource groups found. Cleanup successful!" -ForegroundColor Green
    } else {
        Write-Warning "Some resource groups still exist:"
        Write-Host $remainingRGs -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Manual cleanup may be required. Run:" -ForegroundColor Yellow
        Write-Host "  az group list --query `"[?contains(name, '-$namingSuffix')].name`" -o table" -ForegroundColor DarkGray
    }
    
    # Clean up plan files
    if (Test-Path "destroy.tfplan") {
        Remove-Item "destroy.tfplan" -Force
        Write-Host "✓ Cleaned up temporary files" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Green
    Write-Host "Next Steps:" -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Green
    Write-Host "1. Review Azure Portal to confirm all resources are removed" -ForegroundColor White
    Write-Host "2. Check for any orphaned managed resource groups" -ForegroundColor White
    Write-Host "3. If you plan to redeploy:" -ForegroundColor White
    Write-Host "   - Confirm soft-deleted names are reusable before using the same suffix" -ForegroundColor White
    Write-Host "   - Key Vaults with purge protection enabled can delay permanent deletion and name reuse" -ForegroundColor White
    Write-Host "   - Workspaces should be permanently deleted" -ForegroundColor White
    
} else {
    Write-Host "✗ Destruction encountered errors" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting steps:" -ForegroundColor Yellow
    Write-Host "1. Check the error messages above" -ForegroundColor White
    Write-Host "2. You may need to manually delete some resources via Azure Portal" -ForegroundColor White
    Write-Host "3. Try running the destroy command again:" -ForegroundColor White
    Write-Host "   terraform destroy -auto-approve -var naming_suffix=$namingSuffix" -ForegroundColor DarkGray
    Write-Host "4. For stuck resources, use targeted destroy:" -ForegroundColor White
    Write-Host "   terraform destroy -target=<resource_address> -var naming_suffix=$namingSuffix" -ForegroundColor DarkGray
    exit 1
}

Write-Host ""
Write-Host "Destroy process complete!" -ForegroundColor Cyan
