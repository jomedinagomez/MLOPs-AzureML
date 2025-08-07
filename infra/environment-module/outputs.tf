# Environment Module Outputs with Purpose Context
# These outputs include environment purpose for easier troubleshooting and implementation
# Output names and descriptions help identify which environment resources belong to

###### VNet Module Outputs ######
output "vnet_id" {
  description = "ID of the environment Virtual Network (purpose determined by module instantiation)"
  value       = module.aml_vnet.vnet_id
}

output "subnet_id" {
  description = "ID of the environment subnet (purpose determined by module instantiation)"
  value       = module.aml_vnet.subnet_id
}

output "resource_group_name_dns" {
  description = "Name of the environment DNS resource group (purpose determined by module instantiation)"
  value       = module.aml_vnet.resource_group_name_dns
}

###### Workspace Module Outputs ######
output "workspace_id" {
  description = "ID of the environment Azure ML workspace (purpose determined by module instantiation)"
  value       = module.aml_workspace.workspace_id
}

output "workspace_name" {
  description = "Name of the environment Azure ML workspace (purpose determined by module instantiation)"
  value       = module.aml_workspace.workspace_name
}

output "workspace_principal_id" {
  description = "Principal ID of the environment workspace system-managed identity (purpose determined by module instantiation)"
  value       = module.aml_workspace.workspace_principal_id
  sensitive   = true
}

output "workspace_resource_group_id" {
  description = "ID of the environment workspace resource group (purpose determined by module instantiation)"
  value       = module.aml_workspace.resource_group_id
}

output "workspace_resource_group_name" {
  description = "Name of the environment workspace resource group (purpose determined by module instantiation)"
  value       = module.aml_workspace.resource_group_name
}

output "storage_account_id" {
  description = "ID of the environment workspace storage account (purpose determined by module instantiation)"
  value       = module.aml_workspace.storage_account_id
}

output "storage_account_name" {
  description = "Name of the environment workspace storage account (purpose determined by module instantiation)"
  value       = module.aml_workspace.storage_account_name
}

output "container_registry_id" {
  description = "ID of the environment workspace container registry (purpose determined by module instantiation)"
  value       = module.aml_workspace.container_registry_id
}

output "container_registry_name" {
  description = "Name of the environment workspace container registry (purpose determined by module instantiation)"
  value       = module.aml_workspace.container_registry_name
}

output "key_vault_id" {
  description = "ID of the environment workspace key vault (purpose determined by module instantiation)"
  value       = module.aml_workspace.keyvault_id
}

output "key_vault_name" {
  description = "Name of the environment workspace key vault (purpose determined by module instantiation)"
  value       = module.aml_workspace.keyvault_name
}

###### Registry Module Outputs ######
output "registry_id" {
  description = "ID of the environment Azure ML registry (purpose determined by module instantiation)"
  value       = module.aml_registry.registry_id
}

output "registry_name" {
  description = "Name of the environment Azure ML registry (purpose determined by module instantiation)"
  value       = module.aml_registry.registry_name
}

output "registry_resource_group_id" {
  description = "ID of the environment registry resource group (purpose determined by module instantiation)"
  value       = module.aml_registry.resource_group_id
}

output "registry_resource_group_name" {
  description = "Name of the environment registry resource group (purpose determined by module instantiation)"
  value       = module.aml_registry.resource_group_name
}

###### Managed Identities ######
output "managed_identity_cc_id" {
  description = "ID of the environment compute cluster managed identity (purpose determined by module instantiation)"
  value       = module.aml_vnet.cc_identity_id
}

output "managed_identity_cc_name" {
  description = "Name of the environment shared compute managed identity (used by both cluster and compute instance)"
  value       = module.aml_vnet.cc_identity_name
}

###### Log Analytics ######
output "log_analytics_workspace_id" {
  description = "ID of the environment Log Analytics workspace (purpose determined by module instantiation)"
  value       = module.aml_vnet.log_analytics_workspace_id
}

output "log_analytics_workspace_name" {
  description = "Name of the environment Log Analytics workspace (purpose determined by module instantiation)"
  value       = module.aml_vnet.log_analytics_workspace_name
}

###### DNS Zones ######
output "dns_zone_ids" {
  description = "Map of all environment DNS zone IDs (purpose determined by module instantiation)"
  value = {
    blob          = module.aml_vnet.dns_zone_blob_id
    file          = module.aml_vnet.dns_zone_file_id
    table         = module.aml_vnet.dns_zone_table_id
    queue         = module.aml_vnet.dns_zone_queue_id
    keyvault      = module.aml_vnet.dns_zone_keyvault_id
    acr           = module.aml_vnet.dns_zone_acr_id
    aml_api       = module.aml_vnet.dns_zone_aml_api_id
    aml_notebooks = module.aml_vnet.dns_zone_aml_notebooks_id
  }
}
