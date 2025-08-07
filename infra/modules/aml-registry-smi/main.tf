##### Create the base resources
#####

locals {
  use_existing_rg = var.resource_group_name != ""
  rg_name         = local.use_existing_rg ? var.resource_group_name : "rg-aml-reg-${var.purpose}-${var.location_code}${var.random_string}"
}

## Create resource group if not provided
resource "azurerm_resource_group" "rgwork" {
  count    = local.use_existing_rg ? 0 : 1
  name     = local.rg_name
  location = var.location
  tags     = var.tags
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
  parent_id                 = local.use_existing_rg ? "/subscriptions/${data.azurerm_client_config.identity_config.subscription_id}/resourceGroups/${local.rg_name}" : azurerm_resource_group.rgwork[0].id
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
          {
            principalId = var.managed_rg_assigned_principal_id
          }
        ]
      }
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

  source = "../private-endpoint"

  random_string       = var.random_string
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

##### Diagnostic Settings for Microsoft-Managed Registry Resources
#####

# Note: Registry managed resources are created by Azure and their resource IDs
# are not immediately available through the azapi_resource output.
# We use null_resource with Azure CLI to configure diagnostic settings after
# the registry and its managed resources are fully provisioned.

# Configure diagnostic settings for Microsoft-managed registry resources
resource "null_resource" "registry_managed_resources_diagnostics" {
  depends_on = [
    azapi_resource.registry,
    time_sleep.wait_registry_identity
  ]

  # Configure diagnostics when the resource is created/updated
  provisioner "local-exec" {
    command = <<-EOT
      $registryName = "${azapi_resource.registry.name}"
  $resourceGroup = "${local.rg_name}"
      $workspaceId = "${var.log_analytics_workspace_id}"
      
      Write-Host "Configuring diagnostic settings for registry managed resources: $registryName"
      
      # Retry until all resources are configured (max 10 minutes)
      $maxAttempts = 20
      $attempt = 1
      $storageAccountConfigured = $false
      $blobConfigured = $false
      $fileConfigured = $false
      $queueConfigured = $false
      $tableConfigured = $false
      $acrConfigured = $false
      
      while (($attempt -le $maxAttempts) -and (-not ($storageAccountConfigured -and $blobConfigured -and $fileConfigured -and $queueConfigured -and $tableConfigured -and $acrConfigured))) {
        Write-Host "Attempt $attempt/$maxAttempts - Checking for managed resources..."
        
        # Configure storage account diagnostics (metrics only)
        if (-not $storageAccountConfigured) {
          # Look for managed resource group following pattern: azureml-rg-{registryName}_{guid}
          $managedRgPattern = "azureml-rg-$registryName"
          $managedRgs = az group list --query "[?starts_with(name, '$managedRgPattern')].name" --output tsv 2>$null
          
          foreach ($rg in $managedRgs) {
            if ($rg) {
              Write-Host "Checking managed resource group: $rg"
              $storage = az storage account list --resource-group $rg --query "[0].id" --output tsv 2>$null
              if ($storage) {
                Write-Host "Found managed storage account: $storage"
                # Storage account only supports metrics, not logs
                az monitor diagnostic-settings create --name "managed-storage-account-diagnostics" --resource $storage --workspace $workspaceId --metrics '[{"category":"Transaction","enabled":true},{"category":"Capacity","enabled":true}]' 2>$null
                if ($LASTEXITCODE -eq 0) { 
                  $storageAccountConfigured = $true
                  Write-Host "✓ Storage account diagnostics configured"
                }
                
                # Configure blob service diagnostics (logs and metrics)
                if (-not $blobConfigured) {
                  $blobService = "$storage/blobServices/default"
                  az monitor diagnostic-settings create --name "managed-blob-diagnostics" --resource $blobService --workspace $workspaceId --logs '[{"category":"StorageRead","enabled":true},{"category":"StorageWrite","enabled":true},{"category":"StorageDelete","enabled":true}]' --metrics '[{"category":"Transaction","enabled":true},{"category":"Capacity","enabled":true}]' 2>$null
                  if ($LASTEXITCODE -eq 0) { 
                    $blobConfigured = $true
                    Write-Host "✓ Blob service diagnostics configured"
                  }
                }
                
                # Configure file service diagnostics (logs and metrics)
                if (-not $fileConfigured) {
                  $fileService = "$storage/fileServices/default"
                  az monitor diagnostic-settings create --name "managed-file-diagnostics" --resource $fileService --workspace $workspaceId --logs '[{"category":"StorageRead","enabled":true},{"category":"StorageWrite","enabled":true},{"category":"StorageDelete","enabled":true}]' --metrics '[{"category":"Transaction","enabled":true},{"category":"Capacity","enabled":true}]' 2>$null
                  if ($LASTEXITCODE -eq 0) { 
                    $fileConfigured = $true
                    Write-Host "✓ File service diagnostics configured"
                  }
                }
                
                # Configure queue service diagnostics (logs and metrics)
                if (-not $queueConfigured) {
                  $queueService = "$storage/queueServices/default"
                  az monitor diagnostic-settings create --name "managed-queue-diagnostics" --resource $queueService --workspace $workspaceId --logs '[{"category":"StorageRead","enabled":true},{"category":"StorageWrite","enabled":true},{"category":"StorageDelete","enabled":true}]' --metrics '[{"category":"Transaction","enabled":true},{"category":"Capacity","enabled":true}]' 2>$null
                  if ($LASTEXITCODE -eq 0) { 
                    $queueConfigured = $true
                    Write-Host "✓ Queue service diagnostics configured"
                  }
                }
                
                # Configure table service diagnostics (logs and metrics)
                if (-not $tableConfigured) {
                  $tableService = "$storage/tableServices/default"
                  az monitor diagnostic-settings create --name "managed-table-diagnostics" --resource $tableService --workspace $workspaceId --logs '[{"category":"StorageRead","enabled":true},{"category":"StorageWrite","enabled":true},{"category":"StorageDelete","enabled":true}]' --metrics '[{"category":"Transaction","enabled":true},{"category":"Capacity","enabled":true}]' 2>$null
                  if ($LASTEXITCODE -eq 0) { 
                    $tableConfigured = $true
                    Write-Host "✓ Table service diagnostics configured"
                  }
                }
                
                break
              }
            }
          }
        }
        
        # Configure ACR diagnostics  
        if (-not $acrConfigured) {
          # Look for managed resource group following pattern: azureml-rg-{registryName}_{guid}
          $managedRgPattern = "azureml-rg-$registryName"
          $managedRgs = az group list --query "[?starts_with(name, '$managedRgPattern')].name" --output tsv 2>$null
          
          foreach ($rg in $managedRgs) {
            if ($rg) {
              $acr = az acr list --resource-group $rg --query "[0].id" --output tsv 2>$null
              if ($acr) {
                Write-Host "Found managed ACR: $acr"
                az monitor diagnostic-settings create --name "managed-acr-diagnostics" --resource $acr --workspace $workspaceId --logs '[{"category":"ContainerRegistryRepositoryEvents","enabled":true},{"category":"ContainerRegistryLoginEvents","enabled":true}]' --metrics '[{"category":"AllMetrics","enabled":true}]' 2>$null
                if ($LASTEXITCODE -eq 0) { 
                  $acrConfigured = $true
                  Write-Host "✓ ACR diagnostics configured"
                  break
                }
              }
            }
          }
        }
        
        if ($storageAccountConfigured -and $blobConfigured -and $fileConfigured -and $queueConfigured -and $tableConfigured -and $acrConfigured) {
          Write-Host "✓ All diagnostics configured successfully"
          break
        }
        
        $attempt++
        if ($attempt -le $maxAttempts) {
          Start-Sleep -Seconds 30
        }
      }
      
      if (-not ($storageAccountConfigured -and $blobConfigured -and $fileConfigured -and $queueConfigured -and $tableConfigured -and $acrConfigured)) {
        Write-Host "⚠ Timeout: Not all diagnostics could be configured"
        exit 1
      }
    EOT

    interpreter = ["PowerShell", "-Command"]
  }

  triggers = {
    registry_id  = azapi_resource.registry.id
    workspace_id = var.log_analytics_workspace_id
  }
}



