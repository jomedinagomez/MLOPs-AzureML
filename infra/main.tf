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
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azapi" {}

# Data sources to automatically get current subscription and user information
data "azurerm_client_config" "current" {}

##### Module Orchestration
#####

# 1. Create networking foundation first
module "aml_vnet" {
  source = "./aml-vnet"

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
  purpose        = var.purpose
  location       = var.location
  location_code  = var.location_code
  random_string  = var.random_string
  sub_id         = data.azurerm_client_config.current.subscription_id
  user_object_id = data.azurerm_client_config.current.object_id
  tags           = var.tags

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

  depends_on = [module.aml_vnet]
}

# 3. Create registry (depends on VNet outputs)
module "aml_registry" {
  source = "./aml-registry-smi"

  # Core variables
  purpose        = var.purpose
  location       = var.location
  location_code  = var.location_code
  random_string  = var.random_string
  sub_id         = data.azurerm_client_config.current.subscription_id
  user_object_id = data.azurerm_client_config.current.object_id
  tags           = var.tags

  # Use VNet module outputs instead of variables
  subnet_id                   = module.aml_vnet.subnet_id
  resource_group_name_dns     = module.aml_vnet.resource_group_name_dns
  workload_vnet_location      = var.location
  workload_vnet_location_code = var.location_code

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

  depends_on = [module.aml_vnet, module.aml_workspace]
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
