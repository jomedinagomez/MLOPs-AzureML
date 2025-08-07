# VPN Verification Script
# Run this after VPN Gateway deployment

Write-Host "Checking VPN Gateway deployment status..." -ForegroundColor Green

# Get VPN Gateway information
$vpnGateway = az network vnet-gateway list --query "[?contains(name, 'vpn')]" -o table

if ($vpnGateway) {
    Write-Host "VPN Gateway found:" -ForegroundColor Green
    Write-Host $vpnGateway
    
    # Get VPN client configuration
    Write-Host "`nGenerating VPN client configuration..." -ForegroundColor Blue
    $vpnClientConfig = az network vnet-gateway vpn-client generate --name "your-vpn-gateway-name" --resource-group "your-rg-name"
    
    if ($vpnClientConfig) {
        Write-Host "VPN client configuration generated successfully!" -ForegroundColor Green
        Write-Host "Download URL: $vpnClientConfig"
    }
} else {
    Write-Host "VPN Gateway not found. Please check deployment." -ForegroundColor Red
}

Write-Host "`nNext steps for users:"
Write-Host "1. Download VPN client from Azure Portal"
Write-Host "2. Install the client certificate (.pfx file)"
Write-Host "3. Connect using the VPN client"
Write-Host "4. Test connectivity to ML workspaces"
