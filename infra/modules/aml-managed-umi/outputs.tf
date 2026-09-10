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
  description = "Principal ID of the Azure ML workspace user-assigned managed identity"
  value       = azurerm_user_assigned_identity.workspace_identity.principal_id
}

output "workspace_identity_id" {
  description = "Resource ID of the workspace user-assigned managed identity"
  value       = azurerm_user_assigned_identity.workspace_identity.id
}

output "resource_group_name" {
  description = "Name of the resource group containing the AML workspace"
  value       = var.resource_group_name
}

output "resource_group_id" {
  description = "ID of the resource group containing the AML workspace"
  value       = "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name}"
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

output "compute_instance_uami_id" {
  description = "ID of the compute instance with user-assigned managed identity"
  value       = azapi_resource.compute_instance_uami.id
}

output "compute_instance_uami_name" {
  description = "Name of the compute instance with user-assigned managed identity"
  value       = azapi_resource.compute_instance_uami.name
}

output "image_build_compute_config" {
  description = "Image build compute configuration applied to workspace"
  value       = azapi_update_resource.workspace_image_build_config.body.properties.imageBuildCompute
}

output "workspace_uami_principal_id" {
  description = "Principal ID of the workspace user-assigned managed identity"
  value       = azurerm_user_assigned_identity.workspace_identity.principal_id
}

output "compute_uami_principal_id" {
  description = "Principal ID of the compute user-assigned managed identity"
  value       = var.compute_cluster_principal_id
}

output "compute_cluster_identity_id" {
  description = "Resource ID of the compute cluster user-assigned managed identity"
  value       = var.compute_cluster_identity_id
}

output "compute_instance_identity_id" {
  description = "Resource ID of the compute instance user-assigned managed identity"
  value       = var.compute_instance_identity_id
}

output "compute_instance_principal_id" {
  description = "Principal ID of the compute instance user-assigned managed identity"
  value       = var.compute_instance_principal_id
}

output "online_endpoint_identity_id" {
  description = "Resource ID of the managed online endpoint user-assigned managed identity"
  value       = var.online_endpoint_identity_id
  depends_on  = [time_sleep.wait_online_endpoint_rbac]
}

output "online_endpoint_principal_id" {
  description = "Principal ID of the managed online endpoint user-assigned managed identity"
  value       = var.online_endpoint_principal_id
  depends_on  = [time_sleep.wait_online_endpoint_rbac]
}

output "cmk_key_vault_id" {
  description = "Resource ID of the CMK Key Vault when CMK prerequisites are provisioned"
  value       = try(azurerm_key_vault.cmk[0].id, null)
}

output "cmk_key_id" {
  description = "Resource ID of the customer-managed key when provisioned"
  value       = try(azapi_resource.workspace_cmk[0].id, null)
}

output "cmk_key_uri" {
  description = "Versioned URI of the customer-managed key when provisioned"
  value       = try(azapi_resource.workspace_cmk[0].output.properties.keyUriWithVersion, null)
}

output "storage_encryption_scope_id" {
  description = "Resource ID of the default storage CMK encryption scope when provisioned"
  value       = try(azapi_resource.storage_encryption_scope[0].id, null)
}

# Private endpoint IP for the AML workspace (used for DNS validation / nslookup checks)
output "workspace_private_endpoint_ip" {
  description = "Private IP address of the AML workspace private endpoint"
  value       = module.private_endpoint_aml_workspace.private_endpoint_ip
}