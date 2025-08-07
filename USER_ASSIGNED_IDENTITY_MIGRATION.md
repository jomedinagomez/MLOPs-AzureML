# USER-ASSIGNED MANAGED IDENTITY MIGRATION

## Summary
Successfully migrated Azure ML workspace from system-assigned managed identity to user-assigned managed identity only. This change improves security, manageability, and aligns with enterprise best practices.

## ✅ COMPLETED CHANGES

### 1. **Created User-Assigned Managed Identity Resource**
- **File**: `infra/aml-managed-smi/main.tf`
- **Resource**: `azurerm_user_assigned_identity.workspace_identity`
- **Name**: `"${var.purpose}-mi-workspace"`
- **Location**: Same as workspace resource group

### 2. **Updated Workspace Identity Configuration**
- **Changed From**: `type = "SystemAssigned"`
- **Changed To**: `type = "UserAssigned"` with explicit identity reference
- **Added Dependency**: Workspace now depends on the user-assigned identity
- **Removed**: `response_export_values` for system identity

### 3. **Updated All Role Assignments**
Migrated all role assignments from system-assigned to user-assigned identity:

#### **Resource Group Level Roles:**
- ✅ **Reader** - `azurerm_user_assigned_identity.workspace_identity.principal_id`
- ✅ **Azure AI Enterprise Network Connection Approver** - `azurerm_user_assigned_identity.workspace_identity.principal_id`
- ✅ **Azure AI Administrator** - `azurerm_user_assigned_identity.workspace_identity.principal_id`

#### **Storage Account Level Roles:**
- ✅ **Storage Blob Data Owner** - `azurerm_user_assigned_identity.workspace_identity.principal_id`

#### **Cross-Environment Roles:**
- ✅ **AzureML Registry User** (cross-env) - `azurerm_user_assigned_identity.workspace_identity.principal_id`

### 4. **Updated Outputs**
- **Modified**: `workspace_principal_id` now references user-assigned identity
- **Added**: `workspace_identity_id` output for resource ID reference
- **Updated Description**: Clarified it's user-assigned managed identity

### 5. **Updated Dependencies**
- **time_sleep**: Now depends on both workspace and user-assigned identity
- **Role Assignments**: All properly depend on the user-assigned identity

## 🔧 TECHNICAL DETAILS

### **Identity Architecture**
```
BEFORE: Workspace → System-Assigned Identity (automatically created)
AFTER:  Workspace → User-Assigned Identity (explicitly managed)
```

### **Resource Naming**
- **Identity Name**: `{purpose}-mi-workspace` (e.g., `dev-mi-workspace`, `prod-mi-workspace`)
- **Resource Group**: Same as workspace (`rg-aml-ws-{purpose}-{location_code}`)

### **Role Assignment Pattern**
All role assignments now use:
```terraform
principal_id = azurerm_user_assigned_identity.workspace_identity.principal_id
```

### **UUID Generation Pattern**
Names updated to use user-assigned identity principal ID:
```terraform
name = uuidv5("dns", "${resource_group}${azurerm_user_assigned_identity.workspace_identity.principal_id}{role_suffix}")
```

## 🚀 BENEFITS

### **Enhanced Security**
- **Predictable Identity**: User-assigned identity has consistent ID across deployments
- **Explicit Management**: Identity lifecycle is explicitly controlled
- **Cross-Subscription**: Can be shared across subscriptions if needed

### **Improved Operations**
- **Pre-Provisioning**: Identity can be created before workspace
- **Role Pre-Assignment**: Roles can be assigned before workspace creation
- **Disaster Recovery**: Identity persists independently of workspace

### **Better Governance**
- **Clear Ownership**: Explicit identity resource with tags and metadata
- **Audit Trail**: Separate resource for identity lifecycle tracking
- **Policy Compliance**: Can apply Azure Policy to managed identities separately

## 📋 VALIDATION CHECKLIST

### **Before Deployment**
- ✅ All role assignments updated to use user-assigned identity
- ✅ No references to `azapi_resource.aml_workspace.output.identity.principalId`
- ✅ Outputs updated to reference user-assigned identity
- ✅ Dependencies properly configured

### **After Deployment**
- [ ] Verify workspace uses user-assigned identity: `az ml workspace show --name {workspace-name} --resource-group {rg-name} --query identity`
- [ ] Confirm role assignments: `az role assignment list --assignee {user-assigned-identity-principal-id}`
- [ ] Test workspace functionality (compute creation, job submission)
- [ ] Validate cross-environment access (if configured)

## 🔄 DEPLOYMENT IMPACT

### **Infrastructure Changes**
- **New Resource**: User-assigned managed identity will be created
- **Modified Resource**: Workspace identity configuration changes
- **Role Assignments**: All workspace-related role assignments will be recreated

### **Potential Downtime**
- **Workspace Modification**: May require workspace restart
- **Role Propagation**: Role assignments may take time to propagate (typically 5-10 minutes)

### **Rollback Strategy**
If needed, can revert by:
1. Changing workspace identity back to `SystemAssigned`
2. Updating role assignments to use system identity
3. Removing user-assigned identity resource

## 📚 OPERATIONAL NOTES

### **Cross-Environment Configuration**
When setting up cross-environment RBAC, use the user-assigned identity principal ID:
```bash
# Get the identity principal ID for cross-environment configuration
az identity show --name {purpose}-mi-workspace --resource-group {rg-name} --query principalId -o tsv
```

### **Monitoring**
- **Identity Health**: Monitor user-assigned identity resource
- **Role Assignment Status**: Verify role assignments are active
- **Workspace Operations**: Ensure ML operations work correctly

### **Troubleshooting**
- **Permission Issues**: Check user-assigned identity has proper roles
- **Identity Not Found**: Verify identity exists and is in correct resource group
- **Role Propagation**: Allow 5-10 minutes for role changes to take effect

## 🎯 NEXT STEPS

1. **Test Deployment**: Deploy to dev environment first
2. **Validate Functionality**: Run basic ML operations to confirm everything works
3. **Update Documentation**: Ensure operational procedures reflect new identity model
4. **Deploy to Production**: Apply changes to production environment
5. **Monitor Operations**: Watch for any identity-related issues

This migration significantly improves the security and manageability of the Azure ML platform while maintaining all existing functionality.
