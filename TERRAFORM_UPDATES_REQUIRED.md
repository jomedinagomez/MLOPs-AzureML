# Terraform Updates Required for Deployment Strategy Implementation

## Overview

This document outlines all the required updates to the Terraform templates to align with the Azure ML deployment strategy. The analysis reveals several critical gaps between the current infrastructure and the strategy requirements.

## Executive Summary

**Current State**: The Terraform templates provide a solid foundation with modular architecture, managed identities, private networking, and basic RBAC.

**Critical Gaps Identified**:
1. ❌ **Resource naming mismatch**: Current `random_string = "004"` vs required `"01"`
2. ❌ **Missing cross-environment RBAC** for asset promotion workflows
3. ❌ **Missing Azure AI Administrator roles** for workspace UAMIs
4. ❌ **Missing Storage Blob Data Owner** assignments
5. ❌ **No cross-environment outbound rules** for production → dev registry access
6. ❌ **Missing environment-specific configurations** for dual deployment
7. ❌ **Missing default compute cluster assignment** for image creation in workspaces

## 1. CRITICAL: Resource Naming Configuration

### Current Problem
```hcl
# terraform.tfvars (CURRENT - INCORRECT)
random_string = "004"  # ❌ Does not match deployment strategy
```

### Required Fix
```hcl
# terraform.tfvars (REQUIRED UPDATE)
random_string = "01"   # ✅ Matches deployment strategy specification
```

**Impact**: This affects ALL resource names across the infrastructure. Must be updated immediately to align with deployment strategy.

## 2. Environment-Specific Configuration Files

### Current Problem
Single `terraform.tfvars` file cannot support dual-environment deployment with different configurations.

### Required Solution
Create **two separate configuration files**:

#### `terraform.tfvars.dev`
```hcl
# Base prefix for all resources
prefix = "aml"

# Specific prefixes for each resource type (aligned with deployment strategy)
resource_prefixes = {
  vnet               = "vnet-aml"
  subnet             = "subnet-aml"
  workspace          = "amlws"       # ✅ Matches strategy
  registry           = "amlreg"      # ✅ Matches strategy
  storage            = "amlst"       # ✅ Matches strategy
  container_registry = "amlacr"      # ✅ Matches strategy
  key_vault          = "amlkv"       # ✅ Matches strategy
  log_analytics      = "amllog"      # ✅ Matches strategy
}

# Environment Configuration
purpose       = "dev"
location      = "canadacentral"
location_code = "cc"
random_string = "01"                # ✅ CRITICAL: Fixed from "004"

# Development Network Configuration
vnet_address_space    = "10.1.0.0/16"    # ✅ Dev CIDR
subnet_address_prefix = "10.1.1.0/24"    # ✅ Dev subnet

# Resource Tagging
tags = {
  environment  = "dev"
  project      = "ml-platform"
  created_by   = "terraform"
  owner        = "ml-team"
  purpose      = "development"
}

# Key Vault Configuration
enable_auto_purge = true              # ✅ SAFE for dev environment
```

#### `terraform.tfvars.prod`
```hcl
# Base prefix for all resources
prefix = "aml"

# Specific prefixes for each resource type (same as dev)
resource_prefixes = {
  vnet               = "vnet-aml"
  subnet             = "subnet-aml"
  workspace          = "amlws"
  registry           = "amlreg"
  storage            = "amlst"
  container_registry = "amlacr"
  key_vault          = "amlkv"
  log_analytics      = "amllog"
}

# Environment Configuration
purpose       = "prod"
location      = "canadacentral"
location_code = "cc"
random_string = "01"                  # ✅ Same as dev per strategy

# Production Network Configuration (DIFFERENT CIDR)
vnet_address_space    = "10.2.0.0/16"    # ✅ Prod CIDR - isolated
subnet_address_prefix = "10.2.1.0/24"    # ✅ Prod subnet - isolated

# Resource Tagging
tags = {
  environment  = "production"
  project      = "ml-platform"
  created_by   = "terraform"
  owner        = "ml-team"
  purpose      = "production"
}

# Key Vault Configuration - CRITICAL SECURITY
enable_auto_purge = false             # ✅ MANDATORY for production
```

## 3. Missing Cross-Environment RBAC for Asset Promotion

### Current Problem
The deployment strategy requires production compute and workspace to access dev registry for asset promotion, but this RBAC is completely missing.

### Required Addition to `main.tf`

```hcl
# ============================================================================
# CROSS-ENVIRONMENT RBAC FOR ASSET PROMOTION
# ============================================================================

# Data source to get dev environment state (for production deployment only)
data "terraform_remote_state" "dev" {
  count = var.purpose == "prod" ? 1 : 0
  
  backend = "local"  # Update this to match your backend configuration
  config = {
    path = "../dev/terraform.tfstate"  # Adjust path as needed
  }
}

# Production compute cluster needs read access to dev registry for promoted assets
resource "azurerm_role_assignment" "prod_compute_to_dev_registry" {
  count = var.purpose == "prod" ? 1 : 0
  
  scope                = data.terraform_remote_state.dev[0].outputs.registry_id
  role_definition_name = "AzureML Registry User"
  principal_id         = module.aml_vnet.cc_identity_principal_id
  description          = "Allows prod compute to access promoted assets from dev registry"

  depends_on = [module.aml_vnet]
}

# Production workspace needs connection approver for automatic private endpoint creation
resource "azurerm_role_assignment" "prod_workspace_to_dev_registry_approver" {
  count = var.purpose == "prod" ? 1 : 0
  
  scope                = data.terraform_remote_state.dev[0].outputs.registry_id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = module.aml_workspace.workspace_principal_id
  description          = "Allows prod workspace to create private endpoints to dev registry"

  depends_on = [module.aml_workspace]
}
```

## 4. Missing Cross-Environment Outbound Rules

### Current Problem
Production workspace has no network connectivity to dev registry for asset promotion.

### Required Addition to `main.tf`

```hcl
# ============================================================================
# CROSS-ENVIRONMENT NETWORK CONNECTIVITY
# ============================================================================

# Production workspace outbound rule to dev registry (for asset promotion)
resource "azapi_resource" "prod_workspace_to_dev_registry_outbound" {
  count = var.purpose == "prod" ? 1 : 0
  
  type      = "Microsoft.MachineLearningServices/workspaces/outboundRules@2024-10-01-preview"
  name      = "allow-dev-registry-${var.purpose}"
  parent_id = module.aml_workspace.workspace_id

  body = {
    properties = {
      type = "PrivateEndpoint"              # Automatically creates private endpoint
      destination = {
        serviceResourceId = data.terraform_remote_state.dev[0].outputs.registry_id
        subresourceTarget = "amlregistry"
      }
      category = "UserDefined"
    }
  }

  depends_on = [module.aml_workspace, data.terraform_remote_state.dev]
}
```

## 5. Missing Azure AI Administrator Role

### Current Problem
Deployment strategy specifies workspace UAMIs need `Azure AI Administrator` role, but this is missing from the templates.

### Required Addition to `aml-managed-smi/main.tf`

```hcl
# ============================================================================
# AZURE AI ADMINISTRATOR ROLE FOR WORKSPACE UAMI (MISSING)
# ============================================================================

# Azure AI Administrator role for workspace UAMI
resource "azurerm_role_assignment" "workspace_ai_administrator" {
  scope                = azurerm_resource_group.rgwork.id
  role_definition_name = "Azure AI Administrator"
  principal_id         = azapi_resource.aml_workspace.identity[0].principal_id
  description          = "Allows workspace to configure AI services and workspace settings"

  depends_on = [azapi_resource.aml_workspace, azurerm_resource_group.rgwork]
}
```

## 6. Missing Default Compute Cluster Assignment for Image Creation

### Current Problem
Azure ML workspaces require a default compute cluster for image creation during environment builds and training job preparation. This assignment is missing from the workspace configuration.

### Required Addition to `aml-managed-smi/main.tf`

```hcl
# ============================================================================
# DEFAULT COMPUTE CLUSTER ASSIGNMENT FOR IMAGE CREATION (MISSING)
# ============================================================================

# Set default compute cluster for image creation in workspace
resource "azapi_update_resource" "workspace_default_compute" {
  type        = "Microsoft.MachineLearningServices/workspaces@2024-10-01"
  resource_id = azapi_resource.aml_workspace.id

  body = {
    properties = {
      imageConfigurations = {
        defaultCompute = azapi_resource.compute_cluster_uami.name  # References the cpu-cluster-uami
      }
    }
  }

  depends_on = [azapi_resource.aml_workspace, azapi_resource.compute_cluster_uami]
}
```

**Critical Note**: This configuration ensures that when environments are built or training jobs need custom images, they use the pre-configured compute cluster with proper managed identity and RBAC permissions.

## 7. Missing Storage Role Assignments

### Current Problem
Deployment strategy requires specific storage roles that are missing from current RBAC configuration.

### Required Addition to `aml-managed-smi/main.tf`

```hcl
# ============================================================================
# MISSING STORAGE ROLE ASSIGNMENTS
# ============================================================================

# Storage Blob Data Owner for workspace UAMI (MISSING)
resource "azurerm_role_assignment" "workspace_storage_owner" {
  scope                = module.storage_aml.storage_account_id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azapi_resource.aml_workspace.identity[0].principal_id
  description          = "Complete workspace storage management and permissions"

  depends_on = [azapi_resource.aml_workspace, module.storage_aml]
}

# Storage File Data Privileged Contributor for compute UAMI (MISSING)
resource "azurerm_role_assignment" "compute_storage_file_privileged" {
  scope                = module.storage_aml.storage_account_id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = var.compute_cluster_principal_id
  description          = "Share files between compute nodes"

  depends_on = [module.storage_aml]
}

# AcrPush role for compute UAMI (MISSING from strategy)
resource "azurerm_role_assignment" "compute_acr_push" {
  scope                = module.container_registry_aml.container_registry_id
  role_definition_name = "AcrPush"
  principal_id         = var.compute_cluster_principal_id
  description          = "Build and store custom training environments and inference images"

  depends_on = [module.container_registry_aml]
}
```

## 8. Missing Human User RBAC Variables

### Current Problem
Deployment strategy includes human user permissions, but there are no variables for user assignments.

### Required Addition to `variables.tf`

```hcl
# ============================================================================
# HUMAN USER RBAC VARIABLES (MISSING)
# ============================================================================

variable "data_scientists" {
  description = "List of user object IDs for data scientists (AzureML Data Scientist role)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for user_id in var.data_scientists : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", user_id))
    ])
    error_message = "All data scientist IDs must be valid UUIDs."
  }
}

variable "ml_engineers" {
  description = "List of user object IDs for ML engineers (Azure AI Developer role)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for user_id in var.ml_engineers : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", user_id))
    ])
    error_message = "All ML engineer IDs must be valid UUIDs."
  }
}

variable "admin_users" {
  description = "List of user object IDs for platform administrators"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for user_id in var.admin_users : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", user_id))
    ])
    error_message = "All admin user IDs must be valid UUIDs."
  }
}
```

### Required Addition to `aml-managed-smi/main.tf` for Human User RBAC

```hcl
# ============================================================================
# HUMAN USER RBAC ASSIGNMENTS (MISSING)
# ============================================================================

# Data Scientists - Workspace Level
resource "azurerm_role_assignment" "data_scientists_workspace" {
  for_each = toset(var.data_scientists)
  
  scope                = azapi_resource.aml_workspace.id
  role_definition_name = "AzureML Data Scientist"
  principal_id         = each.value
  description          = "Core ML development and model management access"

  depends_on = [azapi_resource.aml_workspace]
}

# Data Scientists - Storage Level
resource "azurerm_role_assignment" "data_scientists_storage" {
  for_each = toset(var.data_scientists)
  
  scope                = module.storage_aml.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
  description          = "Manage training data and experimental outputs"

  depends_on = [module.storage_aml]
}

# Data Scientists - Registry Level
resource "azurerm_role_assignment" "data_scientists_registry" {
  for_each = toset(var.data_scientists)
  
  scope                = azapi_resource.aml_registry.id
  role_definition_name = "AzureML Registry User"
  principal_id         = each.value
  description          = "Access organization-wide ML assets and promote models"

  depends_on = [azapi_resource.aml_registry]
}

# ML Engineers - Workspace Level
resource "azurerm_role_assignment" "ml_engineers_workspace" {
  for_each = toset(var.ml_engineers)
  
  scope                = azapi_resource.aml_workspace.id
  role_definition_name = "Azure AI Developer"
  principal_id         = each.value
  description          = "Develop generative AI solutions and prompt engineering"

  depends_on = [azapi_resource.aml_workspace]
}

# Resource Group Reader for all users
resource "azurerm_role_assignment" "users_resource_group_reader" {
  for_each = toset(concat(var.data_scientists, var.ml_engineers, var.admin_users))
  
  scope                = azurerm_resource_group.rgwork.id
  role_definition_name = "Reader"
  principal_id         = each.value
  description          = "Discover ML resources and monitor workspace infrastructure"

  depends_on = [azurerm_resource_group.rgwork]
}
```

## 9. Missing Environment Validation

### Current Problem
Terraform should validate environment-specific constraints to prevent configuration errors.

### Required Update to `variables.tf`

```hcl
# ============================================================================
# ENHANCED ENVIRONMENT VALIDATION (MISSING)
# ============================================================================

variable "purpose" {
  description = "Environment identifier (e.g., 'dev', 'prod', 'test')"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod", "test"], var.purpose)
    error_message = "Purpose must be one of: dev, prod, test."
  }

  validation {
    condition     = !(var.purpose == "prod" && var.enable_auto_purge == true)
    error_message = "SECURITY ERROR: Auto-purge MUST be disabled (false) for production environments."
  }
}

# Enhanced random_string validation
variable "random_string" {
  description = "Unique string for resource naming (must be '01' per deployment strategy)"
  type        = string
  default     = "01"

  validation {
    condition     = var.random_string == "01"
    error_message = "DEPLOYMENT STRATEGY REQUIREMENT: random_string must be '01' for both dev and prod environments."
  }

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.random_string))
    error_message = "Random string must be between 2-8 characters, lowercase letters and numbers only."
  }
}

# Network validation for environment isolation
variable "vnet_address_space" {
  description = "Address space for the VNet (dev: 10.1.0.0/16, prod: 10.2.0.0/16)"
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition     = can(cidrhost(var.vnet_address_space, 0))
    error_message = "VNet address space must be a valid CIDR block."
  }

  validation {
    condition = (
      (var.purpose == "dev" && var.vnet_address_space == "10.1.0.0/16") ||
      (var.purpose == "prod" && var.vnet_address_space == "10.2.0.0/16") ||
      (var.purpose == "test")
    )
    error_message = "NETWORK ISOLATION REQUIREMENT: Dev must use 10.1.0.0/16, Prod must use 10.2.0.0/16."
  }
}
```

## 10. Missing Registry-to-Registry Promotion Variables

### Current Problem
Two-registry architecture requires variables to specify external registries for cross-environment references.

### Required Addition to `variables.tf`

```hcl
# ============================================================================
# CROSS-ENVIRONMENT REGISTRY VARIABLES (MISSING)
# ============================================================================

variable "external_registry_id" {
  description = "External registry ID for cross-environment asset promotion (used by production)"
  type        = string
  default     = null
  
  validation {
    condition = (
      var.external_registry_id == null || 
      can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.MachineLearningServices/registries/[^/]+$", var.external_registry_id))
    )
    error_message = "External registry ID must be a valid Azure ML registry resource ID or null."
  }
}

variable "external_registry_name" {
  description = "External registry name for cross-environment references (used by production)"
  type        = string
  default     = null
  
  validation {
    condition = (
      var.external_registry_name == null || 
      can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]$", var.external_registry_name))
    )
    error_message = "External registry name must be a valid Azure ML registry name or null."
  }
}

variable "enable_cross_environment_access" {
  description = "Enable cross-environment access for asset promotion (production only)"
  type        = bool
  default     = false
  
  validation {
    condition = !(var.enable_cross_environment_access && var.purpose == "dev")
    error_message = "Cross-environment access should only be enabled for production environment."
  }
}
```

## 11. Missing Output Values for Cross-Environment References

### Current Problem
Production environment needs to reference dev registry outputs, but current outputs are incomplete.

### Required Addition to `outputs.tf`

```hcl
# ============================================================================
# CROSS-ENVIRONMENT OUTPUT VALUES (MISSING)
# ============================================================================

# Registry outputs for cross-environment references
output "registry_id" {
  value       = module.aml_registry.registry_id
  description = "Full resource ID of the Azure ML registry (used by other environments)"
}

output "registry_name" {
  value       = module.aml_registry.registry_name
  description = "Name of the Azure ML registry (used for cross-environment references)"
}

output "registry_login_server" {
  value       = module.aml_registry.registry_login_server
  description = "Login server URL of the registry's ACR (used for cross-environment access)"
}

# Workspace outputs for cross-environment references
output "workspace_id" {
  value       = module.aml_workspace.workspace_id
  description = "Full resource ID of the Azure ML workspace"
}

output "workspace_name" {
  value       = module.aml_workspace.workspace_name
  description = "Name of the Azure ML workspace"
}

# Network outputs for cross-environment connectivity
output "vnet_id" {
  value       = module.aml_vnet.vnet_id
  description = "Virtual network ID for cross-environment connectivity planning"
}

output "subnet_id" {
  value       = module.aml_vnet.subnet_id
  description = "Subnet ID for cross-environment private endpoint configuration"
}

# Environment metadata
output "environment_purpose" {
  value       = var.purpose
  description = "Environment purpose (dev/prod/test) for cross-environment validation"
}

output "environment_location" {
  value       = var.location
  description = "Environment location for cross-environment validation"
}
```

## 12. Implementation Priority and Sequence

### Phase 1: Critical Fixes (IMMEDIATE)
1. **Update `random_string = "01"`** in current terraform.tfvars
2. **Create separate dev/prod tfvars files**
3. **Add Azure AI Administrator role** to workspace UAMI
4. **Add default compute cluster assignment** for image creation
5. **Add environment validation** to prevent prod auto-purge

### Phase 2: Cross-Environment Setup (HIGH PRIORITY)
1. **Add cross-environment RBAC** for asset promotion
2. **Add cross-environment outbound rules** for network connectivity
3. **Add missing storage role assignments**
4. **Update outputs for cross-environment references**

### Phase 3: Enhanced Features (MEDIUM PRIORITY)
1. **Add human user RBAC variables and assignments**
2. **Add registry promotion variables**
3. **Enhanced validation rules**

### Phase 4: Deployment Validation (LOW PRIORITY)
1. **Test dev environment deployment**
2. **Test prod environment deployment**
3. **Validate cross-environment asset promotion**
4. **Verify all RBAC permissions**

## 13. Deployment Commands After Updates

### Development Environment
```bash
# Navigate to infrastructure directory
cd infra/

# Initialize Terraform (if needed)
terraform init

# Plan development deployment
terraform plan -var-file="terraform.tfvars.dev" -out="dev.tfplan"

# Apply development deployment
terraform apply "dev.tfplan"

# Get outputs for production reference
terraform output > ../outputs/dev-outputs.json
```

### Production Environment
```bash
# Plan production deployment (after dev is complete)
terraform plan -var-file="terraform.tfvars.prod" -out="prod.tfplan"

# Apply production deployment
terraform apply "prod.tfplan"

# Verify cross-environment connectivity
terraform output
```

### Validation Commands
```bash
# Verify dev registry is accessible from production
az ml registry show --name "amlregdevcc01" --resource-group "rg-aml-reg-dev-cc"

# Verify production outbound rule was created
az ml workspace outbound-rule list --name "amlwsprodcc01" --resource-group "rg-aml-ws-prod-cc"

# Test cross-environment asset access
az ml model list --registry-name "amlregdevcc01"
```

## 14. Security Considerations

### ✅ Security Validations Built Into Updates
- **Production auto-purge prevention**: Terraform validation prevents `enable_auto_purge = true` in prod
- **Network isolation**: Different CIDR ranges ensure no network connectivity between environments
- **Least privilege**: Cross-environment access is read-only and limited to specific assets
- **Resource group isolation**: All resources remain in separate resource groups per environment

### ⚠️ Security Recommendations
- **Monitor cross-environment access**: Implement logging for all cross-environment registry access
- **Regular RBAC audits**: Periodically review cross-environment permissions
- **Asset promotion governance**: Implement approval workflows for asset promotion
- **Network monitoring**: Monitor private endpoint usage for unexpected cross-environment traffic

## 15. Expected Resource Naming After Updates

After implementing these updates, resources will follow the deployment strategy naming:

### Development Environment
- **Resource Group VNet**: `rg-aml-vnet-dev-cc`
- **Resource Group Workspace**: `rg-aml-ws-dev-cc`
- **Resource Group Registry**: `rg-aml-reg-dev-cc`
- **Workspace**: `amlwsdevcc01`
- **Registry**: `amlregdevcc01`
- **Storage**: `amlstdevcc01`
- **VNet**: `vnet-amldevcc01`

### Production Environment
- **Resource Group VNet**: `rg-aml-vnet-prod-cc`
- **Resource Group Workspace**: `rg-aml-ws-prod-cc`
- **Resource Group Registry**: `rg-aml-reg-prod-cc`
- **Workspace**: `amlwsprodcc01`
- **Registry**: `amlregprodcc01`
- **Storage**: `amlstprodcc01`
- **VNet**: `vnet-amlprodcc01`

This alignment ensures consistency between the deployment strategy documentation and the actual Terraform implementation.
