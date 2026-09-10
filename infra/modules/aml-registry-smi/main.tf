##### Create the base resources
#####

locals {
  rg_name         = var.resource_group_name
  rg_id           = "/subscriptions/${data.azurerm_client_config.identity_config.subscription_id}/resourceGroups/${local.rg_name}"
  resolved_suffix = coalesce(var.naming_suffix, "")

  managed_storage_account_id    = try(azapi_resource.registry.output.properties.regionDetails[0].storageAccountDetails[0].systemCreatedStorageAccount.armResourceId.resourceId, null)
  managed_container_registry_id = try(azapi_resource.registry.output.properties.regionDetails[0].acrDetails[0].systemCreatedAcrAccount.armResourceId.resourceId, null)
}

## Resource group is expected to be created by the root module

##### Create the Azure Machine Learning Registry
#####

## Create the Azure Machine Learning Registry
##
resource "azapi_resource" "registry" {
  type                      = "Microsoft.MachineLearningServices/registries@2025-01-01-preview"
  name                      = "${local.aml_registry_prefix}${var.purpose}${var.location_code}${local.resolved_suffix}"
  parent_id                 = local.rg_id
  location                  = var.location
  schema_validation_enabled = false

  body = {
    identity = {
      type = "SystemAssigned"
    }
    properties = {
      regionDetails = [
        {
          location = var.location
          storageAccountDetails = [
            {
              systemCreatedStorageAccount = {
                storageAccountType       = "Standard_LRS"
                storageAccountHnsEnabled = false
              }
            }
          ]
          acrDetails = [
            {
              systemCreatedAcrAccount = {
                acrAccountSku = "Premium"
              }
            }
          ]

        }
      ]
      managedResourceGroupSettings = {
        assignedIdentities = [
          for principal_id in sort(tolist(var.managed_rg_assigned_principal_ids)) : {
            principalId = principal_id
          }
        ]
      }
      publicNetworkAccess = "Disabled"
    }

    tags = var.tags
  }

  response_export_values = [
    "identity.principalId",
    "properties.regionDetails"
  ]

  lifecycle {
    ignore_changes = [tags]
  }
}


## Pause 10 seconds to ensure the managed identity has replicated
##
resource "time_sleep" "wait_registry_identity" {
  depends_on = [
    azapi_resource.registry
  ]
  create_duration = "10s"

  triggers = {
    principal_id = azapi_resource.registry.output.identity.principalId
    registry_id  = azapi_resource.registry.id
  }
}

##### Create the Private Endpoints for the registry
#####

module "private_endpoint_aml_registry" {
  depends_on = [
    azapi_resource.registry
  ]

  source              = "../private-endpoint"
  naming_suffix       = local.resolved_suffix
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = local.rg_name
  tags                = var.tags

  resource_name    = azapi_resource.registry.name
  resource_id      = azapi_resource.registry.id
  subresource_name = "amlregistry"

  subnet_id            = var.subnet_id
  private_dns_zone_ids = [local.dns_zone_aml_api_id]
}

module "private_endpoint_registry_storage_blob" {
  source = "../private-endpoint"

  naming_suffix       = local.resolved_suffix
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = local.rg_name
  tags                = var.tags

  resource_name    = basename(local.managed_storage_account_id)
  resource_id      = local.managed_storage_account_id
  subresource_name = "blob"

  subnet_id            = var.subnet_id
  private_dns_zone_ids = [local.dns_zone_blob_id]

  depends_on = [time_sleep.wait_registry_identity]
}

module "private_endpoint_registry_acr" {
  source = "../private-endpoint"

  naming_suffix       = local.resolved_suffix
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = local.rg_name
  tags                = var.tags

  resource_name    = basename(local.managed_container_registry_id)
  resource_id      = local.managed_container_registry_id
  subresource_name = "registry"

  subnet_id            = var.subnet_id
  private_dns_zone_ids = [local.dns_zone_acr_id]

  depends_on = [module.private_endpoint_registry_storage_blob]
}

// RBAC assignments removed — centralized in infra/main.tf

##### Diagnostic Settings for Monitoring
#####

# Azure ML Registry diagnostic settings with supported log categories
resource "azurerm_monitor_diagnostic_setting" "registry_diagnostics" {
  name                       = "${azapi_resource.registry.name}-diagnostics"
  target_resource_id         = azapi_resource.registry.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # ML Registry supported log categories based on Microsoft documentation
  enabled_log {
    category = "RegistryAssetReadEvent"
  }

  enabled_log {
    category = "RegistryAssetWriteEvent"
  }
}

resource "azurerm_monitor_diagnostic_setting" "managed_storage" {
  name                       = "managed-storage-diagnostics"
  target_resource_id         = local.managed_storage_account_id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_metric {
    category = "Transaction"
  }

  enabled_metric {
    category = "Capacity"
  }

  depends_on = [time_sleep.wait_registry_identity]
}

resource "azurerm_monitor_diagnostic_setting" "managed_storage_blob" {
  name                       = "managed-blob-diagnostics"
  target_resource_id         = "${local.managed_storage_account_id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }

  depends_on = [azurerm_monitor_diagnostic_setting.managed_storage]
}

resource "azurerm_monitor_diagnostic_setting" "managed_storage_file" {
  name                       = "managed-file-diagnostics"
  target_resource_id         = "${local.managed_storage_account_id}/fileServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }

  depends_on = [azurerm_monitor_diagnostic_setting.managed_storage_blob]
}

resource "azurerm_monitor_diagnostic_setting" "managed_storage_queue" {
  name                       = "managed-queue-diagnostics"
  target_resource_id         = "${local.managed_storage_account_id}/queueServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }

  depends_on = [azurerm_monitor_diagnostic_setting.managed_storage_file]
}

resource "azurerm_monitor_diagnostic_setting" "managed_storage_table" {
  name                       = "managed-table-diagnostics"
  target_resource_id         = "${local.managed_storage_account_id}/tableServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }

  depends_on = [azurerm_monitor_diagnostic_setting.managed_storage_queue]
}

resource "azurerm_monitor_diagnostic_setting" "managed_acr" {
  name                       = "managed-acr-diagnostics"
  target_resource_id         = local.managed_container_registry_id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }
  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }
  enabled_metric {
    category = "AllMetrics"
  }

  depends_on = [time_sleep.wait_registry_identity]
}



