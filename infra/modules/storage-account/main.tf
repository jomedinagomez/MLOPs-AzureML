locals {
  resolved_suffix = coalesce(var.naming_suffix, "")
}

# Create a storage account
resource "azurerm_storage_account" "storage_account" {
  name                = "${local.storage_account_name}${var.purpose}${var.location_code}${local.resolved_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  account_kind                    = var.storage_account_kind
  account_tier                    = var.storage_account_tier
  account_replication_type        = var.storage_account_replication_type
  shared_access_key_enabled       = var.key_based_authentication
  allow_nested_items_to_be_public = var.allow_blob_public_access

  # Enforce private-only by default
  public_network_access_enabled = var.public_network_access_enabled

  network_rules {
    default_action = var.network_access_default

    # Configure bypass if bypass isn't an empty list
    bypass   = var.network_trusted_services_bypass
    ip_rules = var.allowed_ips
    dynamic "private_link_access" {
      for_each = var.resource_access != null ? var.resource_access : []
      content {
        endpoint_resource_id = private_link_access.value.endpoint_resource_id
        endpoint_tenant_id   = private_link_access.value.endpoint_tenant_id
      }
    }
  }

  blob_properties {
    dynamic "cors_rule" {
      for_each = var.cors_rules != null ? var.cors_rules : []
      content {
        allowed_origins    = cors_rule.value.allowed_origins
        allowed_methods    = cors_rule.value.allowed_methods
        allowed_headers    = cors_rule.value.allowed_headers
        max_age_in_seconds = cors_rule.value.max_age_in_seconds
        exposed_headers    = cors_rule.value.exposed_headers
      }
    }
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

# Configure diagnostic settings
resource "azurerm_monitor_diagnostic_setting" "diag-base" {

  depends_on = [azurerm_storage_account.storage_account]

  name                       = "${azurerm_storage_account.storage_account.name}-diag-base-${var.purpose}-${local.resolved_suffix}"
  target_resource_id         = azurerm_storage_account.storage_account.id
  log_analytics_workspace_id = var.law_resource_id

  enabled_metric {
    category = "Transaction"
  }

  enabled_metric {
    category = "Capacity"
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag-blob" {

  depends_on = [
    azurerm_storage_account.storage_account,
  azurerm_monitor_diagnostic_setting.diag-base]

  name                       = "${azurerm_storage_account.storage_account.name}-diag-blob-${var.purpose}-${local.resolved_suffix}"
  target_resource_id         = "${azurerm_storage_account.storage_account.id}/blobServices/default"
  log_analytics_workspace_id = var.law_resource_id

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

resource "azurerm_monitor_diagnostic_setting" "diag-file" {
  depends_on = [
    azurerm_storage_account.storage_account,
    azurerm_monitor_diagnostic_setting.diag-blob
  ]

  name                       = "${azurerm_storage_account.storage_account.name}-diag-file-${var.purpose}-${local.resolved_suffix}"
  target_resource_id         = "${azurerm_storage_account.storage_account.id}/fileServices/default"
  log_analytics_workspace_id = var.law_resource_id

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

resource "azurerm_monitor_diagnostic_setting" "diag-queue" {
  depends_on = [
    azurerm_storage_account.storage_account,
    azurerm_monitor_diagnostic_setting.diag-file
  ]

  name                       = "${azurerm_storage_account.storage_account.name}-diag-queue-${var.purpose}-${local.resolved_suffix}"
  target_resource_id         = "${azurerm_storage_account.storage_account.id}/queueServices/default"
  log_analytics_workspace_id = var.law_resource_id

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

resource "azurerm_monitor_diagnostic_setting" "diag-table" {

  depends_on = [
    azurerm_storage_account.storage_account,
    azurerm_monitor_diagnostic_setting.diag-queue
  ]

  name                       = "${azurerm_storage_account.storage_account.name}-diag-table-${var.purpose}-${local.resolved_suffix}"
  target_resource_id         = "${azurerm_storage_account.storage_account.id}/tableServices/default"
  log_analytics_workspace_id = var.law_resource_id

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

# Automatic Storage Account cleanup on destroy (configurable for dev/test environments)
resource "null_resource" "storage_cleanup" {
  count      = var.enable_auto_purge ? 1 : 0
  depends_on = [azurerm_storage_account.storage_account]

  # This runs when the resource is destroyed
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      # Get storage account details from triggers
      $storageAccount = "${self.triggers.storage_name}"
      $resourceGroup = "${self.triggers.resource_group}"
      
      Write-Host "Cleaning up Storage Account: $storageAccount"
      
      try {
        # Purge soft-deleted blobs and containers
        Write-Host "Purging soft-deleted blobs..."
        az storage blob undelete-batch --account-name $storageAccount --source '$root' 2>$null
        
        # List and purge soft-deleted containers
        Write-Host "Checking for soft-deleted containers..."
        $containers = az storage container list --account-name $storageAccount --include-deleted --query "[?deleted].name" --output tsv 2>$null
        if ($containers) {
          foreach ($container in $containers) {
            Write-Host "Purging soft-deleted container: $container"
            az storage container restore --account-name $storageAccount --name $container 2>$null
            az storage container delete --account-name $storageAccount --name $container 2>$null
          }
        }
        
        Write-Host "Storage Account cleanup completed: $storageAccount"
      } catch {
        Write-Host "Storage Account already cleaned or not accessible: $storageAccount"
      }
    EOT

    # Use PowerShell on Windows, bash on Linux/Mac
    interpreter = ["PowerShell", "-Command"]
  }

  triggers = {
    storage_name   = azurerm_storage_account.storage_account.name
    resource_group = azurerm_storage_account.storage_account.resource_group_name
  }

  lifecycle {
    # Only recreate if the storage account itself is recreated
    # Don't recreate for minor storage account changes
    ignore_changes = [triggers]
  }
}
