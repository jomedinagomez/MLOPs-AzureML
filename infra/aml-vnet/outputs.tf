##### Outputs
#####

output "subnet_id" {
  description = "ID of the AML subnet"
  value       = azurerm_subnet.aml_subnet.id
}

output "cc_identity_id" {
  description = "ID of the compute cluster managed identity"
  value       = azurerm_user_assigned_identity.cc.id
}

output "cc_identity_name" {
  description = "Name of the compute cluster managed identity"
  value       = azurerm_user_assigned_identity.cc.name
}

output "cc_identity_principal_id" {
  description = "Principal ID of the compute cluster managed identity"
  value       = azurerm_user_assigned_identity.cc.principal_id
}

output "moe_identity_id" {
  description = "ID of the managed online endpoint identity"
  value       = azurerm_user_assigned_identity.moe.id
}

output "moe_identity_name" {
  description = "Name of the managed online endpoint identity"
  value       = azurerm_user_assigned_identity.moe.name
}

output "moe_identity_principal_id" {
  description = "Principal ID of the managed online endpoint identity"
  value       = azurerm_user_assigned_identity.moe.principal_id
}

output "resource_group_name" {
  description = "Name of the resource group containing VNet and DNS zones"
  value       = azurerm_resource_group.aml_vnet_rg.name
}

output "resource_group_name_dns" {
  description = "Name of the resource group containing DNS zones (alias for resource_group_name)"
  value       = azurerm_resource_group.aml_vnet_rg.name
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
  description = "Resource ID of the blob storage DNS zone"
  value       = azurerm_private_dns_zone.blob.id
}

output "dns_zone_file_id" {
  description = "Resource ID of the file storage DNS zone"
  value       = azurerm_private_dns_zone.file.id
}

output "dns_zone_table_id" {
  description = "Resource ID of the table storage DNS zone"
  value       = azurerm_private_dns_zone.table.id
}

output "dns_zone_queue_id" {
  description = "Resource ID of the queue storage DNS zone"
  value       = azurerm_private_dns_zone.queue.id
}

output "dns_zone_keyvault_id" {
  description = "Resource ID of the Key Vault DNS zone"
  value       = azurerm_private_dns_zone.keyvault.id
}

output "dns_zone_acr_id" {
  description = "Resource ID of the Container Registry DNS zone"
  value       = azurerm_private_dns_zone.acr.id
}

output "dns_zone_aml_api_id" {
  description = "Resource ID of the Azure ML API DNS zone"
  value       = azurerm_private_dns_zone.aml_api.id
}

output "dns_zone_aml_notebooks_id" {
  description = "Resource ID of the Azure ML Notebooks DNS zone"
  value       = azurerm_private_dns_zone.aml_notebooks.id
}

output "dns_zone_aml_instances_id" {
  description = "Resource ID of the Azure ML Instances DNS zone"
  value       = azurerm_private_dns_zone.aml_instances.id
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
