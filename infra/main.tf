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

# Hub Network Resource Group
resource "azurerm_resource_group" "hub_network_rg" {
  name     = "rg-${var.prefix}-hub-${var.location_code}${random_string.main.result}"
  location = var.location
  tags = merge(var.tags, {
    environment = "shared"
    purpose     = "hub"
    component   = "network"
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

# Hub Network Service Principal Permissions
resource "azurerm_role_assignment" "sp_hub_network_contributor" {
  scope                = azurerm_resource_group.hub_network_rg.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.hub_network_rg]
}

resource "azurerm_role_assignment" "sp_hub_network_user_access_admin" {
  scope                = azurerm_resource_group.hub_network_rg.id
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.hub_network_rg]
}

resource "azurerm_role_assignment" "sp_hub_network_network_contributor" {
  scope                = azurerm_resource_group.hub_network_rg.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.hub_network_rg]
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
  enable_auto_purge        = true
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
  
  # Network configuration
  vnet_address_space       = "10.1.0.0/16"
  subnet_address_prefix    = "10.1.1.0/24"
  workload_vnet_location   = var.location
  workload_vnet_location_code = var.location_code
  resource_group_name_dns  = azurerm_resource_group.dev_vnet_rg.name
  user_object_id          = data.azurerm_client_config.current.object_id
  
  # Pass compute cluster identity from VNet module
  compute_cluster_identity_id    = module.dev_vnet.cc_identity_id
  compute_cluster_principal_id   = module.dev_vnet.cc_identity_principal_id
  
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
  
  # Pass compute cluster identity from VNet module
  compute_cluster_identity_id    = module.dev_vnet.cc_identity_id
  compute_cluster_principal_id   = module.dev_vnet.cc_identity_principal_id
  
  # Additional required variables
  user_object_id               = var.user_object_id
  workload_vnet_location       = var.location
  workload_vnet_location_code  = var.location_code
  resource_group_name_dns      = module.dev_vnet.resource_group_name_dns
  subnet_id                    = module.dev_vnet.subnet_id
  sub_id                       = var.subscription_id
  log_analytics_workspace_id   = module.dev_vnet.log_analytics_workspace_id
  workspace_principal_id       = module.dev_managed_umi.workspace_principal_id
  
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
  enable_auto_purge        = true
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
  
  # Network configuration
  vnet_address_space       = "10.2.0.0/16"
  subnet_address_prefix    = "10.2.1.0/24"
  workload_vnet_location   = var.location
  workload_vnet_location_code = var.location_code
  resource_group_name_dns  = azurerm_resource_group.prod_vnet_rg.name
  user_object_id          = data.azurerm_client_config.current.object_id
  
  # Pass compute cluster identity from VNet module
  compute_cluster_identity_id    = module.prod_vnet.cc_identity_id
  compute_cluster_principal_id   = module.prod_vnet.cc_identity_principal_id
  
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
  
  # Pass compute cluster identity from VNet module
  compute_cluster_identity_id    = module.prod_vnet.cc_identity_id
  compute_cluster_principal_id   = module.prod_vnet.cc_identity_principal_id
  
  # Additional required variables
  user_object_id               = var.user_object_id
  workload_vnet_location       = var.location
  workload_vnet_location_code  = var.location_code
  resource_group_name_dns      = module.prod_vnet.resource_group_name_dns
  subnet_id                    = module.prod_vnet.subnet_id
  sub_id                       = var.subscription_id
  log_analytics_workspace_id   = module.prod_vnet.log_analytics_workspace_id
  workspace_principal_id       = module.prod_managed_umi.workspace_principal_id
  
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

# Dev compute to dev registry (local environment access)
resource "azurerm_role_assignment" "dev_compute_to_dev_registry" {
  scope                = module.dev_registry.registry_id
  role_definition_name = "AzureML Registry User"
  principal_id         = module.dev_managed_umi.compute_uami_principal_id

  depends_on = [
    module.dev_registry,
    module.dev_managed_umi
  ]
}

# Prod compute to prod registry (local environment access)
resource "azurerm_role_assignment" "prod_compute_to_prod_registry" {
  scope                = module.prod_registry.registry_id
  role_definition_name = "AzureML Registry User"
  principal_id         = module.prod_managed_umi.compute_uami_principal_id

  depends_on = [
    module.prod_registry,
    module.prod_managed_umi
  ]
}

# Network connection approver roles for workspaces to create outbound rules
# Allow dev workspace to create private endpoints to dev registry (local environment)
resource "azurerm_role_assignment" "dev_workspace_network_connection_approver" {
  scope                = module.dev_registry.registry_id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = module.dev_managed_umi.workspace_uami_principal_id

  depends_on = [
    module.dev_registry,
    module.dev_managed_umi
  ]
}

# Allow prod workspace to create private endpoints to prod registry (local environment)
resource "azurerm_role_assignment" "prod_workspace_to_prod_registry_network_approver" {
  scope                = module.prod_registry.registry_id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = module.prod_managed_umi.workspace_uami_principal_id

  depends_on = [
    module.prod_registry,
    module.prod_managed_umi
  ]
}

# Allow prod workspace to create private endpoints to dev registry (cross-environment)
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

# Create outbound rule for dev workspace to access dev registry (local environment)
resource "azapi_resource" "dev_workspace_to_dev_registry_outbound_rule" {
  type      = "Microsoft.MachineLearningServices/workspaces/outboundRules@2024-10-01-preview"
  name      = "AllowDevRegistryAccess"
  parent_id = module.dev_managed_umi.workspace_id

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
    module.dev_managed_umi,
    module.dev_registry,
    azurerm_role_assignment.dev_workspace_network_connection_approver
  ]
}

# Create outbound rule for prod workspace to access prod registry (local environment)
resource "azapi_resource" "prod_workspace_to_prod_registry_outbound_rule" {
  type      = "Microsoft.MachineLearningServices/workspaces/outboundRules@2024-10-01-preview"
  name      = "AllowProdRegistryAccess"
  parent_id = module.prod_managed_umi.workspace_id

  body = {
    properties = {
      type = "PrivateEndpoint"
      destination = {
        serviceResourceId = module.prod_registry.registry_id
      }
      category = "UserDefined"
    }
  }

  depends_on = [
    module.prod_managed_umi,
    module.prod_registry,
    azurerm_role_assignment.prod_workspace_to_prod_registry_network_approver
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

# ===============================
# STEP 7: USER ROLE ASSIGNMENTS
# ===============================

# Development Environment - Human User Role Assignments
resource "azurerm_role_assignment" "user_dev_rg_reader" {
  count                = var.assign_user_roles ? 1 : 0
  scope                = azurerm_resource_group.dev_workspace_rg.id
  role_definition_name = "Reader"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [
    azurerm_resource_group.dev_workspace_rg
  ]
}

resource "azurerm_role_assignment" "user_dev_workspace_data_scientist" {
  count                = var.assign_user_roles ? 1 : 0
  scope                = module.dev_managed_umi.workspace_id
  role_definition_name = "AzureML Data Scientist"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [
    module.dev_managed_umi
  ]
}

resource "azurerm_role_assignment" "user_dev_workspace_ai_developer" {
  count                = var.assign_user_roles ? 1 : 0
  scope                = module.dev_managed_umi.workspace_id
  role_definition_name = "Azure AI Developer"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [
    module.dev_managed_umi
  ]
}

resource "azurerm_role_assignment" "user_dev_workspace_compute_operator" {
  count                = var.assign_user_roles ? 1 : 0
  scope                = module.dev_managed_umi.workspace_id
  role_definition_name = "AzureML Compute Operator"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [
    module.dev_managed_umi
  ]
}

resource "azurerm_role_assignment" "user_dev_storage_blob_contributor" {
  count                = var.assign_user_roles ? 1 : 0
  scope                = module.dev_managed_umi.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [
    module.dev_managed_umi
  ]
}

resource "azurerm_role_assignment" "user_dev_storage_file_privileged_contributor" {
  count                = var.assign_user_roles ? 1 : 0
  scope                = module.dev_managed_umi.storage_account_id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [
    module.dev_managed_umi
  ]
}

resource "azurerm_role_assignment" "user_dev_registry_user" {
  count                = var.assign_user_roles ? 1 : 0
  scope                = module.dev_registry.registry_id
  role_definition_name = "AzureML Registry User"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [
    module.dev_registry
  ]
}

# Production Environment - Human User Role Assignments
resource "azurerm_role_assignment" "user_prod_rg_reader" {
  count                = var.assign_user_roles ? 1 : 0
  scope                = azurerm_resource_group.prod_workspace_rg.id
  role_definition_name = "Reader"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [
    azurerm_resource_group.prod_workspace_rg
  ]
}

resource "azurerm_role_assignment" "user_prod_workspace_data_scientist" {
  count                = var.assign_user_roles ? 1 : 0
  scope                = module.prod_managed_umi.workspace_id
  role_definition_name = "AzureML Data Scientist"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [
    module.prod_managed_umi
  ]
}

resource "azurerm_role_assignment" "user_prod_workspace_ai_developer" {
  count                = var.assign_user_roles ? 1 : 0
  scope                = module.prod_managed_umi.workspace_id
  role_definition_name = "Azure AI Developer"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [
    module.prod_managed_umi
  ]
}

resource "azurerm_role_assignment" "user_prod_workspace_compute_operator" {
  count                = var.assign_user_roles ? 1 : 0
  scope                = module.prod_managed_umi.workspace_id
  role_definition_name = "AzureML Compute Operator"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [
    module.prod_managed_umi
  ]
}

resource "azurerm_role_assignment" "user_prod_storage_blob_contributor" {
  count                = var.assign_user_roles ? 1 : 0
  scope                = module.prod_managed_umi.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [
    module.prod_managed_umi
  ]
}

resource "azurerm_role_assignment" "user_prod_storage_file_privileged_contributor" {
  count                = var.assign_user_roles ? 1 : 0
  scope                = module.prod_managed_umi.storage_account_id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [
    module.prod_managed_umi
  ]
}

resource "azurerm_role_assignment" "user_prod_registry_user" {
  count                = var.assign_user_roles ? 1 : 0
  scope                = module.prod_registry.registry_id
  role_definition_name = "AzureML Registry User"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [
    module.prod_registry
  ]
}

# ===============================
# STEP 8: HUB-AND-SPOKE NETWORK
# ===============================

# Hub Network Module
module "hub_network" {
  source = "./modules/hub-network"
  
  prefix                         = var.prefix
  location                       = var.location
  location_code                  = var.location_code
  random_string                  = random_string.main.result
  resource_group_name            = azurerm_resource_group.hub_network_rg.name
  
  hub_vnet_address_space         = "10.0.0.0/16"
  gateway_subnet_address_prefix  = "10.0.1.0/24"
  vpn_client_address_space       = "172.16.0.0/24"
  vpn_root_certificate_data      = var.vpn_root_certificate_data
  vpn_gateway_sku                = "VpnGw2"
  
  # VNet peering configuration
  dev_vnet_id                    = module.dev_vnet.vnet_id
  prod_vnet_id                   = module.prod_vnet.vnet_id
  dev_vnet_name                  = module.dev_vnet.vnet_name
  prod_vnet_name                 = module.prod_vnet.vnet_name
  dev_vnet_resource_group        = azurerm_resource_group.dev_vnet_rg.name
  prod_vnet_resource_group       = azurerm_resource_group.prod_vnet_rg.name
  
  tags = merge(var.tags, {
    environment = "shared"
    purpose     = "hub"
  })
  
  depends_on = [
    azurerm_role_assignment.sp_hub_network_contributor,
    azurerm_role_assignment.sp_hub_network_user_access_admin,
    azurerm_role_assignment.sp_hub_network_network_contributor,
    module.dev_vnet,
    module.prod_vnet
  ]
}

# Dev Spoke to Hub Peering
module "dev_spoke_peering" {
  source = "./modules/spoke-peering"
  
  spoke_vnet_name              = module.dev_vnet.vnet_name
  spoke_resource_group_name    = azurerm_resource_group.dev_vnet_rg.name
  hub_vnet_id                  = module.hub_network.hub_vnet_id
  peering_name                 = "peer-dev-to-hub"
  
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways         = true
  
  depends_on = [
    module.hub_network,
    module.dev_vnet
  ]
}

# Prod Spoke to Hub Peering
module "prod_spoke_peering" {
  source = "./modules/spoke-peering"
  
  spoke_vnet_name              = module.prod_vnet.vnet_name
  spoke_resource_group_name    = azurerm_resource_group.prod_vnet_rg.name
  hub_vnet_id                  = module.hub_network.hub_vnet_id
  peering_name                 = "peer-prod-to-hub"
  
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways         = true
  
  depends_on = [
    module.hub_network,
    module.prod_vnet
  ]
}
