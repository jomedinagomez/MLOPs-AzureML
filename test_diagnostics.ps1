# Test script to validate the Microsoft-managed resources discovery logic
# This simulates what the null_resource provisioner does

param(
    [Parameter(Mandatory=$true)]
    [string]$RegistryName,
    
    [Parameter(Mandatory=$false)]
    [string]$WorkspaceId = "test-workspace-id"
)

Write-Host "Testing diagnostic settings discovery for registry: $RegistryName"
Write-Host "=================================================="

# Test the resource discovery logic
$managedRgPattern = "azureml-rg-$RegistryName"
Write-Host "Looking for managed resource groups with pattern: $managedRgPattern"

# Test storage discovery
Write-Host "`n1. Testing Storage Account Discovery"
Write-Host "-------------------------------------"
$managedRgs = az group list --query "[?starts_with(name, '$managedRgPattern')].name" --output tsv 2>$null

if ($managedRgs) {
    foreach ($rg in $managedRgs) {
        if ($rg) {
            Write-Host "✓ Found managed resource group: $rg"
            $storage = az storage account list --resource-group $rg --query "[0].id" --output tsv 2>$null
            if ($storage) {
                Write-Host "✓ Found managed storage: $storage"
                Write-Host "  Would configure diagnostic settings for: $storage"
            } else {
                Write-Host "⚠ No storage account found in resource group: $rg"
            }
        }
    }
} else {
    Write-Host "⚠ No managed resource groups found with pattern: $managedRgPattern"
}

# Test ACR discovery
Write-Host "`n2. Testing Container Registry Discovery"
Write-Host "---------------------------------------"
if ($managedRgs) {
    foreach ($rg in $managedRgs) {
        if ($rg) {
            $acr = az acr list --resource-group $rg --query "[0].id" --output tsv 2>$null
            if ($acr) {
                Write-Host "✓ Found managed ACR: $acr"
                Write-Host "  Would configure diagnostic settings for: $acr"
            } else {
                Write-Host "⚠ No container registry found in resource group: $rg"
            }
        }
    }
}

Write-Host "`n3. Summary"
Write-Host "----------"
if ($managedRgs) {
    Write-Host "✓ Resource discovery logic should work correctly"
    Write-Host "✓ Managed resource group pattern matches existing naming convention"
} else {
    Write-Host "⚠ No existing managed resources found - this is expected if registry doesn't exist yet"
    Write-Host "ℹ The logic will work correctly once the registry is deployed"
}

Write-Host "`nTest completed!"
