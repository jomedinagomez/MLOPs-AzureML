# Clean VPN Certificate Script
# This script properly formats the VPN certificate for Terraform

Write-Host "Cleaning VPN certificate for Terraform..." -ForegroundColor Green

# Get the certificate
$cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq "CN=AzureMLHubVPNRootCert" } | Select-Object -First 1

if ($cert) {
    Write-Host "Certificate found with thumbprint: $($cert.Thumbprint)" -ForegroundColor Green
    
    # Export certificate as base64
    $certBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
    $certBase64 = [System.Convert]::ToBase64String($certBytes)
    
    # Remove any line breaks and clean the string
    $cleanCert = $certBase64 -replace '\s', ''
    
    Write-Host "Clean certificate length: $($cleanCert.Length) characters" -ForegroundColor Blue
    
    # Read current terraform.tfvars
    $tfvarsPath = "terraform.tfvars"
    if (Test-Path $tfvarsPath) {
        $tfvarsContent = Get-Content $tfvarsPath -Raw
        
        # Replace the certificate line with clean format
        $newLine = "vpn_root_certificate_data = `"$cleanCert`""
        $tfvarsContent = $tfvarsContent -replace 'vpn_root_certificate_data = .*', $newLine
        
        # Write back to file
        $tfvarsContent | Set-Content $tfvarsPath -NoNewline
        
        Write-Host "terraform.tfvars updated successfully!" -ForegroundColor Green
        Write-Host "Certificate validation should now pass." -ForegroundColor Green
    } else {
        Write-Host "ERROR: terraform.tfvars not found!" -ForegroundColor Red
    }
} else {
    Write-Host "ERROR: VPN root certificate not found!" -ForegroundColor Red
    Write-Host "Please run generate_clean_vpn_cert.ps1 first" -ForegroundColor Yellow
}
