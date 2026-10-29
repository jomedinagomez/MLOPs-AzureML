output "workspace" {
  description = "Workspace identifiers and retained dependency resources."
  value = {
    id                   = module.workspace.workspace_id
    name                 = module.workspace.workspace_name
    resource_group       = module.workspace.resource_group_name
    identity_id          = module.workspace.workspace_identity_id
    storage_account_name = module.workspace.storage_account_name
    key_vault_name       = module.workspace.keyvault_name
    acr_name             = module.workspace.container_registry_name
  }
}

output "registry" {
  description = "External AML registry and its private backing resources."
  value = {
    id                 = module.registry.registry_id
    name               = module.registry.registry_name
    resource_group     = module.registry.resource_group_name
    storage_account_id = module.registry.managed_storage_account_id
    acr_id             = module.registry.managed_container_registry_id
  }
}

output "network" {
  description = "Customer inbound network, distinct from the workspace AML-managed VNet."
  value = {
    vnet_id                    = azurerm_virtual_network.workload.id
    private_endpoint_subnet_id = azurerm_subnet.private_endpoints.id
    private_endpoint_nsg_id    = azurerm_network_security_group.private_endpoints.id
    private_dns_zone_ids       = { for name, zone in azurerm_private_dns_zone.service : name => zone.id }
  }
}

output "workshop_environment" {
  description = "Copy these identifier values into workshop/.env; do not overwrite existing behavior switches."
  value = {
    AZURE_SUBSCRIPTION_ID               = var.subscription_id
    AZURE_TENANT_ID                     = data.azurerm_client_config.current.tenant_id
    AZURE_RESOURCE_GROUP                = module.workspace.resource_group_name
    AZUREML_WORKSPACE_NAME              = module.workspace.workspace_name
    AZUREML_COMPUTE_NAME                = module.workspace.compute_cluster_uami_name
    AZUREML_COMPUTE_INSTANCE_NAME       = module.workspace.compute_instance_uami_name
    AZUREML_COMPUTE_IDENTITY_CLIENT_ID  = azurerm_user_assigned_identity.compute["cluster"].client_id
    AZUREML_ONLINE_ENDPOINT_IDENTITY_ID = azurerm_user_assigned_identity.compute["online-endpoint"].id
    AZUREML_REGISTRY_NAME               = module.registry.registry_name
  }
}
output "resource_group_name" {
  description = "The single project resource group containing the workspace, registry, compute, networking, and workspace dependencies."
  value       = azurerm_resource_group.platform.name
}
