##### Outputs
#####

output "workspace_id" {
  description = "ID of the Azure ML workspace"
  value       = azapi_resource.aml_workspace.id
}

output "workspace_name" {
  description = "Name of the Azure ML workspace"
  value       = azapi_resource.aml_workspace.name
}

output "workspace_principal_id" {
  description = "Principal ID of the Azure ML workspace system-managed identity"
  value       = azapi_resource.aml_workspace.output.identity.principalId
}

output "resource_group_name" {
  description = "Name of the resource group containing the AML workspace"
  value       = azurerm_resource_group.rgwork.name
}

output "resource_group_id" {
  description = "ID of the resource group containing the AML workspace"
  value       = azurerm_resource_group.rgwork.id
}

output "storage_account_id" {
  description = "ID of the default storage account"
  value       = module.storage_account_default.id
}

output "storage_account_name" {
  description = "Name of the default storage account"
  value       = module.storage_account_default.name
}

output "keyvault_id" {
  description = "ID of the Key Vault"
  value       = module.keyvault_aml.id
}

output "keyvault_name" {
  description = "Name of the Key Vault"
  value       = module.keyvault_aml.name
}

output "container_registry_id" {
  description = "ID of the Container Registry"
  value       = module.container_registry.id
}

output "container_registry_name" {
  description = "Name of the Container Registry"
  value       = module.container_registry.name
}

output "compute_cluster_uami_id" {
  description = "ID of the CPU compute cluster with user-assigned managed identity"
  value       = azapi_resource.compute_cluster_uami.id
}

output "compute_cluster_uami_name" {
  description = "Name of the CPU compute cluster with user-assigned managed identity"
  value       = azapi_resource.compute_cluster_uami.name
}