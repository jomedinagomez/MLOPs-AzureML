##### Outputs
#####

output "registry_id" {
  description = "ID of the Azure ML registry"
  value       = azapi_resource.registry.id
}

output "registry_name" {
  description = "Name of the Azure ML registry"
  value       = azapi_resource.registry.name
}

output "resource_group_name" {
  description = "Name of the resource group containing the AML registry"
  value       = local.rg_name
}

output "resource_group_id" {
  description = "ID of the resource group containing the AML registry"
  value       = local.rg_id
}

output "managed_storage_account_id" {
  description = "ID of the storage account managed by the Azure ML registry"
  value       = local.managed_storage_account_id
}

output "managed_container_registry_id" {
  description = "ID of the container registry managed by the Azure ML registry"
  value       = local.managed_container_registry_id
}

##### Microsoft-Managed Resources Outputs
#####