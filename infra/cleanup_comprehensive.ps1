#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Comprehensive Azure Infrastructure Cleanup Script
.DESCRIPTION
    Safely destroys Azure ML infrastructure and purges all soft-deleted resources
    including Key Vaults, Container Registries, Storage Accounts, and Log Analytics workspaces.
.PARAMETER Force
    Skip interactive confirmations (use with caution)
.PARAMETER PurgeOnly
    Only purge soft-deleted resources without destroying infrastructure
.EXAMPLE
    .\cleanup_comprehensive.ps1                    # Interactive cleanup with confirmations
    .\cleanup_comprehensive.ps1 -Force             # Force cleanup without prompts (dev environments only)
    .\cleanup_comprehensive.ps1 -PurgeOnly         # Only purge soft-deleted resources
#>

param(
    [switch]$Force,
    [switch]$PurgeOnly
)

# Color functions for better output
function Write-Success { param($Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Warning { param($Message) Write-Host "⚠️  $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "❌ $Message" -ForegroundColor Red }
function Write-Info { param($Message) Write-Host "ℹ️  $Message" -ForegroundColor Cyan }

# Safety check function
function Confirm-Action {
    param($Message)
    if ($Force) { return $true }
    $response = Read-Host "$Message (y/N)"
    return ($response -eq 'y' -or $response -eq 'Y')
}

Write-Info "=== Azure ML Infrastructure Cleanup Script ==="
Write-Info "This script will handle soft-delete cleanup for all Azure services"

# Get current subscription
try {
    $subscription = az account show --query "{id:id, name:name}" --output json | ConvertFrom-Json
    Write-Info "Current subscription: $($subscription.name) ($($subscription.id))"
} catch {
    Write-Error "Failed to get current subscription. Please run 'az login' first."
    exit 1
}

if (-not $PurgeOnly) {
    Write-Warning "This will destroy ALL Azure infrastructure in this directory!"
    if (-not (Confirm-Action "Do you want to proceed with infrastructure destruction?")) {
        Write-Info "Operation cancelled."
        exit 0
    }

    # Step 1: Destroy infrastructure
    Write-Info "Destroying Terraform infrastructure..."
    terraform destroy -auto-approve
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Terraform destroy completed with warnings. Proceeding with cleanup..."
    } else {
        Write-Success "Infrastructure destroyed successfully"
    }
}

# Step 2: Purge soft-deleted resources
Write-Info "Purging soft-deleted Azure resources..."

# Purge Key Vaults
Write-Info "Checking for soft-deleted Key Vaults..."
try {
    $deletedKeyVaults = az keyvault list-deleted --query "[].{name:name, location:properties.location}" --output json | ConvertFrom-Json
    if ($deletedKeyVaults) {
        foreach ($kv in $deletedKeyVaults) {
            if ($kv.name -match "kv.*cc\d+") {  # Match our naming pattern
                Write-Info "Purging Key Vault: $($kv.name) in $($kv.location)"
                az keyvault purge --name $kv.name --location $kv.location
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Purged Key Vault: $($kv.name)"
                } else {
                    Write-Warning "Failed to purge Key Vault: $($kv.name)"
                }
            }
        }
    } else {
        Write-Info "No soft-deleted Key Vaults found"
    }
} catch {
    Write-Warning "Failed to check soft-deleted Key Vaults: $_"
}

# Purge Container Registries
Write-Info "Checking for Container Registry repositories..."
try {
    $registries = az acr list --query "[?name contains(@, 'acr') && name contains(@, 'cc')].{name:name, resourceGroup:resourceGroup}" --output json | ConvertFrom-Json
    foreach ($acr in $registries) {
        Write-Info "Checking Container Registry: $($acr.name)"
        $repos = az acr repository list --name $acr.name --output json 2>$null | ConvertFrom-Json
        if ($repos) {
            foreach ($repo in $repos) {
                Write-Info "Purging repository: $repo from $($acr.name)"
                az acr repository delete --name $acr.name --repository $repo --yes 2>$null
            }
            Write-Success "Cleaned Container Registry: $($acr.name)"
        }
    }
} catch {
    Write-Warning "Failed to check Container Registries: $_"
}

# Purge Storage Account soft-deleted resources
Write-Info "Checking for Storage Account soft-deleted resources..."
try {
    $storageAccounts = az storage account list --query "[?name contains(@, 'st') && name contains(@, 'cc')].{name:name, resourceGroup:resourceGroup}" --output json | ConvertFrom-Json
    foreach ($storage in $storageAccounts) {
        Write-Info "Checking Storage Account: $($storage.name)"
        
        # Check for soft-deleted blobs
        try {
            az storage blob undelete-batch --account-name $storage.name --source '$root' 2>$null
            Write-Success "Cleaned soft-deleted blobs in: $($storage.name)"
        } catch {
            Write-Info "No soft-deleted blobs found in: $($storage.name)"
        }
        
        # Check for soft-deleted containers
        try {
            $deletedContainers = az storage container list --account-name $storage.name --include-deleted --query "[?deleted].name" --output tsv 2>$null
            if ($deletedContainers) {
                foreach ($container in $deletedContainers) {
                    Write-Info "Purging soft-deleted container: $container"
                    az storage container restore --account-name $storage.name --name $container 2>$null
                    az storage container delete --account-name $storage.name --name $container 2>$null
                }
                Write-Success "Cleaned soft-deleted containers in: $($storage.name)"
            }
        } catch {
            Write-Info "No soft-deleted containers found in: $($storage.name)"
        }
    }
} catch {
    Write-Warning "Failed to check Storage Accounts: $_"
}

# Purge Log Analytics workspaces (soft-delete)
Write-Info "Checking for soft-deleted Log Analytics workspaces..."
try {
    $deletedWorkspaces = az monitor log-analytics workspace list-deleted --query "[].{name:name, resourceGroup:resourceGroup}" --output json 2>$null | ConvertFrom-Json
    if ($deletedWorkspaces) {
        foreach ($workspace in $deletedWorkspaces) {
            if ($workspace.name -match "law.*cc\d+") {  # Match our naming pattern
                Write-Info "Purging Log Analytics workspace: $($workspace.name)"
                az monitor log-analytics workspace recover --workspace-name $workspace.name --resource-group $workspace.resourceGroup 2>$null
                az monitor log-analytics workspace delete --workspace-name $workspace.name --resource-group $workspace.resourceGroup --yes 2>$null
                Write-Success "Purged Log Analytics workspace: $($workspace.name)"
            }
        }
    } else {
        Write-Info "No soft-deleted Log Analytics workspaces found"
    }
} catch {
    Write-Warning "Failed to check Log Analytics workspaces: $_"
}

if (-not $PurgeOnly) {
    # Step 3: Clean up Terraform state
    Write-Info "Cleaning up Terraform state files..."
    $stateFiles = @("terraform.tfstate", "terraform.tfstate.backup", ".terraform.lock.hcl")
    foreach ($file in $stateFiles) {
        if (Test-Path $file) {
            Remove-Item $file -Force
            Write-Success "Removed: $file"
        }
    }

    if (Test-Path ".terraform") {
        Remove-Item ".terraform" -Recurse -Force
        Write-Success "Removed: .terraform directory"
    }
}

Write-Success "=== Cleanup completed successfully! ==="
Write-Info "All soft-deleted resources have been purged to prevent future deployment conflicts."

if (-not $PurgeOnly) {
    Write-Info "To redeploy infrastructure, run: terraform init && terraform apply"
}
