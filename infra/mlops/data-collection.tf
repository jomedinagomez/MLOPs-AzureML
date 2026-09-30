resource "azurerm_resource_group" "data_collection" {
  count = var.enable_data_collection_storage ? 1 : 0

  name     = "rg-${var.prefix}-datacollection-${var.location_code}-${var.naming_suffix}"
  location = var.location
  tags = merge(var.tags, {
    environment = "shared"
    purpose     = "data-collection"
    component   = "storage"
  })
}

resource "azurerm_storage_account" "data_collection" {
  count = var.enable_data_collection_storage ? 1 : 0

  #checkov:skip=CKV_AZURE_43: The resolved stamldccc01 name passes Azure's storage-account naming rules.
  #checkov:skip=CKV_AZURE_33: Queue logging is configured by azurerm_storage_account_queue_properties.data_collection below.
  #checkov:skip=CKV2_AZURE_33: Blob and DFS private endpoints are declared below for both Dev and Prod VNets.
  #checkov:skip=CKV2_AZURE_1: This shared collection account uses GRS plus infrastructure encryption; workspace and managed-resource CMK is handled separately per environment.

  name                = "st${var.prefix}dc${var.location_code}${var.naming_suffix}"
  resource_group_name = azurerm_resource_group.data_collection[0].name
  location            = var.location

  account_kind                      = "StorageV2"
  account_tier                      = "Standard"
  account_replication_type          = var.data_collection_storage_replication_type
  is_hns_enabled                    = true
  shared_access_key_enabled         = false
  allow_nested_items_to_be_public   = false
  default_to_oauth_authentication   = true
  https_traffic_only_enabled        = true
  infrastructure_encryption_enabled = true
  local_user_enabled                = false
  min_tls_version                   = "TLS1_2"
  public_network_access_enabled     = false

  identity {
    type = "SystemAssigned"
  }

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  blob_properties {
    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = merge(var.tags, {
    environment = "shared"
    purpose     = "data-collection"
    component   = "storage"
  })

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

resource "azurerm_storage_account_queue_properties" "data_collection" {
  count = var.enable_data_collection_storage ? 1 : 0

  storage_account_id = azurerm_storage_account.data_collection[0].id

  logging {
    delete                = true
    read                  = true
    version               = "1.0"
    write                 = true
    retention_policy_days = 30
  }
}

resource "azapi_resource" "data_collection_container" {
  count = var.enable_data_collection_storage ? 1 : 0

  type                      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  name                      = "datacollection"
  parent_id                 = "${azurerm_storage_account.data_collection[0].id}/blobServices/default"
  schema_validation_enabled = false

  body = {
    properties = {
      publicAccess = "None"
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "data_collection_storage" {
  count = var.enable_data_collection_storage ? 1 : 0

  name                       = "${azurerm_storage_account.data_collection[0].name}-diagnostics"
  target_resource_id         = azurerm_storage_account.data_collection[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.dev_logs.id

  enabled_metric {
    category = "Transaction"
  }

  enabled_metric {
    category = "Capacity"
  }
}

resource "azurerm_monitor_diagnostic_setting" "data_collection_blob" {
  count = var.enable_data_collection_storage ? 1 : 0

  name                       = "blob"
  target_resource_id         = "${azurerm_storage_account.data_collection[0].id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.dev_logs.id

  enabled_log {
    category_group = "audit"
  }

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "Transaction"
  }
}

resource "azurerm_monitor_diagnostic_setting" "data_collection_queue" {
  count = var.enable_data_collection_storage ? 1 : 0

  name                       = "${azurerm_storage_account.data_collection[0].name}-queue-diagnostics"
  target_resource_id         = "${azurerm_storage_account.data_collection[0].id}/queueServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.dev_logs.id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }
}

module "dev_data_collection_blob_private_endpoint" {
  count = var.enable_data_collection_storage ? 1 : 0

  source              = "./modules/private-endpoint"
  location            = var.location
  location_code       = var.location_code
  naming_suffix       = "${var.naming_suffix}dev"
  resource_group_name = azurerm_resource_group.dev_workspace_rg.name
  resource_name       = azurerm_storage_account.data_collection[0].name
  resource_id         = azurerm_storage_account.data_collection[0].id
  subresource_name    = "blob"
  subnet_id           = azurerm_subnet.dev_pe.id
  private_dns_zone_ids = [
    azurerm_private_dns_zone.shared_blob.id
  ]
  tags = merge(var.tags, { environment = "development", purpose = "data-collection" })
}

module "dev_data_collection_dfs_private_endpoint" {
  count = var.enable_data_collection_storage ? 1 : 0

  source              = "./modules/private-endpoint"
  location            = var.location
  location_code       = var.location_code
  naming_suffix       = "${var.naming_suffix}dev"
  resource_group_name = azurerm_resource_group.dev_workspace_rg.name
  resource_name       = azurerm_storage_account.data_collection[0].name
  resource_id         = azurerm_storage_account.data_collection[0].id
  subresource_name    = "dfs"
  subnet_id           = azurerm_subnet.dev_pe.id
  private_dns_zone_ids = [
    azurerm_private_dns_zone.shared_dfs.id
  ]
  tags       = merge(var.tags, { environment = "development", purpose = "data-collection" })
  depends_on = [module.dev_data_collection_blob_private_endpoint]
}

module "prod_data_collection_blob_private_endpoint" {
  count = var.enable_data_collection_storage ? 1 : 0

  source              = "./modules/private-endpoint"
  location            = var.location
  location_code       = var.location_code
  naming_suffix       = "${var.naming_suffix}prod"
  resource_group_name = azurerm_resource_group.prod_workspace_rg.name
  resource_name       = azurerm_storage_account.data_collection[0].name
  resource_id         = azurerm_storage_account.data_collection[0].id
  subresource_name    = "blob"
  subnet_id           = azurerm_subnet.prod_pe.id
  private_dns_zone_ids = [
    azurerm_private_dns_zone.shared_blob.id
  ]
  tags = merge(var.tags, { environment = "production", purpose = "data-collection" })
}

module "prod_data_collection_dfs_private_endpoint" {
  count = var.enable_data_collection_storage ? 1 : 0

  source              = "./modules/private-endpoint"
  location            = var.location
  location_code       = var.location_code
  naming_suffix       = "${var.naming_suffix}prod"
  resource_group_name = azurerm_resource_group.prod_workspace_rg.name
  resource_name       = azurerm_storage_account.data_collection[0].name
  resource_id         = azurerm_storage_account.data_collection[0].id
  subresource_name    = "dfs"
  subnet_id           = azurerm_subnet.prod_pe.id
  private_dns_zone_ids = [
    azurerm_private_dns_zone.shared_dfs.id
  ]
  tags       = merge(var.tags, { environment = "production", purpose = "data-collection" })
  depends_on = [module.prod_data_collection_blob_private_endpoint]
}

locals {
  data_collection_principals = var.enable_data_collection_storage ? {
    dev_workspace  = module.dev_managed_umi.workspace_uami_principal_id
    dev_compute    = azurerm_user_assigned_identity.dev_cc.principal_id
    dev_endpoint   = azurerm_user_assigned_identity.dev_online_endpoint.principal_id
    prod_workspace = module.prod_managed_umi.workspace_uami_principal_id
    prod_compute   = azurerm_user_assigned_identity.prod_cc.principal_id
    prod_endpoint  = azurerm_user_assigned_identity.prod_online_endpoint.principal_id
  } : {}
}

resource "azurerm_role_assignment" "data_collection_blob_contributor" {
  for_each = local.data_collection_principals

  name                 = uuidv5("dns", "${azurerm_storage_account.data_collection[0].id}${each.value}blobdatacontributor")
  scope                = azurerm_storage_account.data_collection[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "dev_workspace_data_collection_network_approver" {
  count = var.enable_data_collection_storage ? 1 : 0

  name                 = uuidv5("dns", "${azurerm_resource_group.data_collection[0].id}${module.dev_managed_umi.workspace_uami_principal_id}networkapprover")
  scope                = azurerm_resource_group.data_collection[0].id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = module.dev_managed_umi.workspace_uami_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "prod_workspace_data_collection_network_approver" {
  count = var.enable_data_collection_storage ? 1 : 0

  name                 = uuidv5("dns", "${azurerm_resource_group.data_collection[0].id}${module.prod_managed_umi.workspace_uami_principal_id}networkapprover")
  scope                = azurerm_resource_group.data_collection[0].id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = module.prod_managed_umi.workspace_uami_principal_id
  principal_type       = "ServicePrincipal"
}

resource "time_sleep" "wait_data_collection_rbac" {
  count = var.enable_data_collection_storage ? 1 : 0

  create_duration = "120s"
  depends_on = [
    azurerm_role_assignment.data_collection_blob_contributor,
    azurerm_role_assignment.dev_workspace_data_collection_network_approver,
    azurerm_role_assignment.prod_workspace_data_collection_network_approver
  ]

  triggers = {
    role_assignment_ids = sha256(join(",", sort(concat(
      [for assignment in azurerm_role_assignment.data_collection_blob_contributor : assignment.id],
      azurerm_role_assignment.dev_workspace_data_collection_network_approver[*].id,
      azurerm_role_assignment.prod_workspace_data_collection_network_approver[*].id
    ))))
  }
}

resource "azapi_resource" "dev_data_collection_datastore" {
  count = var.enable_data_collection_storage ? 1 : 0

  type      = "Microsoft.MachineLearningServices/workspaces/datastores@2024-04-01"
  name      = "datacollection_adls"
  parent_id = module.dev_managed_umi.workspace_id

  body = {
    properties = {
      description = "Private ADLS Gen2 datastore for development inference data collection"
      credentials = {
        credentialsType = "None"
      }
      datastoreType = "AzureDataLakeGen2"
      accountName   = azurerm_storage_account.data_collection[0].name
      filesystem    = "datacollection"
    }
  }

  depends_on = [
    azapi_resource.data_collection_container,
    module.dev_data_collection_blob_private_endpoint,
    module.dev_data_collection_dfs_private_endpoint,
    time_sleep.wait_data_collection_rbac
  ]
}

resource "azapi_resource" "prod_data_collection_datastore" {
  count = var.enable_data_collection_storage ? 1 : 0

  type      = "Microsoft.MachineLearningServices/workspaces/datastores@2024-04-01"
  name      = "datacollection_adls"
  parent_id = module.prod_managed_umi.workspace_id

  body = {
    properties = {
      description = "Private ADLS Gen2 datastore for production inference data collection"
      credentials = {
        credentialsType = "None"
      }
      datastoreType = "AzureDataLakeGen2"
      accountName   = azurerm_storage_account.data_collection[0].name
      filesystem    = "datacollection"
    }
  }

  depends_on = [
    azapi_resource.data_collection_container,
    module.prod_data_collection_blob_private_endpoint,
    module.prod_data_collection_dfs_private_endpoint,
    time_sleep.wait_data_collection_rbac
  ]
}

resource "azapi_resource" "dev_data_collection_blob_outbound_rule" {
  count = var.enable_data_collection_storage ? 1 : 0

  type      = "Microsoft.MachineLearningServices/workspaces/outboundRules@2024-10-01-preview"
  name      = "AllowDataCollectionBlob"
  parent_id = module.dev_managed_umi.workspace_id

  body = {
    properties = {
      type = "PrivateEndpoint"
      destination = {
        serviceResourceId = azurerm_storage_account.data_collection[0].id
        subresourceTarget = "blob"
      }
      category = "UserDefined"
    }
  }

  depends_on = [time_sleep.wait_data_collection_rbac]
}

resource "azapi_resource" "dev_data_collection_dfs_outbound_rule" {
  count = var.enable_data_collection_storage ? 1 : 0

  type      = "Microsoft.MachineLearningServices/workspaces/outboundRules@2024-10-01-preview"
  name      = "AllowDataCollectionDfs"
  parent_id = module.dev_managed_umi.workspace_id

  body = {
    properties = {
      type = "PrivateEndpoint"
      destination = {
        serviceResourceId = azurerm_storage_account.data_collection[0].id
        subresourceTarget = "dfs"
      }
      category = "UserDefined"
    }
  }

  depends_on = [azapi_resource.dev_data_collection_blob_outbound_rule]
}

resource "azapi_resource" "prod_data_collection_blob_outbound_rule" {
  count = var.enable_data_collection_storage ? 1 : 0

  type      = "Microsoft.MachineLearningServices/workspaces/outboundRules@2024-10-01-preview"
  name      = "AllowDataCollectionBlob"
  parent_id = module.prod_managed_umi.workspace_id

  body = {
    properties = {
      type = "PrivateEndpoint"
      destination = {
        serviceResourceId = azurerm_storage_account.data_collection[0].id
        subresourceTarget = "blob"
      }
      category = "UserDefined"
    }
  }

  depends_on = [time_sleep.wait_data_collection_rbac]
}

resource "azapi_resource" "prod_data_collection_dfs_outbound_rule" {
  count = var.enable_data_collection_storage ? 1 : 0

  type      = "Microsoft.MachineLearningServices/workspaces/outboundRules@2024-10-01-preview"
  name      = "AllowDataCollectionDfs"
  parent_id = module.prod_managed_umi.workspace_id

  body = {
    properties = {
      type = "PrivateEndpoint"
      destination = {
        serviceResourceId = azurerm_storage_account.data_collection[0].id
        subresourceTarget = "dfs"
      }
      category = "UserDefined"
    }
  }

  depends_on = [azapi_resource.prod_data_collection_blob_outbound_rule]
}

output "data_collection_storage" {
  description = "Private shared data-collection storage and datastore details"
  value = var.enable_data_collection_storage ? {
    storage_account_id   = azurerm_storage_account.data_collection[0].id
    storage_account_name = azurerm_storage_account.data_collection[0].name
    filesystem           = "datacollection"
    datastore_name       = "datacollection_adls"
  } : null
  depends_on = [time_sleep.wait_data_collection_rbac]
}