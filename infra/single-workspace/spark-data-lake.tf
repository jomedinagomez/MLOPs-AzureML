locals {
  spark_data_lake_account_name = substr(
    lower(replace("st${var.purpose}dl${var.location_code}04", "-", "")),
    0,
    24
  )
  spark_data_lake_filesystem_name = "spark"
}

resource "azurerm_storage_account" "spark_data_lake" {
  name                              = local.spark_data_lake_account_name
  resource_group_name               = azurerm_resource_group.workspace.name
  location                          = var.location
  account_kind                      = "StorageV2"
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  is_hns_enabled                    = true
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  allow_nested_items_to_be_public   = false
  public_network_access_enabled     = true
  infrastructure_encryption_enabled = true

  identity {
    type = "SystemAssigned"
  }

  dynamic "network_rules" {
    for_each = var.network_profile == "managed" ? [1] : []

    content {
      default_action = "Deny"
      bypass         = ["AzureServices"]
      ip_rules = [
        for cidr in var.allowed_public_ip_cidrs :
        endswith(cidr, "/32") ? trimsuffix(cidr, "/32") : cidr
      ]
    }
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
    environment = var.purpose
    component   = "spark-data-lake"
  })
}

resource "azurerm_role_assignment" "workspace_spark_data_lake_contributor" {
  name                 = uuidv5("dns", "${azurerm_storage_account.spark_data_lake.id}${module.workspace.workspace_uami_principal_id}sparkcontributor")
  scope                = azurerm_storage_account.spark_data_lake.id
  role_definition_name = "Contributor"
  principal_id         = module.workspace.workspace_uami_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "workspace_spark_data_lake_blob_contributor" {
  name                 = uuidv5("dns", "${azurerm_storage_account.spark_data_lake.id}${module.workspace.workspace_uami_principal_id}sparkblobdatacontributor")
  scope                = azurerm_storage_account.spark_data_lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.workspace.workspace_uami_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "caller_spark_data_lake_blob_owner" {
  count                = var.assign_user_roles ? 1 : 0
  name                 = uuidv5("dns", "${azurerm_storage_account.spark_data_lake.id}${data.azurerm_client_config.current.object_id}sparkblobdataowner")
  scope                = azurerm_storage_account.spark_data_lake.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "wait_spark_data_lake_rbac" {
  create_duration = "60s"

  depends_on = [
    azurerm_role_assignment.workspace_spark_data_lake_contributor,
    azurerm_role_assignment.workspace_spark_data_lake_blob_contributor,
    azurerm_role_assignment.caller_spark_data_lake_blob_owner
  ]
}

resource "azurerm_storage_data_lake_gen2_filesystem" "spark" {
  name               = local.spark_data_lake_filesystem_name
  storage_account_id = azurerm_storage_account.spark_data_lake.id

  depends_on = [time_sleep.wait_spark_data_lake_rbac]
}

resource "azurerm_storage_blob" "spark_titanic_sample" {
  name                   = "data/titanic.csv"
  storage_account_name   = azurerm_storage_account.spark_data_lake.name
  storage_container_name = azurerm_storage_data_lake_gen2_filesystem.spark.name
  type                   = "Block"
  source                 = "${path.module}/../../workshop/notebooks/06_spark_jobs_pipelines/data/titanic.csv"

  depends_on = [azurerm_storage_data_lake_gen2_filesystem.spark]
}
