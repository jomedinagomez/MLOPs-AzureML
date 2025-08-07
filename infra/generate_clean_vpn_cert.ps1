# Clean VPN Certificate Generation Script
# This version ensures proper base64 encoding without line breaks

Write-Host "Generating VPN certificates for Azure P2S connection..." -ForegroundColor Green

# Generate the root certificate
$rootCert = New-SelfSignedCertificate -Type Custom -KeySpec Signature `
    -Subject "CN=AzureMLHubVPNRootCert" -KeyExportPolicy Exportable `
    -HashAlgorithm sha256 -KeyLength 2048 `
    -CertStoreLocation "Cert:\CurrentUser\My" -KeyUsageProperty Sign -KeyUsage CertSign

Write-Host "Root certificate created with thumbprint: $($rootCert.Thumbprint)" -ForegroundColor Yellow

# Generate client certificate (signed by root)
$clientCert = New-SelfSignedCertificate -Type Custom -DnsName "AzureMLClient" -KeySpec Signature `
    -Subject "CN=AzureMLClient" -KeyExportPolicy Exportable `
    -HashAlgorithm sha256 -KeyLength 2048 `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -Signer $rootCert -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.2")

Write-Host "Client certificate created with thumbprint: $($clientCert.Thumbprint)" -ForegroundColor Yellow

# Get the base64 encoded root certificate data (clean, no line breaks)
$rootCertBase64 = [System.Convert]::ToBase64String($rootCert.RawData)

# Validate the base64 string
try {
    [System.Convert]::FromBase64String($rootCertBase64) | Out-Null
    Write-Host "Certificate validation: PASSED" -ForegroundColor Green
} catch {
    Write-Host "Certificate validation: FAILED" -ForegroundColor Red
    exit 1
}

# Update terraform.tfvars file
$tfvarsPath = "terraform.tfvars"
if (Test-Path $tfvarsPath) {
    Write-Host "Updating terraform.tfvars with VPN certificate..." -ForegroundColor Blue
    
    # Read current content
    $content = Get-Content $tfvarsPath -Raw
    
    # Replace the VPN certificate line
    $newContent = $content -replace 'vpn_root_certificate_data = ""', "vpn_root_certificate_data = `"$rootCertBase64`""
    
    # Write back to file
    Set-Content -Path $tfvarsPath -Value $newContent -NoNewline
    
    Write-Host "terraform.tfvars updated successfully!" -ForegroundColor Green
} else {
    Write-Host "terraform.tfvars not found. Manual update required:" -ForegroundColor Yellow
    Write-Host "vpn_root_certificate_data = `"$rootCertBase64`""
}

# Export client certificate for distribution
$clientCertPath = "$env:USERPROFILE\Desktop\AzureML-VPN-Client.pfx"
$clientPassword = ConvertTo-SecureString -String "AzureML123!" -Force -AsPlainText
Export-PfxCertificate -Cert $clientCert -FilePath $clientCertPath -Password $clientPassword

Write-Host "`n=== VPN CERTIFICATE SETUP COMPLETE ===" -ForegroundColor Green
Write-Host "Certificate thumbprint: $($rootCert.Thumbprint)"
Write-Host "Client certificate: $clientCertPath"
Write-Host "Client password: AzureML123!"
Write-Host "terraform.tfvars: Updated"
Write-Host "`nNext steps:"
Write-Host "1. Run 'terraform plan' to verify VPN configuration"
Write-Host "2. Run 'terraform apply' to deploy VPN Gateway"
Write-Host "3. Download VPN client from Azure Portal"
Write-Host "4. Install client certificate on user machines"
