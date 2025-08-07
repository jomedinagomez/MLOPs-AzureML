# Key Vault Module

This Terraform module creates an Azure Key Vault with enterprise-grade security configurations, RBAC authorization, private networking support, and comprehensive diagnostic settings.

## Features

- **Security**: RBAC-based authorization, network ACLs, soft delete protection
- **Networking**: Private endpoint support with firewall rules
- **Monitoring**: Complete diagnostic settings for audit events and metrics
- **Access Management**: Flexible access policies and administrator role assignment

## Resources Created

| Resource | Purpose |
|----------|---------|
| `azurerm_key_vault` | Main Key Vault with security configurations |
| `azurerm_role_assignment` | Key Vault Administrator role for specified admin |
| `azurerm_key_vault_access_policy` | Access policies for service principals/users |
| `azurerm_monitor_diagnostic_setting` | Comprehensive audit logging and metrics |

## Usage

```hcl
module "keyvault_aml" {
  source = "../modules/key-vault"
  
  # Basic Configuration
  naming_suffix       = var.naming_suffix
  location            = var.location
  location_code       = var.location_code
  resource_group_name = azurerm_resource_group.rgwork.name
  purpose             = var.purpose
  
  # Monitoring
  law_resource_id = var.log_analytics_workspace_id
  
  # Access Management
  kv_admin_object_id = var.user_object_id
  
  # Network Security
  firewall_default_action = "Deny"
  firewall_bypass         = "AzureServices"
  
  # Auto-purge for dev/test environments (NEVER use in production)
  enable_auto_purge = var.purpose == "dev" ? true : false
  
  # Tags
  tags = var.tags
}
```

## Diagnostic Settings

The module automatically configures comprehensive diagnostic settings that capture:

### Log Categories
- **AuditEvent**: All access to secrets, keys, and certificates
- **AzurePolicyEvaluationDetails**: Policy compliance monitoring

### Metrics
- **AllMetrics**: Performance and usage monitoring

These settings ensure full observability and compliance with security monitoring requirements.

## Network Security

### Firewall Configuration
- **Default Action**: Configurable (Allow/Deny)
- **Bypass**: Azure services can bypass firewall
- **IP Rules**: Support for allowed IP ranges
- **Private Endpoints**: Full support for private connectivity

### Best Practices
- Use `firewall_default_action = "Deny"` for production
- Configure private endpoints for secure access
- Whitelist only necessary IP ranges

## Access Management

### RBAC Authorization
- **Enabled by default**: Uses Azure RBAC instead of access policies
- **Key Vault Administrator**: Automatically assigned to specified admin
- **Flexible Policies**: Support for additional access policies if needed

### Access Policy Structure
```hcl
access_policies = [
  {
    object_id               = "user-or-service-principal-id"
    key_permissions         = ["Get", "List", "Create"]
    secret_permissions      = ["Get", "List", "Set"]
    certificate_permissions = ["Get", "List", "Import"]
  }
]
```

## Soft Delete & Purge Protection

### Configuration
- **Soft Delete**: Enabled with configurable retention period (default 90 days)
- **Purge Protection**: Configurable (recommended for production)

### ⚠️ Important: Soft Delete Behavior

When a Key Vault is deleted, it enters a "soft-deleted" state and **retains its name** for the retention period. This can cause deployment conflicts.

## 🔧 Troubleshooting

### Key Vault Name Conflicts

**Issue**: Getting `409 Conflict` errors during deployment:
```
Error: A resource with the ID ".../Microsoft.KeyVault/vaults/kvdevcc002/..." already exists
```

**Cause**: A Key Vault with the same name exists in soft-deleted state.

**Solutions**:

#### Option 1: Manual Purge (Quick Fix)
```bash
# 1. List soft-deleted Key Vaults
az keyvault list-deleted --query "[].{Name:name, Location:properties.location, DeletionDate:properties.deletionDate}" --output table

# 2. Purge specific Key Vault (replace with actual name and location)
az keyvault purge --name kvdevcc002 --location canadacentral

# 3. Verify purge completed
az keyvault list-deleted --query "[?name=='kvdevcc002']"
```

#### Option 2: Enable Auto-Purge (Recommended for Dev/Test)
Set `enable_auto_purge = true` in your Terraform configuration:

```hcl
module "keyvault_aml" {
  source = "../modules/key-vault"
  
  # ... other configuration
  
  # Enable auto-purge for dev/test environments
  enable_auto_purge = true
}
```

**How Auto-Purge Works**:
- When `enable_auto_purge = true`, a `null_resource` is created alongside the Key Vault
- During `terraform destroy`, it automatically runs `az keyvault purge` 
- This prevents soft-delete conflicts on subsequent deployments
- Uses `|| echo` fallback so destroy succeeds even if purge fails

### Clean Deployment Practices

For development/testing environments:
1. **Enable auto-purge**: Set `enable_auto_purge = true`
2. **Use unique naming** with timestamps if needed
3. **Document cleanup** procedures for your team
4. Consider **shorter retention periods** for development

### Production Considerations
- **NEVER enable auto-purge** for production environments
- Use **purge protection** for critical environments
- Implement **backup and recovery** procedures
- Monitor **access patterns** through diagnostic logs
- **Manual purge only** with proper approval process

## Variables

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `random_string` | string | - | Unique suffix for resource naming |
| `location` | string | - | Azure region for deployment |
| `location_code` | string | - | Short location code (e.g., "cc" for Canada Central) |
| `resource_group_name` | string | - | Resource group for Key Vault |
| `purpose` | string | - | Environment/purpose identifier |
| `law_resource_id` | string | - | Log Analytics workspace ID for diagnostics |
| `kv_admin_object_id` | string | - | Object ID for Key Vault Administrator role |
| `firewall_default_action` | string | `"Allow"` | Default firewall action |
| `firewall_bypass` | string | `"None"` | Services that can bypass firewall |
| `firewall_ip_rules` | list(string) | `[]` | Allowed IP ranges |
| `tags` | map(string) | `{}` | Resource tags |
| `enable_auto_purge` | bool | `false` | Enable automatic purging on destroy (dev/test only) |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Key Vault resource ID |
| `name` | Key Vault name |
| `vault_uri` | Key Vault URI |
| `tenant_id` | Tenant ID |

## Security Notes

1. **RBAC vs Access Policies**: This module uses RBAC by default for better security
2. **Network Isolation**: Configure firewall rules and private endpoints
3. **Audit Logging**: All access is logged via diagnostic settings
4. **Soft Delete**: Provides protection against accidental deletion
5. **Key Rotation**: Implement regular key rotation policies

---

**Version**: 1.0.0  
**Last Updated**: July 30, 2025  
**Author**: MLOps Team
