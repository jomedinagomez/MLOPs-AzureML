# MLOPs-AzureML Empty File Cleanup Script
# This script safely removes empty files and folders while preserving important structure

Write-Host "🧹 MLOPs-AzureML Workspace Cleanup" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

# Set location
Set-Location "c:\Users\jomedin\Documents\MLOPs-AzureML"

# Files to definitely keep even if empty (important for structure)
$KeepFiles = @(
    "terraform.tfstate",  # Terraform state - NEVER delete
    ".gitkeep",          # Git folder structure
    "__init__.py"        # Python package structure
)

# Get all empty files
$EmptyFiles = Get-ChildItem -Recurse -File | Where-Object { $_.Length -eq 0 }

Write-Host "Found $($EmptyFiles.Count) empty files" -ForegroundColor Yellow

# Categorize files
$SafeToDelete = @()
$KeepThese = @()

foreach ($file in $EmptyFiles) {
    $filename = $file.Name
    $keep = $false
    
    foreach ($keepPattern in $KeepFiles) {
        if ($filename -like $keepPattern) {
            $keep = $true
            break
        }
    }
    
    if ($keep) {
        $KeepThese += $file
    } else {
        $SafeToDelete += $file
    }
}

Write-Host "`n📋 ANALYSIS RESULTS:" -ForegroundColor Cyan
Write-Host "Files safe to delete: $($SafeToDelete.Count)" -ForegroundColor Green
Write-Host "Files to keep (important): $($KeepThese.Count)" -ForegroundColor Yellow

if ($SafeToDelete.Count -gt 0) {
    Write-Host "`n🗑️  FILES SAFE TO DELETE:" -ForegroundColor Green
    foreach ($file in $SafeToDelete) {
        $relativePath = $file.FullName.Replace("c:\Users\jomedin\Documents\MLOPs-AzureML\", "")
        Write-Host "  ❌ $relativePath" -ForegroundColor Red
    }
}

if ($KeepThese.Count -gt 0) {
    Write-Host "`n🛡️  FILES TO KEEP (IMPORTANT):" -ForegroundColor Yellow
    foreach ($file in $KeepThese) {
        $relativePath = $file.FullName.Replace("c:\Users\jomedin\Documents\MLOPs-AzureML\", "")
        Write-Host "  ✅ $relativePath" -ForegroundColor Green
    }
}

Write-Host "`n🤔 Do you want to proceed with deletion? (y/N): " -ForegroundColor Cyan -NoNewline
$response = Read-Host

if ($response -eq 'y' -or $response -eq 'Y') {
    Write-Host "`n🗑️  Deleting empty files..." -ForegroundColor Yellow
    
    $deleteCount = 0
    foreach ($file in $SafeToDelete) {
        try {
            Remove-Item $file.FullName -Force
            $relativePath = $file.FullName.Replace("c:\Users\jomedin\Documents\MLOPs-AzureML\", "")
            Write-Host "  ✅ Deleted: $relativePath" -ForegroundColor Green
            $deleteCount++
        }
        catch {
            $relativePath = $file.FullName.Replace("c:\Users\jomedin\Documents\MLOPs-AzureML\", "")
            Write-Host "  ❌ Failed to delete: $relativePath - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    Write-Host "`n✨ Cleanup complete! Deleted $deleteCount files." -ForegroundColor Green
    
    # Now check for empty directories
    Write-Host "`n🔍 Checking for empty directories..." -ForegroundColor Cyan
    $EmptyDirs = Get-ChildItem -Recurse -Directory | Where-Object { 
        (Get-ChildItem $_.FullName -Recurse | Measure-Object).Count -eq 0 
    }
    
    if ($EmptyDirs.Count -gt 0) {
        Write-Host "Found $($EmptyDirs.Count) empty directories:" -ForegroundColor Yellow
        foreach ($dir in $EmptyDirs) {
            $relativePath = $dir.FullName.Replace("c:\Users\jomedin\Documents\MLOPs-AzureML\", "")
            Write-Host "  📁 $relativePath" -ForegroundColor Blue
        }
        
        Write-Host "`n🤔 Remove empty directories too? (y/N): " -ForegroundColor Cyan -NoNewline
        $dirResponse = Read-Host
        
        if ($dirResponse -eq 'y' -or $dirResponse -eq 'Y') {
            foreach ($dir in $EmptyDirs) {
                try {
                    Remove-Item $dir.FullName -Force
                    $relativePath = $dir.FullName.Replace("c:\Users\jomedin\Documents\MLOPs-AzureML\", "")
                    Write-Host "  ✅ Removed directory: $relativePath" -ForegroundColor Green
                }
                catch {
                    $relativePath = $dir.FullName.Replace("c:\Users\jomedin\Documents\MLOPs-AzureML\", "")
                    Write-Host "  ❌ Failed to remove: $relativePath - $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    } else {
        Write-Host "No empty directories found. ✨" -ForegroundColor Green
    }
    
} else {
    Write-Host "`n❌ Cleanup cancelled. No files were deleted." -ForegroundColor Yellow
}

Write-Host "`n🎉 Cleanup process completed!" -ForegroundColor Green
