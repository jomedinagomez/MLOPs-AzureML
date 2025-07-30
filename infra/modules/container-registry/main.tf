resource "azurerm_container_registry" "acr" {
  name                = "${local.acr_name}${var.purpose}${var.location_code}${var.random_string}"
  resource_group_name = var.resource_group_name
  location            = var.location

  sku                    = local.sku_name
  admin_enabled          = local.local_admin_enabled
  anonymous_pull_enabled = local.anonymous_pull_enabled

  identity {
    type = "SystemAssigned"
  }

  public_network_access_enabled = var.public_network_access_enabled
  network_rule_set {
    default_action = var.default_network_action
  }
  network_rule_bypass_option = "AzureServices"

  tags = var.tags
}
resource "azurerm_monitor_diagnostic_setting" "diag-base" {
  name                       = "diag-base"
  target_resource_id         = azurerm_container_registry.acr.id
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }
  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }

  # Additional comprehensive logging for Container Registry
  enabled_metric {
    category = "AllMetrics"
  }
}

# Automatic Container Registry cleanup on destroy (configurable for dev/test environments)
resource "null_resource" "acr_cleanup" {
  count      = var.enable_auto_purge ? 1 : 0
  depends_on = [azurerm_container_registry.acr]

  # This runs when the resource is destroyed
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      # Get ACR name from triggers
      $acrName = "${self.triggers.acr_name}"
      $location = "${self.triggers.location}"
      
      # Purge soft-deleted repositories and manifests
      Write-Host "Cleaning up Container Registry: $acrName"
      
      # List and purge soft-deleted repositories (if any)
      try {
        $repos = az acr repository list --name $acrName --output json 2>$null | ConvertFrom-Json
        if ($repos) {
          foreach ($repo in $repos) {
            Write-Host "Purging repository: $repo"
            az acr repository delete --name $acrName --repository $repo --yes 2>$null
          }
        }
        Write-Host "Container Registry cleanup completed: $acrName"
      } catch {
        Write-Host "Container Registry already cleaned or not found: $acrName"
      }
    EOT

    # Use PowerShell on Windows, bash on Linux/Mac
    interpreter = ["PowerShell", "-Command"]
  }

  triggers = {
    acr_name = azurerm_container_registry.acr.name
    location = azurerm_container_registry.acr.location
  }

  lifecycle {
    # Prevent recreation when triggers change
    replace_triggered_by = [azurerm_container_registry.acr]
  }
}
