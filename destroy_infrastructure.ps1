# Destroy Azure ML Infrastructure
# This script safely destroys the Terraform-managed Azure ML platform
# Location: infra_no_networking/

# Exit on error
$ErrorActionPreference = "Stop"

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Azure ML Infrastructure Destruction Script" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Change to the infra_no_networking directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$infraDir = Join-Path $scriptDir "infra_no_networking"

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

# Read naming suffix from terraform.tfvars
Write-Host "Reading configuration..." -ForegroundColor Yellow
$namingSuffix = ""
if (Test-Path "terraform.tfvars") {
    $tfvarsContent = Get-Content "terraform.tfvars" -Raw
    if ($tfvarsContent -match 'naming_suffix\s*=\s*"([^"]+)"') {
        $namingSuffix = $matches[1]
        Write-Host "✓ Found naming suffix: $namingSuffix" -ForegroundColor Green
    }
}

if ([string]::IsNullOrEmpty($namingSuffix)) {
    Write-Warning "Could not determine naming suffix from terraform.tfvars"
    $namingSuffix = Read-Host "Enter your naming suffix (e.g., '01')"
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Red
Write-Host "WARNING: DESTRUCTIVE OPERATION" -ForegroundColor Red
Write-Host "================================================" -ForegroundColor Red
Write-Host ""
Write-Host "This will PERMANENTLY DELETE all resources with suffix: $namingSuffix" -ForegroundColor Yellow
Write-Host ""
Write-Host "Resources to be destroyed include:" -ForegroundColor Yellow
Write-Host "  - Azure ML Workspaces (dev, integration, prod)" -ForegroundColor Yellow
Write-Host "  - Storage Accounts" -ForegroundColor Yellow
Write-Host "  - Container Registries" -ForegroundColor Yellow
Write-Host "  - Key Vaults" -ForegroundColor Yellow
Write-Host "  - Service Principals" -ForegroundColor Yellow
Write-Host "  - Virtual Networks (if deployed)" -ForegroundColor Yellow
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
    Write-Host "   - You can use the same naming suffix now" -ForegroundColor White
    Write-Host "   - Key Vaults should be purged (auto-purge enabled by default)" -ForegroundColor White
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
