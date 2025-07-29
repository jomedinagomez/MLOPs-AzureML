##### Create the base resources
#####

## Create resource group
##
resource "azurerm_resource_group" "rgwork" {

  name     = "rg-aml-reg-${var.purpose}-${var.location_code}"
  location = var.location
  tags = var.tags
}

##### Create the Azure Machine Learning Registry
#####

## Create the Azure Machine Learning Registry
##
resource "azapi_resource" "registry" {
  depends_on = [
    azurerm_resource_group.rgwork
  ]

  type                      = "Microsoft.MachineLearningServices/registries@2025-01-01-preview"
  name                      = "${local.aml_registry_prefix}${var.purpose}${var.location_code}${var.random_string}"
  parent_id                 = azurerm_resource_group.rgwork.id
  location                  = var.location
  schema_validation_enabled = true

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
      publicNetworkAccess = "Disabled"
    }

    tags = var.tags
  }

  response_export_values = [
    "identity.principalId"
  ]

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Pause 10 seconds to ensure the managed identity has replicated
##
resource "time_sleep" "wait_registry_identity" {
  depends_on = [
    azapi_resource.registry
  ]
  create_duration = "10s"
}

##### Create the Private Endpoints for the registry
#####

module "private_endpoint_aml_registry" {
  depends_on = [
    azapi_resource.registry
  ]

  source              = "../modules/private-endpoint"
  
  random_string       = var.random_string
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = azurerm_resource_group.rgwork.name
  tags                = var.tags

  resource_name    = azapi_resource.registry.name
  resource_id      = azapi_resource.registry.id
  subresource_name = "amlregistry"

  subnet_id = var.subnet_id
  private_dns_zone_ids = [local.dns_zone_aml_api_id]
}

##### Create role assignments for registry access
#####

## Assign AzureML Registry User role to user account
## This allows the user to read and use models from the registry
##
resource "azurerm_role_assignment" "registry_user_permission" {
  depends_on = [
    time_sleep.wait_registry_identity
  ]
  
  name                 = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${var.user_object_id}${azapi_resource.registry.name}registryuser")
  scope                = azapi_resource.registry.id
  role_definition_name = "AzureML Registry User"
  principal_id         = var.user_object_id
}

## Use the compute cluster managed identity passed from the VNet module
## The managed identity IDs are always passed from the parent module
##
locals {
  # Use the managed identity values passed from the VNet module
  compute_cluster_identity_id = var.compute_cluster_identity_id
  compute_cluster_principal_id = var.compute_cluster_principal_id
}

## Assign AzureML Registry User role to compute cluster managed identity
## This allows compute clusters to access models from the registry during training/inference
##
resource "azurerm_role_assignment" "compute_registry_user" {
  depends_on = [
    time_sleep.wait_registry_identity
  ]
  
  name                 = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${local.compute_cluster_principal_id}${azapi_resource.registry.name}registryuser")
  scope                = azapi_resource.registry.id
  role_definition_name = "AzureML Registry User"
  principal_id         = local.compute_cluster_principal_id
}

## Assign Azure AI Enterprise Network Connection Approver role to workspace system-managed identity
## This allows the workspace to create managed private endpoints to this registry
##
resource "azurerm_role_assignment" "workspace_network_connection_approver" {
  depends_on = [
    time_sleep.wait_registry_identity
  ]
  
  name                 = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${var.workspace_principal_id}${azapi_resource.registry.name}netapprover")
  scope                = azapi_resource.registry.id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = var.workspace_principal_id
}

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

