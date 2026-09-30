##### Outputs
#####

output "subnet_id" {
  description = "ID of the AML subnet"
  value       = azurerm_subnet.aml_subnet.id
}

# Removed compute UAMI outputs: compute identity is now created in workspace RG by root

output "resource_group_name" {
  description = "Name of the resource group containing VNet and DNS zones"
  value       = local.rg_name
}

output "resource_group_name_dns" {
  description = "Name of the resource group containing DNS zones (alias for resource_group_name)"
  value       = local.rg_name
}

output "resource_group_id" {
  description = "ID of the resource group containing VNet and DNS zones"
  value       = "/subscriptions/${data.azurerm_client_config.identity_config.subscription_id}/resourceGroups/${local.rg_name}"
}

output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.aml_vnet.id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.aml_vnet.name
}

# DNS Zone Resource IDs (for private endpoint configuration)
output "dns_zone_blob_id" {
  description = "Resource ID of the blob storage DNS zone (null when managed externally)"
  value       = try(azurerm_private_dns_zone.blob[0].id, null)
}

output "dns_zone_file_id" {
  description = "Resource ID of the file storage DNS zone (null when managed externally)"
  value       = try(azurerm_private_dns_zone.file[0].id, null)
}

output "dns_zone_table_id" {
  description = "Resource ID of the table storage DNS zone (null when managed externally)"
  value       = try(azurerm_private_dns_zone.table[0].id, null)
}

output "dns_zone_queue_id" {
  description = "Resource ID of the queue storage DNS zone (null when managed externally)"
  value       = try(azurerm_private_dns_zone.queue[0].id, null)
}

output "dns_zone_keyvault_id" {
  description = "Resource ID of the Key Vault DNS zone (null when managed externally)"
  value       = try(azurerm_private_dns_zone.keyvault[0].id, null)
}

output "dns_zone_acr_id" {
  description = "Resource ID of the Container Registry DNS zone (null when managed externally)"
  value       = try(azurerm_private_dns_zone.acr[0].id, null)
}

output "dns_zone_aml_api_id" {
  description = "Resource ID of the Azure ML API DNS zone (null when managed externally)"
  value       = try(azurerm_private_dns_zone.aml_api[0].id, null)
}

output "dns_zone_aml_notebooks_id" {
  description = "Resource ID of the Azure ML Notebooks DNS zone (null when managed externally)"
  value       = try(azurerm_private_dns_zone.aml_notebooks[0].id, null)
}

output "dns_zone_aml_instances_id" {
  description = "Resource ID of the Azure ML Instances DNS zone (null when managed externally)"
  value       = try(azurerm_private_dns_zone.aml_instances[0].id, null)
}

##### Log Analytics and Monitoring Outputs
#####

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.vnet_logs.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.vnet_logs.name
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.vnet_logs.workspace_id
}
