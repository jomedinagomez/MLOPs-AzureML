# VPN Certificate Generation Script
# Run this PowerShell script to generate certificates for P2S VPN

# ======================================
# OPTION 1: PowerShell (Windows)
# ======================================

# Generate the root certificate
$rootCert = New-SelfSignedCertificate -Type Custom -KeySpec Signature `
-Subject "CN=P2S-Root-Cert-AML" -KeyExportPolicy Exportable `
-HashAlgorithm sha256 -KeyLength 2048 `
-CertStoreLocation "Cert:\CurrentUser\My" -KeyUsageProperty Sign -KeyUsage CertSign

Write-Host "Root certificate created with thumbprint: $($rootCert.Thumbprint)"

# Generate client certificate (signed by root)
$clientCert = New-SelfSignedCertificate -Type Custom -DnsName "P2S-Client-AML" -KeySpec Signature `
-Subject "CN=P2S-Client-AML" -KeyExportPolicy Exportable `
-HashAlgorithm sha256 -KeyLength 2048 `
-CertStoreLocation "Cert:\CurrentUser\My" `
-Signer $rootCert -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.2")

Write-Host "Client certificate created with thumbprint: $($clientCert.Thumbprint)"

# Get the base64 encoded root certificate data (without headers/footers)
$rootCertBase64 = [System.Convert]::ToBase64String($rootCert.RawData)

Write-Host ""
Write-Host "=== COPY THIS VALUE TO YOUR terraform.tfvars ==="
Write-Host "vpn_root_certificate_data = `"$rootCertBase64`""
Write-Host "================================================="
Write-Host ""

# Export client certificate for distribution
$clientCertPath = "$env:USERPROFILE\Desktop\P2S-Client-AML.pfx"
$clientPassword = ConvertTo-SecureString -String "Azure123!" -Force -AsPlainText
Export-PfxCertificate -Cert $clientCert -FilePath $clientCertPath -Password $clientPassword

Write-Host "Client certificate exported to: $clientCertPath"
Write-Host "Client certificate password: Azure123!"
Write-Host ""
Write-Host "=== INSTALLATION INSTRUCTIONS ==="
Write-Host "1. Add the base64 string above to your terraform.tfvars file"
Write-Host "2. Run terraform apply to deploy the VPN gateway"
Write-Host "3. Download the VPN client from Azure Portal > VPN Gateway > Point-to-site configuration"
Write-Host "4. Install the client certificate (.pfx file) on client machines"
Write-Host "5. Connect using the VPN client"

# ======================================
# OPTION 2: Linux/macOS Commands
# ======================================

Write-Host ""
Write-Host "=== ALTERNATIVE: Linux/macOS Commands ==="
Write-Host "# Generate private key"
Write-Host "openssl genrsa -out P2SRootCert.key 2048"
Write-Host ""
Write-Host "# Generate root certificate"
Write-Host "openssl req -new -x509 -key P2SRootCert.key -out P2SRootCert.crt -days 3650 -subj '/CN=P2S-Root-Cert-AML'"
Write-Host ""
Write-Host "# Get Base64 content (remove header/footer)"
Write-Host "openssl x509 -in P2SRootCert.crt -outform der | base64"
Write-Host ""
Write-Host "# Generate client private key"
Write-Host "openssl genrsa -out P2SClientCert.key 2048"
Write-Host ""
Write-Host "# Generate client certificate request"
Write-Host "openssl req -new -key P2SClientCert.key -out P2SClientCert.csr -subj '/CN=P2S-Client-AML'"
Write-Host ""
Write-Host "# Sign client certificate with root certificate"
Write-Host "openssl x509 -req -in P2SClientCert.csr -CA P2SRootCert.crt -CAkey P2SRootCert.key -CAcreateserial -out P2SClientCert.crt -days 365"
Write-Host ""
Write-Host "# Create PKCS#12 file for client"
Write-Host "openssl pkcs12 -export -out P2SClientCert.p12 -inkey P2SClientCert.key -in P2SClientCert.crt -certfile P2SRootCert.crt"
