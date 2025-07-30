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
  value       = azurerm_resource_group.rgwork.name
}

##### Microsoft-Managed Resources Outputs
#####