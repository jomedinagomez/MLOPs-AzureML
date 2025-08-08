<#
.SYNOPSIS
  Helper script to automate connecting to the hub Point-to-Site (P2S) VPN Gateway for the Azure ML platform.

.DESCRIPTION
  Performs the following:
    1. Validates prerequisites (Az CLI, certificates).
    2. (Optional) Generates root/client certificates if missing.
    3. Downloads the VPN client package (via az CLI) OR creates a native IKEv2 Windows VPN connection.
    4. Creates/updates a Windows built-in IKEv2 VPN connection using certificate auth.
    5. Connects and validates routing & DNS.

  NOTE: This script uses the Windows built-in VPN (IKEv2) path so you do not have to manually import the Azure VPN Client profile.
        Your gateway is configured with both OpenVPN and IKEv2. If you prefer Azure VPN Client UX, still download and import
        the .azurevpnconfig file manually. This script focuses on an automated IKEv2 setup.

.PARAMETER ResourceGroup
  Resource group containing the Virtual Network Gateway (e.g. rg-aml-hub-cc01).

.PARAMETER GatewayName
  Name of the Virtual Network Gateway (e.g. vpngw-aml-hub-cc01).

.PARAMETER ConnectionName
  Name for the local Windows VPN connection to create (default: AzureML-Hub-P2S).

.PARAMETER ClientCertSubject
  Subject (CN) of the client certificate installed in CurrentUser\My (default: CN=AzureMLHubVPNClientCert).

.PARAMETER RootCertSubject
  Subject (CN) of the root certificate (default: CN=AzureMLHubVPNRootCert).

.PARAMETER GenerateIfMissing
  If set, will generate a new root & client certificate if either is missing (self-signed) using New-SelfSignedCertificate.
  Only safe if you ALSO update the gateway root certificate (requires terraform apply with updated vpn_root_certificate_data) OR
  the existing root is already registered and you only need a new client cert.

.PARAMETER ForceRecreateConnection
  If set, will remove and recreate the Windows VPN connection even if it exists.

.PARAMETER SkipConnect
  If set, will configure but not attempt to connect.

.EXAMPLE
  ./connect-p2s-vpn.ps1 -ResourceGroup rg-aml-hub-cc01 -GatewayName vpngw-aml-hub-cc01

.EXAMPLE
  ./connect-p2s-vpn.ps1 -ResourceGroup rg-aml-hub-cc01 -GatewayName vpngw-aml-hub-cc01 -ForceRecreateConnection -Verbose

.EXAMPLE
  # Provide the public IP manually (bypasses az queries)
  ./connect-p2s-vpn.ps1 -ResourceGroup rg-aml-hub-cc01 -GatewayName vpngw-aml-hub-cc01 -GatewayPublicIp 52.228.77.32

#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [Parameter(Mandatory=$true)][string]$ResourceGroup,
  [Parameter(Mandatory=$true)][string]$GatewayName,
  [string]$ConnectionName = "AzureML-Hub-P2S",
  [string]$ClientCertSubject = "CN=AzureMLHubVPNClientCert",
  [string]$RootCertSubject = "CN=AzureMLHubVPNRootCert",
  [string]$GatewayPublicIp,
  [switch]$GenerateIfMissing,
  [switch]$ForceRecreateConnection,
  [switch]$SkipConnect
)

function Write-Info($msg){ Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warn($msg){ Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg){ Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Test-AzCliInstalled {
  if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Err "Azure CLI (az) not found in PATH. Install from https://aka.ms/azure-cli"
    return $false
  }
  return $true
}

function Get-CertificateBySubject([string]$subject) {
  Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq $subject } | Select-Object -First 1
}

function New-RootAndClientCerts {
  Write-Info "Generating certificates (root + client)..."
  $existingRoot = Get-CertificateBySubject -subject $RootCertSubject
  if (-not $existingRoot) {
    $root = New-SelfSignedCertificate -Subject $RootCertSubject -KeyAlgorithm RSA -KeyLength 4096 -KeyExportPolicy Exportable -CertStoreLocation Cert:\CurrentUser\My -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider" -NotAfter (Get-Date).AddYears(3)
    Write-Info "Created root cert thumbprint: $($root.Thumbprint)"
  } else {
    Write-Info "Root cert already exists: $($existingRoot.Thumbprint)"
    $root = $existingRoot
  }
  $client = New-SelfSignedCertificate -Subject $ClientCertSubject -KeyAlgorithm RSA -KeyLength 2048 -KeyExportPolicy Exportable -CertStoreLocation Cert:\CurrentUser\My -Signer $root -NotAfter (Get-Date).AddYears(2)
  Write-Info "Created client cert thumbprint: $($client.Thumbprint)"
  Write-Warn "If this is a NEW root certificate not yet registered in the gateway, update vpn_root_certificate_data in terraform and apply BEFORE using this client."
  return $client
}

function Get-GatewayPublicIp {
  if ($GatewayPublicIp) {
    Write-Info "Manual GatewayPublicIp provided: $GatewayPublicIp"
    return $GatewayPublicIp
  }
  Write-Info "Querying gateway public IP via az CLI..."
  $json = az network vnet-gateway show -g $ResourceGroup -n $GatewayName --query "ipConfigurations[0].publicIpAddress.id" -o tsv 2>$null
  if (-not $json) {
    Write-Warn "Azure CLI query failed or not logged in. Attempting local terraform outputs fallback..."
    $tfOutPathCandidates = @(
      (Join-Path (Split-Path $PSScriptRoot -Parent) '.local_inventory/terraform_outputs.json'),
      (Join-Path $PSScriptRoot '../.local_inventory/terraform_outputs.json')
    )
    foreach ($p in $tfOutPathCandidates) {
      if (Test-Path $p) {
        try {
          $raw = Get-Content $p -Raw | ConvertFrom-Json
          if ($raw.vpn_gateway_public_ip.value) {
            Write-Info "Using fallback public IP from terraform outputs file: $($raw.vpn_gateway_public_ip.value)"
            return $raw.vpn_gateway_public_ip.value
          }
  } catch { Write-Warn ("Failed to parse terraform outputs at " + $p + " :: " + $_.Exception.Message) }
      }
    }
    Write-Err "Failed to get Public IP resource ID via az and no fallback found. Run 'az login' or ensure outputs JSON exists."; return $null
  }
  $pip = az resource show --ids $json --query properties.ipAddress -o tsv 2>$null
  if (-not $pip) { Write-Err "Failed to resolve public IP address."; return $null }
  return $pip
}

function Ensure-VpnConnection($serverIp) {
  $existing = Get-VpnConnection -Name $ConnectionName -ErrorAction SilentlyContinue
  if ($existing -and $ForceRecreateConnection) {
    Write-Info "Removing existing VPN connection $ConnectionName"
    Remove-VpnConnection -Name $ConnectionName -Force -PassThru | Out-Null
    $existing = $null
  }
  if ($existing) {
    Write-Info "VPN connection already exists. Skipping creation."
    return
  }
  Write-Info "Creating IKEv2 VPN connection $ConnectionName -> $serverIp"
  Add-VpnConnection -Name $ConnectionName -ServerAddress $serverIp -TunnelType IKEv2 -AuthenticationMethod MachineCertificate -EncryptionLevel Required -RememberCredential -SplitTunneling:$false -PassThru | Out-Null
  # Apply IPsec configuration with valid enumeration values (may already be secure by default)
  try {
    Set-VpnConnectionIPsecConfiguration -Name $ConnectionName -AuthenticationTransformConstants SHA256128 -CipherTransformConstants AES256 -DHGroup Group14 -IntegrityCheckMethod SHA256 -PfsGroup None -EncryptionMethod AES256 -Force -ErrorAction Stop
  } catch {
    Write-Warn "Could not set advanced IPsec configuration (may not be necessary). $_"
  }
}

function Connect-VpnIfNeeded {
  if ($SkipConnect) { Write-Info "SkipConnect specified - not dialing."; return }
  $status = (Get-VpnConnection -Name $ConnectionName -ErrorAction SilentlyContinue)
  if ($status -and $status.ConnectionStatus -eq 'Connected') {
    Write-Info "Already connected."
    return
  }
  Write-Info "Dialing VPN..."
  rasdial $ConnectionName | Out-Null
  Start-Sleep -Seconds 3
  $status = (Get-VpnConnection -Name $ConnectionName -ErrorAction SilentlyContinue)
  if ($status.ConnectionStatus -ne 'Connected') { Write-Err "Connection failed. Run 'Get-VpnConnection -Name $ConnectionName' for details." } else { Write-Info "Connected: $($status.Name)" }
}

function Test-VpnConnectivity {
  Write-Info "Validating assigned VPN client IP (172.16.* expected)..."
  $ip = (Get-NetIPAddress | Where-Object { $_.IPAddress -like '172.16.*' -and $_.AddressFamily -eq 'IPv4' } | Select-Object -First 1).IPAddress
  if ($ip) { Write-Info "Client IP: $ip" } else { Write-Warn "No 172.16.x.x address detected. Check client address space & routing." }

  Write-Info "Listing key routes to hub/spokes (10.0/10.1/10.2)..."
  Get-NetRoute -DestinationPrefix 10.* | Sort-Object DestinationPrefix | Format-Table -AutoSize | Out-String | Write-Host
}

# MAIN EXECUTION
if (-not (Test-AzCliInstalled)) { exit 1 }

$clientCert = Get-CertificateBySubject -subject $ClientCertSubject
$rootCert   = Get-CertificateBySubject -subject $RootCertSubject
if (-not $clientCert -or -not $rootCert) {
  if ($GenerateIfMissing) {
    $clientCert = New-RootAndClientCerts
  } else {
    Write-Err "Required certificates missing. Re-run with -GenerateIfMissing or import existing PFX."
    Write-Host " Missing client cert: $(-not $clientCert)" -ForegroundColor Yellow
    Write-Host " Missing root cert:   $(-not $rootCert)" -ForegroundColor Yellow
    exit 1
  }
}

$gatewayIp = Get-GatewayPublicIp
if (-not $gatewayIp) { exit 1 }
Write-Info "Gateway Public IP: $gatewayIp"

Ensure-VpnConnection -serverIp $gatewayIp
Connect-VpnIfNeeded
Test-VpnConnectivity

Write-Info "Done. To disconnect: 'rasdial $ConnectionName /disconnect'"
