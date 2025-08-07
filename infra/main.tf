# Single-Deployment Azure ML Platform
# Complete multi-environment Azure ML platform with proper dependency ordering
# Everything is handled by Terraform without external scripts

terraform {
  required_version = "~> 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.32.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Azure Resource Manager provider
provider "azurerm" {
  subscription_id = var.subscription_id
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

# Azure API provider for preview features
provider "azapi" {
  subscription_id = var.subscription_id
}

# Azure Active Directory provider
provider "azuread" {}

# Get current client configuration
data "azurerm_client_config" "current" {}

# Generate random string for resource naming
resource "random_string" "main" {
  length  = 4
  special = false
  upper   = false
  numeric = true
}

# ===============================
# LOCAL VALUES
# ===============================

locals {
  # Resource prefixes for consistent naming
  resource_prefixes = var.resource_prefixes
}

# ===============================
# STEP 1: SERVICE PRINCIPAL
# ===============================

# Create Azure AD Application for deployment service principal
resource "azuread_application" "deployment_sp_app" {
  display_name     = "sp-aml-deployment-platform"
  description      = "Service Principal for Azure ML platform deployment automation (all environments)"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azurerm_client_config.current.object_id]

  tags = [
    "ManagedBy:Terraform",
    "Purpose:MLOps-Deployment",
    "Scope:AllEnvironments"
  ]
}

# Create Service Principal from the application
resource "azuread_service_principal" "deployment_sp" {
  client_id                    = azuread_application.deployment_sp_app.client_id
  app_role_assignment_required = false
  owners                       = [data.azurerm_client_config.current.object_id]
  description                  = "Service Principal for Azure ML platform deployment via Terraform (all environments)"

  tags = [
    "ManagedBy:Terraform",
    "Purpose:MLOps-Deployment",
    "Scope:AllEnvironments"
  ]
}

# Create client secret for the service principal
resource "azuread_application_password" "deployment_sp_secret" {
  application_id = azuread_application.deployment_sp_app.id
  display_name   = "Terraform Deployment Secret - Platform"
}

# ===============================
# STEP 2: CREATE ALL RESOURCE GROUPS
# ===============================

# Development Environment Resource Groups
resource "azurerm_resource_group" "dev_vnet_rg" {
  name     = "rg-${var.prefix}-vnet-dev-${var.location_code}${random_string.main.result}"
  location = var.location
  tags = merge(var.tags, {
    environment = "development"
    purpose     = "dev"
    component   = "vnet"
  })
}

resource "azurerm_resource_group" "dev_workspace_rg" {
  name     = "rg-${var.prefix}-ws-dev-${var.location_code}${random_string.main.result}"
  location = var.location
  tags = merge(var.tags, {
    environment = "development"
    purpose     = "dev"
    component   = "workspace"
  })
}

resource "azurerm_resource_group" "dev_registry_rg" {
  name     = "rg-${var.prefix}-reg-dev-${var.location_code}${random_string.main.result}"
  location = var.location
  tags = merge(var.tags, {
    environment = "development"
    purpose     = "dev"
    component   = "registry"
  })
}

# Production Environment Resource Groups
resource "azurerm_resource_group" "prod_vnet_rg" {
  name     = "rg-${var.prefix}-vnet-prod-${var.location_code}${random_string.main.result}"
  location = var.location
  tags = merge(var.tags, {
    environment = "production"
    purpose     = "prod"
    component   = "vnet"
  })
}

resource "azurerm_resource_group" "prod_workspace_rg" {
  name     = "rg-${var.prefix}-ws-prod-${var.location_code}${random_string.main.result}"
  location = var.location
  tags = merge(var.tags, {
    environment = "production"
    purpose     = "prod"
    component   = "workspace"
  })
}

resource "azurerm_resource_group" "prod_registry_rg" {
  name     = "rg-${var.prefix}-reg-prod-${var.location_code}${random_string.main.result}"
  location = var.location
  tags = merge(var.tags, {
    environment = "production"
    purpose     = "prod"
    component   = "registry"
  })
}

# ===============================
# STEP 3: SERVICE PRINCIPAL RBAC
# ===============================

# Development Environment Service Principal Permissions
resource "azurerm_role_assignment" "sp_dev_vnet_contributor" {
  scope                = azurerm_resource_group.dev_vnet_rg.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.dev_vnet_rg]
}

resource "azurerm_role_assignment" "sp_dev_vnet_user_access_admin" {
  scope                = azurerm_resource_group.dev_vnet_rg.id
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.dev_vnet_rg]
}

resource "azurerm_role_assignment" "sp_dev_vnet_network_contributor" {
  scope                = azurerm_resource_group.dev_vnet_rg.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.dev_vnet_rg]
}

resource "azurerm_role_assignment" "sp_dev_workspace_contributor" {
  scope                = azurerm_resource_group.dev_workspace_rg.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.dev_workspace_rg]
}

resource "azurerm_role_assignment" "sp_dev_workspace_user_access_admin" {
  scope                = azurerm_resource_group.dev_workspace_rg.id
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.dev_workspace_rg]
}

resource "azurerm_role_assignment" "sp_dev_workspace_network_contributor" {
  scope                = azurerm_resource_group.dev_workspace_rg.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.dev_workspace_rg]
}

resource "azurerm_role_assignment" "sp_dev_registry_contributor" {
  scope                = azurerm_resource_group.dev_registry_rg.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.dev_registry_rg]
}

resource "azurerm_role_assignment" "sp_dev_registry_user_access_admin" {
  scope                = azurerm_resource_group.dev_registry_rg.id
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.dev_registry_rg]
}

resource "azurerm_role_assignment" "sp_dev_registry_network_contributor" {
  scope                = azurerm_resource_group.dev_registry_rg.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.dev_registry_rg]
}

# Production Environment Service Principal Permissions
resource "azurerm_role_assignment" "sp_prod_vnet_contributor" {
  scope                = azurerm_resource_group.prod_vnet_rg.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.prod_vnet_rg]
}

resource "azurerm_role_assignment" "sp_prod_vnet_user_access_admin" {
  scope                = azurerm_resource_group.prod_vnet_rg.id
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.prod_vnet_rg]
}

resource "azurerm_role_assignment" "sp_prod_vnet_network_contributor" {
  scope                = azurerm_resource_group.prod_vnet_rg.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.prod_vnet_rg]
}

resource "azurerm_role_assignment" "sp_prod_workspace_contributor" {
  scope                = azurerm_resource_group.prod_workspace_rg.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.prod_workspace_rg]
}

resource "azurerm_role_assignment" "sp_prod_workspace_user_access_admin" {
  scope                = azurerm_resource_group.prod_workspace_rg.id
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.prod_workspace_rg]
}

resource "azurerm_role_assignment" "sp_prod_workspace_network_contributor" {
  scope                = azurerm_resource_group.prod_workspace_rg.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.prod_workspace_rg]
}

resource "azurerm_role_assignment" "sp_prod_registry_contributor" {
  scope                = azurerm_resource_group.prod_registry_rg.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.prod_registry_rg]
}

resource "azurerm_role_assignment" "sp_prod_registry_user_access_admin" {
  scope                = azurerm_resource_group.prod_registry_rg.id
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.prod_registry_rg]
}

resource "azurerm_role_assignment" "sp_prod_registry_network_contributor" {
  scope                = azurerm_resource_group.prod_registry_rg.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.prod_registry_rg]
}

# ===============================
# STEP 4: DEVELOPMENT ENVIRONMENT
# ===============================

# Dev VNet Module (creates VNet resources)
module "dev_vnet" {
  source = "./modules/aml-vnet"
  
  prefix                    = var.prefix
  purpose                   = "dev"
  location                  = var.location
  location_code            = var.location_code
  random_string            = random_string.main.result
  resource_prefixes        = local.resource_prefixes
  vnet_address_space       = "10.1.0.0/16"
  subnet_address_prefix    = "10.1.1.0/24"
  tags                     = merge(var.tags, {
    environment = "development"
    purpose     = "dev"
  })
  
  depends_on = [
    azurerm_role_assignment.sp_dev_vnet_contributor,
    azurerm_role_assignment.sp_dev_vnet_user_access_admin,
    azurerm_role_assignment.sp_dev_vnet_network_contributor
  ]
}

# Dev Managed Identity Module
module "dev_managed_umi" {
  source = "./modules/aml-managed-umi"
  
  prefix                    = var.prefix
  purpose                   = "dev"
  location                  = var.location
  location_code            = var.location_code
  random_string            = random_string.main.result
  resource_prefixes        = local.resource_prefixes
  subnet_id                = module.dev_vnet.subnet_id
  log_analytics_workspace_id = module.dev_vnet.log_analytics_workspace_id
  enable_auto_purge        = true
  sub_id                   = var.subscription_id
  tags                     = merge(var.tags, {
    environment = "development"
    purpose     = "dev"
  })
  
  depends_on = [
    azurerm_role_assignment.sp_dev_workspace_contributor,
    azurerm_role_assignment.sp_dev_workspace_user_access_admin,
    azurerm_role_assignment.sp_dev_workspace_network_contributor,
    module.dev_vnet
  ]
}

# Dev Registry Module
module "dev_registry" {
  source = "./modules/aml-registry-smi"
  
  prefix                    = var.prefix
  purpose                   = "dev"
  location                  = var.location
  location_code            = var.location_code
  random_string            = random_string.main.result
  resource_prefixes        = local.resource_prefixes
  tags                     = merge(var.tags, {
    environment = "development"
    purpose     = "dev"
  })
  
  depends_on = [
    azurerm_role_assignment.sp_dev_registry_contributor,
    azurerm_role_assignment.sp_dev_registry_user_access_admin,
    azurerm_role_assignment.sp_dev_registry_network_contributor
  ]
}

# ===============================
# STEP 5: PRODUCTION ENVIRONMENT
# ===============================

# Prod VNet Module (creates VNet resources)
module "prod_vnet" {
  source = "./modules/aml-vnet"
  
  prefix                    = var.prefix
  purpose                   = "prod"
  location                  = var.location
  location_code            = var.location_code
  random_string            = random_string.main.result
  resource_prefixes        = local.resource_prefixes
  vnet_address_space       = "10.2.0.0/16"
  subnet_address_prefix    = "10.2.1.0/24"
  tags                     = merge(var.tags, {
    environment = "production"
    purpose     = "prod"
  })
  
  depends_on = [
    azurerm_role_assignment.sp_prod_vnet_contributor,
    azurerm_role_assignment.sp_prod_vnet_user_access_admin,
    azurerm_role_assignment.sp_prod_vnet_network_contributor
  ]
}

# Prod Managed Identity Module
module "prod_managed_umi" {
  source = "./modules/aml-managed-umi"
  
  prefix                    = var.prefix
  purpose                   = "prod"
  location                  = var.location
  location_code            = var.location_code
  random_string            = random_string.main.result
  resource_prefixes        = local.resource_prefixes
  subnet_id                = module.prod_vnet.subnet_id
  log_analytics_workspace_id = module.prod_vnet.log_analytics_workspace_id
  enable_auto_purge        = true
  sub_id                   = var.subscription_id
  
  # Cross-environment configuration for asset promotion
  enable_cross_env_rbac           = true
  cross_env_registry_resource_group = azurerm_resource_group.dev_registry_rg.name
  cross_env_registry_name         = module.dev_registry.registry_name
  
  tags                     = merge(var.tags, {
    environment = "production"
    purpose     = "prod"
  })
  
  depends_on = [
    azurerm_role_assignment.sp_prod_workspace_contributor,
    azurerm_role_assignment.sp_prod_workspace_user_access_admin,
    azurerm_role_assignment.sp_prod_workspace_network_contributor,
    module.prod_vnet,
    module.dev_registry
  ]
}

# Prod Registry Module
module "prod_registry" {
  source = "./modules/aml-registry-smi"
  
  prefix                    = var.prefix
  purpose                   = "prod"
  location                  = var.location
  location_code            = var.location_code
  random_string            = random_string.main.result
  resource_prefixes        = local.resource_prefixes
  tags                     = merge(var.tags, {
    environment = "production"
    purpose     = "prod"
  })
  
  depends_on = [
    azurerm_role_assignment.sp_prod_registry_contributor,
    azurerm_role_assignment.sp_prod_registry_user_access_admin,
    azurerm_role_assignment.sp_prod_registry_network_contributor
  ]
}

# ===============================
# STEP 6: CROSS-ENVIRONMENT CONNECTIVITY
# ===============================

# Allow production workspace to read from dev registry (AzureML Registry User role)
resource "azurerm_role_assignment" "prod_workspace_to_dev_registry" {
  scope                = module.dev_registry.registry_id
  role_definition_name = "AzureML Registry User"
  principal_id         = module.prod_managed_umi.workspace_uami_principal_id

  depends_on = [
    module.dev_registry,
    module.prod_managed_umi
  ]
}

# Allow production workspace to create private endpoints to dev registry
resource "azurerm_role_assignment" "prod_workspace_network_connection_approver" {
  scope                = module.dev_registry.registry_id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = module.prod_managed_umi.workspace_uami_principal_id

  depends_on = [
    module.dev_registry,
    module.prod_managed_umi
  ]
}

# Allow production compute to access dev registry for cross-environment model access
resource "azurerm_role_assignment" "prod_compute_to_dev_registry" {
  scope                = module.dev_registry.registry_id
  role_definition_name = "AzureML Registry User"
  principal_id         = module.prod_managed_umi.compute_uami_principal_id

  depends_on = [
    module.dev_registry,
    module.prod_managed_umi
  ]
}

# Create outbound rule for production workspace to access dev registry
resource "azapi_resource" "prod_workspace_to_dev_registry_outbound_rule" {
  type      = "Microsoft.MachineLearningServices/workspaces/outboundRules@2024-10-01-preview"
  name      = "AllowDevRegistryAccess"
  parent_id = module.prod_managed_umi.workspace_id

  body = {
    properties = {
      type = "PrivateEndpoint"
      destination = {
        serviceResourceId = module.dev_registry.registry_id
      }
      category = "UserDefined"
    }
  }

  depends_on = [
    module.prod_managed_umi,
    module.dev_registry,
    azurerm_role_assignment.prod_workspace_network_connection_approver
  ]
}
