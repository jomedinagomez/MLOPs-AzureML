terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.32.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "azurerm" {
  subscription_id = "5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25"
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azapi" {
  subscription_id = "5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25"
}

# Data sources to automatically get current subscription and user information
data "azurerm_client_config" "current" {}

##### Module Orchestration
#####

# 1. Create networking foundation first
module "aml_vnet" {
  source = "./aml-vnet"

  prefix                = var.prefix
  resource_prefixes     = var.resource_prefixes
  purpose               = var.purpose
  location              = var.location
  location_code         = var.location_code
  random_string         = var.random_string
  vnet_address_space    = var.vnet_address_space
  subnet_address_prefix = var.subnet_address_prefix
  enable_auto_purge     = var.enable_auto_purge
  tags                  = var.tags
}

# 2. Create ML workspace (depends on VNet outputs)
module "aml_workspace" {
  source = "./aml-managed-smi"

  # Core variables
  prefix                  = var.prefix
  resource_prefixes       = var.resource_prefixes
  purpose                 = var.purpose
  location                = var.location
  location_code           = var.location_code
  random_string           = var.random_string
  sub_id                  = data.azurerm_client_config.current.subscription_id
  user_object_id          = data.azurerm_client_config.current.object_id
  tags                    = var.tags
  vnet_address_space      = var.vnet_address_space
  subnet_address_prefix   = var.subnet_address_prefix

  # Use VNet module outputs instead of variables
  subnet_id                   = module.aml_vnet.subnet_id
  resource_group_name_dns     = module.aml_vnet.resource_group_name_dns
  workload_vnet_location      = var.location
  workload_vnet_location_code = var.location_code

  # Pass managed identity IDs from VNet module
  compute_cluster_identity_id  = module.aml_vnet.cc_identity_id
  compute_cluster_principal_id = module.aml_vnet.cc_identity_principal_id

  # Pass DNS zone IDs from VNet module
  dns_zone_blob_id          = module.aml_vnet.dns_zone_blob_id
  dns_zone_file_id          = module.aml_vnet.dns_zone_file_id
  dns_zone_table_id         = module.aml_vnet.dns_zone_table_id
  dns_zone_queue_id         = module.aml_vnet.dns_zone_queue_id
  dns_zone_keyvault_id      = module.aml_vnet.dns_zone_keyvault_id
  dns_zone_acr_id           = module.aml_vnet.dns_zone_acr_id
  dns_zone_aml_api_id       = module.aml_vnet.dns_zone_aml_api_id
  dns_zone_aml_notebooks_id = module.aml_vnet.dns_zone_aml_notebooks_id

  # Pass Log Analytics workspace for diagnostic settings
  log_analytics_workspace_id = module.aml_vnet.log_analytics_workspace_id

  # Key Vault auto-purge configuration
  enable_auto_purge = var.enable_auto_purge
}

# 3. Create registry (depends on VNet outputs)
module "aml_registry" {
  source = "./aml-registry-smi"

  # Core variables
  prefix                      = var.prefix
  resource_prefixes           = var.resource_prefixes
  purpose                     = var.purpose
  location                    = var.location
  location_code               = var.location_code
  random_string               = var.random_string
  sub_id                      = data.azurerm_client_config.current.subscription_id
  user_object_id              = data.azurerm_client_config.current.object_id
  tags                        = var.tags
  workload_vnet_location      = var.location
  workload_vnet_location_code = var.location_code

  # Use VNet module outputs instead of variables
  subnet_id                   = module.aml_vnet.subnet_id
  resource_group_name_dns     = module.aml_vnet.resource_group_name_dns

  # Pass managed identity IDs from VNet module
  compute_cluster_identity_id  = module.aml_vnet.cc_identity_id
  compute_cluster_principal_id = module.aml_vnet.cc_identity_principal_id

  # Pass workspace principal ID for network connection approver role
  workspace_principal_id = module.aml_workspace.workspace_principal_id

  # Pass DNS zone IDs from VNet module
  dns_zone_blob_id     = module.aml_vnet.dns_zone_blob_id
  dns_zone_file_id     = module.aml_vnet.dns_zone_file_id
  dns_zone_keyvault_id = module.aml_vnet.dns_zone_keyvault_id
  dns_zone_acr_id      = module.aml_vnet.dns_zone_acr_id
  dns_zone_aml_api_id  = module.aml_vnet.dns_zone_aml_api_id

  # Pass Log Analytics workspace for diagnostic settings
  log_analytics_workspace_id = module.aml_vnet.log_analytics_workspace_id
}

# 4. Create outbound rule for workspace to registry connectivity (after both modules exist)
resource "azapi_resource" "workspace_to_registry_outbound_rule" {
  type      = "Microsoft.MachineLearningServices/workspaces/outboundRules@2024-10-01-preview"
  name      = "allow-external-registry-${var.purpose}"
  parent_id = module.aml_workspace.workspace_id

  body = {
    properties = {
      type = "PrivateEndpoint"
      destination = {
        serviceResourceId = module.aml_registry.registry_id
        subresourceTarget = "amlregistry"
      }
      category = "UserDefined"
    }
  }

  depends_on = [module.aml_workspace, module.aml_registry]
}

# 5. Configure storage account network rules to allow registry access for asset sharing
# This implements the requirement from: https://learn.microsoft.com/en-us/azure/machine-learning/how-to-registry-network-isolation
resource "azapi_update_resource" "workspace_storage_network_rules" {
  type        = "Microsoft.Storage/storageAccounts@2023-05-01"
  resource_id = module.aml_workspace.storage_account_id

  body = {
    properties = {
      allowSharedKeyAccess = true
      networkAcls = {
        defaultAction = "Deny"
        bypass        = "AzureServices"
        resourceAccessRules = [
          {
            resourceId = module.aml_workspace.workspace_id
            tenantId   = "*"
          },
          {
            resourceId = module.aml_registry.registry_id
            tenantId   = "*"
          }
        ]
      }
    }
  }

  depends_on = [module.aml_workspace, module.aml_registry]
}

# 6. Role assignments for dev-mi-endpoint managed identity
# These configure permissions for online endpoint deployments from external registries

# Managed Identity Operator role for current user over MOE identity
# This allows the current user to assign the MOE identity to online endpoints
resource "azurerm_role_assignment" "endpoint_mi_operator" {
  scope                = module.aml_vnet.moe_identity_id
  role_definition_name = "Managed Identity Operator"
  principal_id         = data.azurerm_client_config.current.object_id
  description          = "Allows current user to assign dev-mi-endpoint to online endpoints"

  depends_on = [module.aml_vnet]
}

# AcrPull role on workspace container registry
resource "azurerm_role_assignment" "endpoint_acr_pull_workspace" {
  scope                = module.aml_workspace.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = module.aml_vnet.moe_identity_principal_id
  description          = "Allows dev-mi-endpoint to pull images from workspace ACR"

  depends_on = [module.aml_workspace, module.aml_vnet]
}

# Storage Blob Data Reader role on workspace storage
resource "azurerm_role_assignment" "endpoint_storage_reader" {
  scope                = module.aml_workspace.storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = module.aml_vnet.moe_identity_principal_id
  description          = "Allows dev-mi-endpoint to read model artifacts and data from workspace storage"

  depends_on = [module.aml_workspace, module.aml_vnet]
}

# AzureML Registry User role on the registry for full asset access
resource "azurerm_role_assignment" "endpoint_registry_user" {
  scope                = module.aml_registry.registry_id
  role_definition_name = "AzureML Registry User"
  principal_id         = module.aml_vnet.moe_identity_principal_id
  description          = "Allows dev-mi-endpoint to access models, environments, and components from registry"

  depends_on = [module.aml_registry, module.aml_vnet]
}
