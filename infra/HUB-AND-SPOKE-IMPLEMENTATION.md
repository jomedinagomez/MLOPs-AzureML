# Hub-and-Spoke Implementation Guide

## Overview
This implementation adds a hub-and-spoke network architecture to your existing Azure ML platform, providing unified VPN connectivity to both dev and prod environments.

## What's Been Added

### 1. New Modules Created
- **`modules/hub-network/`** - Hub VNet with VPN Gateway
- **`modules/spoke-peering/`** - Spoke-to-hub peering configuration

### 2. Main Infrastructure Changes
- **New Resource Group**: `rg-{prefix}-hub-{location_code}{random}`
- **Hub VNet**: `10.0.0.0/16` address space
- **VPN Gateway**: Point-to-Site connectivity
- **VNet Peering**: Hub connected to both dev and prod VNets

### 3. New Variables Added
- `vpn_root_certificate_data` - Base64 encoded root certificate

## Implementation Steps

### Step 1: Generate VPN Certificates
```powershell
# Run the certificate generation script
.\generate-vpn-certificates.ps1
```

This will:
- Create root and client certificates
- Display the Base64 string for terraform.tfvars
- Export client certificate for distribution

### Step 2: Update terraform.tfvars
Add the certificate data to your `terraform.tfvars`:

```hcl
# Add this line with the Base64 string from Step 1
vpn_root_certificate_data = "MIIC5j...your-base64-certificate-data"
```

### Step 3: Deploy the Infrastructure
```bash
# Initialize new modules
terraform init

# Plan the deployment
terraform plan

# Apply the changes
terraform apply
```

### Step 4: Configure VPN Client
After deployment:
1. Go to Azure Portal → VPN Gateway → Point-to-site configuration
2. Download the VPN client package
3. Install the client certificate (.pfx file) on your machine
4. Connect using the VPN client

## Network Architecture

```
Your Computer (VPN Client: 172.16.0.x)
│
├── VPN Connection to Hub (10.0.0.0/16)
│   ├── Gateway Subnet (10.0.1.0/24)
│   └── VPN Gateway (Public IP)
│
├── Dev Environment Access (10.1.0.0/16)
│   ├── Azure ML Workspace
│   ├── Registry
│   └── Storage/Key Vault/etc.
│
└── Prod Environment Access (10.2.0.0/16)
    ├── Azure ML Workspace
    ├── Registry
    └── Storage/Key Vault/etc.
```

## Cost Implications

### New Components
- **VPN Gateway (VpnGw2)**: ~$190/month
- **Public IP**: ~$4/month
- **VNet Peering**: No cost (same region)

### Savings
- **Eliminates jumpbox VMs**: Save ~$100-200/month per environment
- **Reduced management overhead**: No VM patching/maintenance

### Net Impact
- **Cost**: Slight increase (~$100/month)
- **Operational Efficiency**: Significant improvement
- **User Experience**: Much better (single connection)

## Benefits

### 🚀 **Improved Connectivity**
- Single VPN connection for both environments
- No need to switch between jumpboxes
- Direct access to all Azure ML resources

### 🔒 **Enhanced Security**
- Certificate-based authentication
- No public VMs to manage
- Maintained network isolation between environments

### 💰 **Cost Optimization**
- Eliminates need for separate jumpboxes
- Shared infrastructure across environments
- Reduced operational overhead

### 🛠️ **Operational Excellence**
- Simplified connection process
- Better user experience
- Easier to scale to additional environments

## Validation Steps

After deployment, verify:

1. **VPN Gateway Status**
   ```bash
   az network vnet-gateway show --name vpngw-{prefix}-hub-{location_code}{random} --resource-group rg-{prefix}-hub-{location_code}{random}
   ```

2. **VNet Peering Status**
   ```bash
   az network vnet peering list --vnet-name vnet-{prefix}-hub-{location_code}{random} --resource-group rg-{prefix}-hub-{location_code}{random}
   ```

3. **Connectivity Test**
   - Connect to VPN
   - Test access to dev workspace: `ping {dev-workspace-private-ip}`
   - Test access to prod workspace: `ping {prod-workspace-private-ip}`

## Troubleshooting

### Common Issues

1. **Certificate Problems**
   - Ensure certificate is properly Base64 encoded
   - Remove BEGIN/END markers from certificate data
   - Verify certificate hasn't expired

2. **Connectivity Issues**
   - Check VPN client is properly installed
   - Verify client certificate is installed in user certificate store
   - Check Azure VPN Gateway status

3. **DNS Resolution**
   - VPN clients use Azure DNS automatically
   - Private endpoints should resolve correctly
   - Test: `nslookup {workspace-name}.api.azureml.ms`

### Support Commands

```bash
# Check VPN Gateway logs
az network vnet-gateway list-bgp-peer-status --name vpngw-{prefix}-hub-{location_code}{random} --resource-group rg-{prefix}-hub-{location_code}{random}

# View VPN client configuration
az network vnet-gateway vpn-client generate --name vpngw-{prefix}-hub-{location_code}{random} --resource-group rg-{prefix}-hub-{location_code}{random}

# Check peering status
az network vnet peering list --vnet-name vnet-{prefix}-hub-{location_code}{random} --resource-group rg-{prefix}-hub-{location_code}{random} --query "[].{Name:name,Status:peeringState}"
```

## Next Steps

1. **Generate Certificates**: Run `generate-vpn-certificates.ps1`
2. **Update Variables**: Add certificate to `terraform.tfvars`
3. **Deploy**: Run `terraform apply`
4. **Test Connectivity**: Verify VPN access to both environments
5. **Distribute Client Certificates**: Share .pfx files with team members

This implementation provides a production-ready hub-and-spoke architecture that maintains all existing Azure ML functionality while significantly improving connectivity and user experience.
