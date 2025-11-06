locals {
  rg_name         = var.resource_group_name
  resolved_suffix = coalesce(var.naming_suffix, "")
}

resource "azurerm_virtual_network" "aml_vnet" {
  name                = "${local.vnet_prefix}${var.purpose}${var.location_code}${local.resolved_suffix}"
  address_space       = [var.vnet_address_space]
  location            = var.location
  resource_group_name = local.rg_name
  tags                = var.tags
}

resource "azurerm_subnet" "aml_subnet" {
  name                 = "${local.subnet_prefix}${var.purpose}${var.location_code}${local.resolved_suffix}"
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.aml_vnet.name
  address_prefixes     = [var.subnet_address_prefix]
}

# NOTE: Compute UAMI is now created in the workspace resource group by root orchestration
# and passed into the workspace module. This module no longer creates a compute UAMI.

##### Private DNS Zones for Azure ML and supporting services
#####

# Storage Account Private DNS Zones
resource "azurerm_private_dns_zone" "blob" {
  count               = var.manage_supporting_private_dns_zones ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = local.rg_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "file" {
  count               = var.manage_supporting_private_dns_zones ? 1 : 0
  name                = "privatelink.file.core.windows.net"
  resource_group_name = local.rg_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "table" {
  count               = var.manage_supporting_private_dns_zones ? 1 : 0
  name                = "privatelink.table.core.windows.net"
  resource_group_name = local.rg_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "queue" {
  count               = var.manage_supporting_private_dns_zones ? 1 : 0
  name                = "privatelink.queue.core.windows.net"
  resource_group_name = local.rg_name
  tags                = var.tags
}

# Key Vault Private DNS Zone
resource "azurerm_private_dns_zone" "keyvault" {
  count               = var.manage_supporting_private_dns_zones ? 1 : 0
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = local.rg_name
  tags                = var.tags
}

# Container Registry Private DNS Zone
resource "azurerm_private_dns_zone" "acr" {
  count               = var.manage_supporting_private_dns_zones ? 1 : 0
  name                = "privatelink.azurecr.io"
  resource_group_name = local.rg_name
  tags                = var.tags
}

# Azure ML Workspace Private DNS Zones
resource "azurerm_private_dns_zone" "aml_api" {
  count               = var.manage_aml_private_dns_zones ? 1 : 0
  name                = "privatelink.api.azureml.ms"
  resource_group_name = local.rg_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "aml_notebooks" {
  count               = var.manage_aml_private_dns_zones ? 1 : 0
  name                = "privatelink.notebooks.azure.net"
  resource_group_name = local.rg_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "aml_instances" {
  count               = var.manage_aml_private_dns_zones ? 1 : 0
  name                = "instances.azureml.ms"
  resource_group_name = local.rg_name
  tags                = var.tags
}

##### VNet Links for Private DNS Zones
#####

resource "azurerm_private_dns_zone_virtual_network_link" "blob_link" {
  count                 = var.manage_supporting_private_dns_zones ? 1 : 0
  name                  = "blob-vnet-link"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = azurerm_virtual_network.aml_vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "file_link" {
  count                 = var.manage_supporting_private_dns_zones ? 1 : 0
  name                  = "file-vnet-link"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.file[0].name
  virtual_network_id    = azurerm_virtual_network.aml_vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "table_link" {
  count                 = var.manage_supporting_private_dns_zones ? 1 : 0
  name                  = "table-vnet-link"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.table[0].name
  virtual_network_id    = azurerm_virtual_network.aml_vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "queue_link" {
  count                 = var.manage_supporting_private_dns_zones ? 1 : 0
  name                  = "queue-vnet-link"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.queue[0].name
  virtual_network_id    = azurerm_virtual_network.aml_vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault_link" {
  count                 = var.manage_supporting_private_dns_zones ? 1 : 0
  name                  = "keyvault-vnet-link"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault[0].name
  virtual_network_id    = azurerm_virtual_network.aml_vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr_link" {
  count                 = var.manage_supporting_private_dns_zones ? 1 : 0
  name                  = "acr-vnet-link"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.acr[0].name
  virtual_network_id    = azurerm_virtual_network.aml_vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aml_api_link" {
  count                 = var.manage_aml_private_dns_zones ? 1 : 0
  name                  = "aml-api-vnet-link"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.aml_api[0].name
  virtual_network_id    = azurerm_virtual_network.aml_vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aml_notebooks_link" {
  count                 = var.manage_aml_private_dns_zones ? 1 : 0
  name                  = "aml-notebooks-vnet-link"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.aml_notebooks[0].name
  virtual_network_id    = azurerm_virtual_network.aml_vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aml_instances_link" {
  count                 = var.manage_aml_private_dns_zones ? 1 : 0
  name                  = "aml-instances-vnet-link"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.aml_instances[0].name
  virtual_network_id    = azurerm_virtual_network.aml_vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

##### Log Analytics and Monitoring
#####

# Log Analytics Workspace for VNet monitoring
resource "azurerm_log_analytics_workspace" "vnet_logs" {
  name                = "${local.log_analytics_prefix}${var.purpose}${var.location_code}${local.resolved_suffix}"
  location            = var.location
  resource_group_name = local.rg_name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

data "azurerm_client_config" "identity_config" {}

##### Diagnostic Settings for Monitoring
#####

# Virtual Network diagnostic settings with supported log categories
resource "azurerm_monitor_diagnostic_setting" "vnet_diagnostics" {
  name                       = "${azurerm_virtual_network.aml_vnet.name}-diagnostics-${var.purpose}-${local.resolved_suffix}"
  target_resource_id         = azurerm_virtual_network.aml_vnet.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.vnet_logs.id

  # VNet only supports VMProtectionAlerts log category based on Microsoft documentation
  enabled_log {
    category = "VMProtectionAlerts"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

##### Log Analytics Workspace Cleanup
#####

# Automatic Log Analytics Workspace cleanup on destroy (configurable for dev/test environments)
resource "null_resource" "log_analytics_cleanup" {
  count = var.enable_auto_purge ? 1 : 0

  # This runs when the resource is destroyed
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      $workspaceName = "${self.triggers.workspace_name}"
      $resourceGroup = "${self.triggers.resource_group}"
      
      Write-Host "Force purging Log Analytics workspace: $workspaceName"
      
      try {
        # Force purge the Log Analytics workspace to allow immediate recreation
        az monitor log-analytics workspace delete --force true --workspace-name $workspaceName --resource-group $resourceGroup --yes 2>$null
        if ($LASTEXITCODE -eq 0) {
          Write-Host "✓ Log Analytics workspace force purged successfully"
        } else {
          Write-Host "⚠ Could not force purge workspace - it may already be deleted"
        }
      } catch {
        Write-Host "⚠ Error during workspace purge: $($_.Exception.Message)"
      }
    EOT

    interpreter = ["PowerShell", "-Command"]
  }

  depends_on = [azurerm_log_analytics_workspace.vnet_logs]

  # Lifecycle management to prevent recreation during normal operations
  lifecycle {
    ignore_changes = all
  }

  triggers = {
    workspace_name = azurerm_log_analytics_workspace.vnet_logs.name
    resource_group = azurerm_log_analytics_workspace.vnet_logs.resource_group_name
    workspace_id   = azurerm_log_analytics_workspace.vnet_logs.id
    enable_purge   = var.enable_auto_purge
  }
}
