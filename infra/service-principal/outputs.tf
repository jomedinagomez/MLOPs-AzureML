# ===========================================
# SERVICE PRINCIPAL OUTPUTS
# ===========================================

output "service_principal_object_id" {
  description = "The object ID of the created service principal"
  value       = azuread_service_principal.deployment_sp.object_id
  sensitive   = false
}

output "service_principal_application_id" {
  description = "The application (client) ID of the service principal"
  value       = azuread_service_principal.deployment_sp.client_id
  sensitive   = false
}

output "service_principal_display_name" {
  description = "The display name of the service principal"
  value       = azuread_service_principal.deployment_sp.display_name
  sensitive   = false
}

output "service_principal_client_secret" {
  description = "The client secret for the service principal"
  value       = azuread_application_password.deployment_sp_secret.value
  sensitive   = true
}

output "service_principal_tenant_id" {
  description = "The tenant ID where the service principal was created"
  value       = data.azurerm_client_config.current.tenant_id
  sensitive   = false
}

# ===========================================
# RBAC ASSIGNMENT CONFIRMATION
# ===========================================

output "rbac_assignments_summary" {
  description = "Summary of RBAC assignments created for the service principal"
  value = {
    development_environment = {
      vnet_rg      = data.azurerm_resource_group.dev_vnet.name
      workspace_rg = data.azurerm_resource_group.dev_workspace.name
      registry_rg  = data.azurerm_resource_group.dev_registry.name
    }
    production_environment = {
      vnet_rg      = data.azurerm_resource_group.prod_vnet.name
      workspace_rg = data.azurerm_resource_group.prod_workspace.name
      registry_rg  = data.azurerm_resource_group.prod_registry.name
    }
    roles_assigned = [
      "Contributor",
      "User Access Administrator", 
      "Network Contributor"
    ]
    total_assignments = 18 # 3 roles × 6 resource groups
  }
}
