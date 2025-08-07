# Environment Module - Deploys a complete ML environment
# This module creates all resources for a single environment (dev/prod)

terraform {
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
  }
}

# Data sources
data "azurerm_client_config" "current" {}

# Reference the existing service principal
data "azuread_service_principal" "deployment_sp" {
  display_name = "sp-aml-deployment-platform"
}

locals {
  # Naming conventions
  workspace_name  = "${var.resource_prefixes.workspace}${var.purpose}${var.location_code}${var.random_string}"
  registry_name   = "${var.resource_prefixes.registry}${var.purpose}${var.location_code}${var.random_string}"
  storage_name    = "${var.resource_prefixes.storage}${var.purpose}${var.location_code}${var.random_string}"
  acr_name        = "${var.resource_prefixes.container_registry}${var.purpose}${var.location_code}${var.random_string}"
  keyvault_name   = "${var.resource_prefixes.key_vault}${var.purpose}${var.location_code}${var.random_string}"
  vnet_name       = "${var.resource_prefixes.vnet}-${var.purpose}-${var.location_code}${var.random_string}"
  subnet_name     = "${var.resource_prefixes.subnet}-${var.purpose}-${var.location_code}${var.random_string}"
  
  # Resource group names  
  workspace_rg_name = "rg-aml-ws-${var.purpose}-${var.location_code}${var.random_string}"
  registry_rg_name  = "rg-aml-reg-${var.purpose}-${var.location_code}${var.random_string}"
  vnet_rg_name      = "rg-aml-vnet-${var.purpose}-${var.location_code}${var.random_string}"
}

# ===============================
# RESOURCE GROUPS
# ===============================

resource "azurerm_resource_group" "workspace_rg" {
  name     = local.workspace_rg_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_group" "registry_rg" {
  name     = local.registry_rg_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_group" "vnet_rg" {
  name     = local.vnet_rg_name
  location = var.location
  tags     = var.tags
}

# ===============================
# NETWORKING
# ===============================

resource "azurerm_virtual_network" "vnet" {
  name                = local.vnet_name
  address_space       = [var.vnet_address_space]
  location            = var.location
  resource_group_name = azurerm_resource_group.vnet_rg.name
  tags                = var.tags
}

resource "azurerm_subnet" "subnet" {
  name                 = local.subnet_name
  resource_group_name  = azurerm_resource_group.vnet_rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.subnet_address_prefix]
}

# ===============================
# LOG ANALYTICS
# ===============================

resource "azurerm_log_analytics_workspace" "workspace" {
  name                = "${var.resource_prefixes.log_analytics}${var.purpose}${var.location_code}${var.random_string}"
  location            = var.location
  resource_group_name = azurerm_resource_group.workspace_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# ===============================
# MANAGED IDENTITIES
# ===============================

resource "azurerm_user_assigned_identity" "endpoint_identity" {
  name                = "${var.purpose}-mi-endpoint"
  location            = var.location
  resource_group_name = azurerm_resource_group.workspace_rg.name
  tags                = var.tags
}

# ===============================
# STORAGE ACCOUNT
# ===============================

module "storage_account_default" {
  source = "../modules/storage-account"

  storage_account_name = local.storage_name
  resource_group_name  = azurerm_resource_group.workspace_rg.name
  location             = var.location
  tags                 = var.tags
  
  log_analytics_workspace_id = azurerm_log_analytics_workspace.workspace.id
}

# ===============================
# KEY VAULT
# ===============================

module "keyvault_aml" {
  source = "../modules/key-vault"

  keyvault_name                = local.keyvault_name
  resource_group_name          = azurerm_resource_group.workspace_rg.name
  location                     = var.location
  tenant_id                    = data.azurerm_client_config.current.tenant_id
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.workspace.id
  enable_rbac_authorization    = true
  enable_purge_protection      = !var.enable_auto_purge
  tags                         = var.tags

  # Grant current user admin access
  rbac_assignments = [
    {
      principal_id         = data.azurerm_client_config.current.object_id
      role_definition_name = "Key Vault Administrator"
    }
  ]
}

# ===============================
# CONTAINER REGISTRY
# ===============================

module "container_registry" {
  source = "../modules/container-registry"

  container_registry_name      = local.acr_name
  resource_group_name          = azurerm_resource_group.workspace_rg.name
  location                     = var.location
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.workspace.id
  tags                         = var.tags
}

# ===============================
# APPLICATION INSIGHTS
# ===============================

resource "azurerm_application_insights" "workspace" {
  name                = "appi-${var.purpose}-${var.location_code}${var.random_string}"
  location            = var.location
  resource_group_name = azurerm_resource_group.workspace_rg.name
  workspace_id        = azurerm_log_analytics_workspace.workspace.id
  application_type    = "web"
  tags                = var.tags
}

# ===============================
# AZURE ML WORKSPACE
# ===============================

resource "azurerm_machine_learning_workspace" "workspace" {
  name                          = local.workspace_name
  location                      = var.location
  resource_group_name           = azurerm_resource_group.workspace_rg.name
  storage_account_id            = module.storage_account_default.storage_account_id
  key_vault_id                  = module.keyvault_aml.key_vault_id
  container_registry_id         = module.container_registry.container_registry_id
  application_insights_id       = azurerm_application_insights.workspace.id
  
  public_network_access_enabled = false
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = var.tags
  
  depends_on = [
    module.storage_account_default,
    module.keyvault_aml,
    module.container_registry
  ]
}

# ===============================
# AZURE ML REGISTRY
# ===============================

resource "azurerm_machine_learning_registry" "registry" {
  name                          = local.registry_name
  location                      = var.location
  resource_group_name           = azurerm_resource_group.registry_rg.name
  public_network_access_enabled = false
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = var.tags
}

# ===============================
# PRIVATE ENDPOINTS
# ===============================

# Private endpoint for workspace
module "private_endpoint_aml_workspace" {
  source = "../modules/private-endpoint"

  private_endpoint_name   = "pe${local.workspace_name}amlworkspace"
  resource_group_name     = azurerm_resource_group.workspace_rg.name
  location                = var.location
  subnet_id               = azurerm_subnet.subnet.id
  private_connection_resource_id = azurerm_machine_learning_workspace.workspace.id
  subresource_names       = ["amlworkspace"]
  tags                    = var.tags
}

# Private endpoint for registry
module "private_endpoint_aml_registry" {
  source = "../modules/private-endpoint"

  private_endpoint_name   = "pe${local.registry_name}amlregistry"
  resource_group_name     = azurerm_resource_group.registry_rg.name
  location                = var.location
  subnet_id               = azurerm_subnet.subnet.id
  private_connection_resource_id = azurerm_machine_learning_registry.registry.id
  subresource_names       = ["amlregistry"]
  tags                    = var.tags
}

# Private endpoint for container registry
module "private_endpoint_container_registry" {
  source = "../modules/private-endpoint"

  private_endpoint_name   = "pe${local.acr_name}registry"
  resource_group_name     = azurerm_resource_group.workspace_rg.name
  location                = var.location
  subnet_id               = azurerm_subnet.subnet.id
  private_connection_resource_id = module.container_registry.container_registry_id
  subresource_names       = ["registry"]
  tags                    = var.tags
}

# Private endpoint for key vault
module "private_endpoint_kv" {
  source = "../modules/private-endpoint"

  private_endpoint_name   = "pe${local.keyvault_name}vault"
  resource_group_name     = azurerm_resource_group.workspace_rg.name
  location                = var.location
  subnet_id               = azurerm_subnet.subnet.id
  private_connection_resource_id = module.keyvault_aml.key_vault_id
  subresource_names       = ["vault"]
  tags                    = var.tags
}

# Private endpoints for storage account
module "private_endpoint_st_default_blob" {
  source = "../modules/private-endpoint"

  private_endpoint_name   = "pe${local.storage_name}blob"
  resource_group_name     = azurerm_resource_group.workspace_rg.name
  location                = var.location
  subnet_id               = azurerm_subnet.subnet.id
  private_connection_resource_id = module.storage_account_default.storage_account_id
  subresource_names       = ["blob"]
  tags                    = var.tags
}

module "private_endpoint_st_default_file" {
  source = "../modules/private-endpoint"

  private_endpoint_name   = "pe${local.storage_name}file"
  resource_group_name     = azurerm_resource_group.workspace_rg.name
  location                = var.location
  subnet_id               = azurerm_subnet.subnet.id
  private_connection_resource_id = module.storage_account_default.storage_account_id
  subresource_names       = ["file"]
  tags                    = var.tags
}

module "private_endpoint_st_default_queue" {
  source = "../modules/private-endpoint"

  private_endpoint_name   = "pe${local.storage_name}queue"
  resource_group_name     = azurerm_resource_group.workspace_rg.name
  location                = var.location
  subnet_id               = azurerm_subnet.subnet.id
  private_connection_resource_id = module.storage_account_default.storage_account_id
  subresource_names       = ["queue"]
  tags                    = var.tags
}

module "private_endpoint_st_default_table" {
  source = "../modules/private-endpoint"

  private_endpoint_name   = "pe${local.storage_name}table"
  resource_group_name     = azurerm_resource_group.workspace_rg.name
  location                = var.location
  subnet_id               = azurerm_subnet.subnet.id
  private_connection_resource_id = module.storage_account_default.storage_account_id
  subresource_names       = ["table"]
  tags                    = var.tags
}

# ===============================
# STORAGE NETWORK CONFIGURATION
# ===============================

# Update storage account network rules to allow workspace access
resource "azapi_update_resource" "workspace_storage_network_rules" {
  type        = "Microsoft.Storage/storageAccounts@2023-05-01"
  resource_id = module.storage_account_default.storage_account_id

  body = {
    properties = {
      allowSharedKeyAccess = true
      networkAcls = {
        bypass        = "AzureServices"
        defaultAction = "Deny"
        resourceAccessRules = [
          {
            resourceId = azurerm_machine_learning_workspace.workspace.id
            tenantId   = "*"
          },
          {
            resourceId = azurerm_machine_learning_registry.registry.id
            tenantId   = "*"
          }
        ]
      }
    }
  }

  depends_on = [
    azurerm_machine_learning_workspace.workspace,
    azurerm_machine_learning_registry.registry
  ]
}

# ===============================
# WORKSPACE OUTBOUND RULE FOR REGISTRY
# ===============================

resource "azapi_resource" "workspace_to_registry_outbound_rule" {
  type      = "Microsoft.MachineLearningServices/workspaces/outboundRules@2024-10-01-preview"
  name      = "allow-external-registry-${var.purpose}"
  parent_id = azurerm_machine_learning_workspace.workspace.id

  body = {
    properties = {
      type = "PrivateEndpoint"
      destination = {
        serviceResourceId = azurerm_machine_learning_registry.registry.id
        subresourceTarget = "amlregistry"
      }
      category = "UserDefined"
    }
  }

  depends_on = [
    azurerm_machine_learning_workspace.workspace,
    azurerm_machine_learning_registry.registry
  ]
}

# ===============================
# RBAC ASSIGNMENTS
# ===============================

# Service Principal access to resource groups
resource "azurerm_role_assignment" "sp_contributor_workspace_rg" {
  scope                = azurerm_resource_group.workspace_rg.id
  role_definition_name = "Contributor"
  principal_id         = data.azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to deploy ML workspace, storage accounts, and compute resources"
}

resource "azurerm_role_assignment" "sp_contributor_registry_rg" {
  scope                = azurerm_resource_group.registry_rg.id
  role_definition_name = "Contributor"
  principal_id         = data.azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to deploy ML registry and associated resources"
}

resource "azurerm_role_assignment" "sp_contributor_vnet_rg" {
  scope                = azurerm_resource_group.vnet_rg.id
  role_definition_name = "Contributor"
  principal_id         = data.azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to deploy ML networking infrastructure"
}

# Network Contributor for private endpoint management
resource "azurerm_role_assignment" "sp_network_contributor_workspace_rg" {
  scope                = azurerm_resource_group.workspace_rg.id
  role_definition_name = "Network Contributor"
  principal_id         = data.azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to configure secure networking for ML workspace isolation"
}

resource "azurerm_role_assignment" "sp_network_contributor_registry_rg" {
  scope                = azurerm_resource_group.registry_rg.id
  role_definition_name = "Network Contributor"
  principal_id         = data.azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to configure secure networking for ML registry isolation"
}

resource "azurerm_role_assignment" "sp_network_contributor_vnet_rg" {
  scope                = azurerm_resource_group.vnet_rg.id
  role_definition_name = "Network Contributor"
  principal_id         = data.azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to configure secure networking for ML workspace isolation"
}

# User Access Administrator for managed identity management
resource "azurerm_role_assignment" "sp_user_access_admin_workspace_rg" {
  scope                = azurerm_resource_group.workspace_rg.id
  role_definition_name = "User Access Administrator"
  principal_id         = data.azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to configure RBAC for managed identities and user access in Workspace RG"
}

resource "azurerm_role_assignment" "sp_user_access_admin_registry_rg" {
  scope                = azurerm_resource_group.registry_rg.id
  role_definition_name = "User Access Administrator"
  principal_id         = data.azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to configure RBAC for managed identities and user access in Registry RG"
}

resource "azurerm_role_assignment" "sp_user_access_admin_vnet_rg" {
  scope                = azurerm_resource_group.vnet_rg.id
  role_definition_name = "User Access Administrator"
  principal_id         = data.azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to configure RBAC for managed identities in VNet RG"
}

# Endpoint managed identity permissions
resource "azurerm_role_assignment" "endpoint_storage_reader" {
  scope                = module.storage_account_default.storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.endpoint_identity.principal_id
  description          = "Allows ${var.purpose}-mi-endpoint to read model artifacts and data from workspace storage"
}

resource "azurerm_role_assignment" "endpoint_acr_pull_workspace" {
  scope                = module.container_registry.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.endpoint_identity.principal_id
  description          = "Allows ${var.purpose}-mi-endpoint to pull images from workspace ACR"
}

resource "azurerm_role_assignment" "endpoint_registry_user" {
  scope                = azurerm_machine_learning_registry.registry.id
  role_definition_name = "AzureML Registry User"
  principal_id         = azurerm_user_assigned_identity.endpoint_identity.principal_id
  description          = "Allows ${var.purpose}-mi-endpoint to access models, environments, and components from registry"
}

resource "azurerm_role_assignment" "endpoint_mi_operator" {
  scope                = azurerm_user_assigned_identity.endpoint_identity.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = data.azurerm_client_config.current.object_id
  description          = "Allows current user to assign ${var.purpose}-mi-endpoint to online endpoints"
}
