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
  value       = coalesce(
    try(azurerm_resource_group.rgwork[0].id, null),
    "/subscriptions/${data.azurerm_client_config.identity_config.subscription_id}/resourceGroups/${local.rg_name}"
  )
}

##### Microsoft-Managed Resources Outputs
#####