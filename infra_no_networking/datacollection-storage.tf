# ===============================
# DATA COLLECTION STORAGE ACCOUNT
# ===============================
# Dedicated ADLS Gen2 storage account for model inference data collection
# Supports OneLake Shortcuts from Microsoft Fabric
#
# Architecture:
#   Azure ML Endpoint → Data Collector → ADLS Gen2 → OneLake Shortcut → Fabric Lakehouse

# Resource group for data collection storage (shared across environments)
resource "azurerm_resource_group" "datacollection_rg" {
  name     = "rg-${var.prefix}-datacollection-${var.location_code}-${var.naming_suffix}"
  location = var.location
  tags = merge(var.tags, {
    environment = "shared"
    purpose     = "data-collection"
    component   = "storage"
  })
}

# ADLS Gen2 storage account for model data collection
resource "azurerm_storage_account" "datacollection" {
  name                = "st${var.prefix}dc${var.location_code}${var.naming_suffix}"
  resource_group_name = azurerm_resource_group.datacollection_rg.name
  location            = var.location
  tags = merge(var.tags, {
    environment = "shared"
    purpose     = "data-collection"
  })

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS" # Change to GRS/ZRS for production if needed
  access_tier              = "Hot"

  # Enable hierarchical namespace for ADLS Gen2
  is_hns_enabled = true

  # Security settings
  shared_access_key_enabled       = true # Required for OneLake shortcuts
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"

  # Network access - adjust based on your security requirements
  public_network_access_enabled = var.datacollection_storage_public_access

  network_rules {
    default_action = var.datacollection_storage_default_action
    bypass         = ["AzureServices"] # Allow Azure ML to write

    # Add your IP addresses if needed for management
    ip_rules = var.datacollection_storage_allowed_ips
  }

  # Lifecycle management for cost optimization
  blob_properties {
    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }

    # Optional: Enable versioning for audit trail
    versioning_enabled = var.datacollection_storage_versioning_enabled
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

# Single container for data collection (inputs and outputs as subdirectories)
resource "azurerm_storage_container" "datacollection" {
  name                  = "datacollection"
  storage_account_name  = azurerm_storage_account.datacollection.name
  container_access_type = "private"

  depends_on = [azurerm_storage_account.datacollection]
}

# Diagnostic settings for monitoring
resource "azurerm_monitor_diagnostic_setting" "datacollection_storage" {
  name                       = "${azurerm_storage_account.datacollection.name}-diag"
  target_resource_id         = azurerm_storage_account.datacollection.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.dev_logs.id

  # Metrics
  metric {
    category = "Transaction"
    enabled  = true
  }

  metric {
    category = "Capacity"
    enabled  = true
  }

  depends_on = [
    azurerm_storage_account.datacollection,
    azurerm_log_analytics_workspace.dev_logs
  ]
}

# ===============================
# RBAC FOR DATA COLLECTION STORAGE
# ===============================

# Allow dev workspace managed identity to write data
resource "azurerm_role_assignment" "dev_workspace_to_datacollection_blob_contributor" {
  scope                = azurerm_storage_account.datacollection.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.dev_managed_umi.workspace_uami_principal_id

  depends_on = [
    azurerm_storage_account.datacollection,
    module.dev_managed_umi
  ]
}

# Allow prod workspace managed identity to write data
resource "azurerm_role_assignment" "prod_workspace_to_datacollection_blob_contributor" {
  scope                = azurerm_storage_account.datacollection.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.prod_managed_umi.workspace_uami_principal_id

  depends_on = [
    azurerm_storage_account.datacollection,
    module.prod_managed_umi
  ]
}

# Allow deployment service principal to manage storage
resource "azurerm_role_assignment" "sp_datacollection_contributor" {
  scope                = azurerm_resource_group.datacollection_rg.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id

  depends_on = [azurerm_resource_group.datacollection_rg]
}

# Optional: Allow human user to read and write collected data
resource "azurerm_role_assignment" "user_datacollection_blob_contributor" {
  count                = local._user_role_enable ? 1 : 0
  scope                = azurerm_storage_account.datacollection.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [azurerm_storage_account.datacollection]
}

# ===============================
# REGISTER AS AZURE ML DATASTORES
# ===============================

# Register ADLS Gen2 as datastore in dev workspace
resource "azapi_resource" "datacollection_datastore_dev" {
  type      = "Microsoft.MachineLearningServices/workspaces/datastores@2024-04-01"
  name      = "datacollection_adls"
  parent_id = module.dev_managed_umi.workspace_id

  body = {
    properties = {
      description = "ADLS Gen2 for model inference data collection - supports OneLake shortcuts"
      credentials = {
        credentialsType = "None" # Uses workspace managed identity
      }
      datastoreType = "AzureDataLakeGen2"
      accountName   = azurerm_storage_account.datacollection.name
      filesystem    = "datacollection"
    }
  }

  depends_on = [
    azurerm_storage_account.datacollection,
    azurerm_storage_container.datacollection,
    module.dev_managed_umi,
    azurerm_role_assignment.dev_workspace_to_datacollection_blob_contributor
  ]
}

# Register ADLS Gen2 as datastore in prod workspace
resource "azapi_resource" "datacollection_datastore_prod" {
  type      = "Microsoft.MachineLearningServices/workspaces/datastores@2024-04-01"
  name      = "datacollection_adls"
  parent_id = module.prod_managed_umi.workspace_id

  body = {
    properties = {
      description = "ADLS Gen2 for model inference data collection - supports OneLake shortcuts"
      credentials = {
        credentialsType = "None" # Uses workspace managed identity
      }
      datastoreType = "AzureDataLakeGen2"
      accountName   = azurerm_storage_account.datacollection.name
      filesystem    = "datacollection"
    }
  }

  depends_on = [
    azurerm_storage_account.datacollection,
    azurerm_storage_container.datacollection,
    module.prod_managed_umi,
    azurerm_role_assignment.prod_workspace_to_datacollection_blob_contributor
  ]
}

# ===============================
# OUTPUTS
# ===============================

output "datacollection_storage_account_name" {
  description = "Name of the data collection storage account"
  value       = azurerm_storage_account.datacollection.name
}

output "datacollection_storage_account_id" {
  description = "Resource ID of the data collection storage account"
  value       = azurerm_storage_account.datacollection.id
}

output "datacollection_storage_primary_blob_endpoint" {
  description = "Primary blob endpoint for data collection storage"
  value       = azurerm_storage_account.datacollection.primary_blob_endpoint
}

output "datacollection_storage_primary_dfs_endpoint" {
  description = "Primary DFS (ADLS Gen2) endpoint for data collection storage"
  value       = azurerm_storage_account.datacollection.primary_dfs_endpoint
}

output "datacollection_storage_connection_string" {
  description = "Connection string for data collection storage (sensitive)"
  value       = azurerm_storage_account.datacollection.primary_connection_string
  sensitive   = true
}

output "datacollection_abfss_path" {
  description = "ABFSS path for OneLake shortcuts"
  value       = "abfss://datacollection@${azurerm_storage_account.datacollection.name}.dfs.core.windows.net/"
}

output "datacollection_datastore_name" {
  description = "Name of the registered datastore in Azure ML workspaces"
  value       = "datacollection_adls"
}
