output "resource_group_name" {
  value = azurerm_resource_group.platform.name
}

output "workspace_name" {
  value = module.workspace.workspace_name
}

output "workspace_id" {
  value = module.workspace.workspace_id
}

output "workspace_principal_id" {
  value = module.workspace.workspace_uami_principal_id
}

output "workspace_identity_id" {
  value = module.workspace.workspace_identity_id
}

output "compute_cluster_name" {
  value = module.workspace.compute_cluster_uami_name
}

output "compute_instance_name" {
  value = module.workspace.compute_instance_uami_name
}

output "storage_account_name" {
  value = module.workspace.storage_account_name
}

output "storage_account_id" {
  value = module.workspace.storage_account_id
}

output "key_vault_name" {
  value = module.workspace.keyvault_name
}

output "container_registry_name" {
  value = module.workspace.container_registry_name
}

output "registry_id" {
  value = var.registry_id
}

output "registry_network_approver_assignment_id" {
  value = azurerm_role_assignment.registry_network_connection_approver.id
}
