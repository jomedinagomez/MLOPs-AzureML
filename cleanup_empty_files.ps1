# MLOps Azure ML - Empty Files and Folders Cleanup Script
# This script safely removes empty files and folders while preserving Git structure

param(
    [switch]$WhatIf = $false,
    [switch]$Verbose = $false
)

$rootPath = "C:\Users\jomedin\Documents\MLOPs-AzureML"

Write-Host "MLOps Azure ML - Empty Files and Folders Cleanup" -ForegroundColor Green
Write-Host "Root Path: $rootPath" -ForegroundColor Yellow

if ($WhatIf) {
    Write-Host "Running in WhatIf mode - no files will be deleted" -ForegroundColor Cyan
}

# Find and handle empty files
Write-Host "`nScanning for empty files..." -ForegroundColor Yellow
$emptyFiles = Get-ChildItem -Path $rootPath -Recurse -Force -File | Where-Object { 
    $_.Length -eq 0 -and 
    $_.FullName -notlike "*\.git\*" -and
    $_.Name -ne ".gitkeep" -and
    $_.Name -ne ".gitignore"
}

if ($emptyFiles.Count -gt 0) {
    Write-Host "Found $($emptyFiles.Count) empty files:" -ForegroundColor Red
    
    foreach ($file in $emptyFiles) {
        $relativePath = $file.FullName.Replace($rootPath, "").TrimStart('\')
        
        if ($Verbose -or $WhatIf) {
            Write-Host "  - $relativePath" -ForegroundColor Gray
        }
        
        if (-not $WhatIf) {
            try {
                Remove-Item $file.FullName -Force
                Write-Host "    Deleted: $relativePath" -ForegroundColor Green
            }
            catch {
                Write-Host "    Failed to delete: $relativePath - $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
} else {
    Write-Host "No empty files found." -ForegroundColor Green
}

# Find and handle empty directories (excluding Git directories)
Write-Host "`nScanning for empty directories..." -ForegroundColor Yellow
$emptyDirs = Get-ChildItem -Path $rootPath -Recurse -Force -Directory | Where-Object { 
    $_.FullName -notlike "*\.git\*" -and
    (Get-ChildItem $_.FullName -Force | Measure-Object).Count -eq 0 
}

if ($emptyDirs.Count -gt 0) {
    Write-Host "Found $($emptyDirs.Count) empty directories:" -ForegroundColor Red
    
    # Sort by depth (deepest first) to avoid issues with parent/child relationships
    $sortedDirs = $emptyDirs | Sort-Object { ($_.FullName -split '\\').Count } -Descending
    
    foreach ($dir in $sortedDirs) {
        $relativePath = $dir.FullName.Replace($rootPath, "").TrimStart('\')
        
        if ($Verbose -or $WhatIf) {
            Write-Host "  - $relativePath" -ForegroundColor Gray
        }
        
        if (-not $WhatIf) {
            try {
                Remove-Item $dir.FullName -Force -Recurse
                Write-Host "    Deleted: $relativePath" -ForegroundColor Green
            }
            catch {
                Write-Host "    Failed to delete: $relativePath - $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
} else {
    Write-Host "No empty directories found." -ForegroundColor Green
}

# Summary
Write-Host "`nCleanup Summary:" -ForegroundColor Yellow
if ($WhatIf) {
    Write-Host "  Would delete: $($emptyFiles.Count) files and $($emptyDirs.Count) directories" -ForegroundColor Cyan
    Write-Host "  Run without -WhatIf to perform actual deletion" -ForegroundColor Cyan
} else {
    Write-Host "  Processed: $($emptyFiles.Count) files and $($emptyDirs.Count) directories" -ForegroundColor Green
}

Write-Host "`nCleanup complete!" -ForegroundColor Green
