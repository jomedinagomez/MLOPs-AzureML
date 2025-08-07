# Outputs for Single-Deployment Azure ML Platform
# Clean, purpose-driven outputs for easy troubleshooting and implementation

# ===============================
# SERVICE PRINCIPAL OUTPUTS
# ===============================

output "service_principal_application_id" {
  description = "Application ID of the deployment service principal"
  value       = azuread_application.deployment_sp_app.client_id
}

output "service_principal_object_id" {
  description = "Object ID of the deployment service principal"
  value       = azuread_service_principal.deployment_sp.object_id
}

output "service_principal_display_name" {
  description = "Display name of the deployment service principal"
  value       = azuread_application.deployment_sp_app.display_name
}

# ===============================
# DEVELOPMENT ENVIRONMENT OUTPUTS
# ===============================

output "dev_workspace_name" {
  description = "Name of the development Azure ML workspace"
  value       = azurerm_machine_learning_workspace.dev_workspace.name
}

output "dev_workspace_id" {
  description = "ID of the development Azure ML workspace"
  value       = azurerm_machine_learning_workspace.dev_workspace.id
}

output "dev_registry_name" {
  description = "Name of the development Azure ML registry"
  value       = azurerm_machine_learning_registry.dev_registry.name
}

output "dev_registry_id" {
  description = "ID of the development Azure ML registry"
  value       = azurerm_machine_learning_registry.dev_registry.id
}

output "dev_container_registry_name" {
  description = "Name of the development container registry"
  value       = module.dev_container_registry.container_registry_name
}

output "dev_key_vault_name" {
  description = "Name of the development key vault"
  value       = module.dev_keyvault.key_vault_name
}

output "dev_storage_account_name" {
  description = "Name of the development storage account"
  value       = module.dev_storage_account.storage_account_name
}

output "dev_vnet_id" {
  description = "ID of the development virtual network"
  value       = azurerm_virtual_network.dev_vnet.id
}

output "dev_subnet_id" {
  description = "ID of the development subnet"
  value       = azurerm_subnet.dev_subnet.id
}

# ===============================
# PRODUCTION ENVIRONMENT OUTPUTS
# ===============================

output "prod_workspace_name" {
  description = "Name of the production Azure ML workspace"
  value       = azurerm_machine_learning_workspace.prod_workspace.name
}

output "prod_workspace_id" {
  description = "ID of the production Azure ML workspace"
  value       = azurerm_machine_learning_workspace.prod_workspace.id
}

output "prod_registry_name" {
  description = "Name of the production Azure ML registry"
  value       = azurerm_machine_learning_registry.prod_registry.name
}

output "prod_registry_id" {
  description = "ID of the production Azure ML registry"
  value       = azurerm_machine_learning_registry.prod_registry.id
}

output "prod_container_registry_name" {
  description = "Name of the production container registry"
  value       = module.prod_container_registry.container_registry_name
}

output "prod_key_vault_name" {
  description = "Name of the production key vault"
  value       = module.prod_keyvault.key_vault_name
}

output "prod_storage_account_name" {
  description = "Name of the production storage account"
  value       = module.prod_storage_account.storage_account_name
}

output "prod_vnet_id" {
  description = "ID of the production virtual network"
  value       = azurerm_virtual_network.prod_vnet.id
}

output "prod_subnet_id" {
  description = "ID of the production subnet"
  value       = azurerm_subnet.prod_subnet.id
}

# ===============================
# CROSS-ENVIRONMENT CONNECTIVITY
# ===============================

output "cross_environment_connectivity" {
  description = "Cross-environment connectivity configuration"
  value = {
    dev_to_prod_registry_access = {
      enabled     = true
      description = "Production workspace can pull from development registry"
    }
    prod_workspace_permissions = {
      dev_registry_reader     = "Configured"
      dev_registry_contributor = "Configured for asset promotion"
    }
  }
  sensitive = false
}

# ===============================
# PLATFORM DEPLOYMENT SUMMARY
# ===============================

output "platform_deployment_summary" {
  description = "Complete platform deployment summary with all key information"
  value = {
    deployment_timestamp = timestamp()
    terraform_version    = "~> 1.0"
    region               = var.location
    region_code          = var.location_code
    
    environments_deployed = ["development", "production"]
    
    service_principal = {
      name           = azuread_application.deployment_sp_app.display_name
      application_id = azuread_application.deployment_sp_app.client_id
    }
    
    environment_config = {
      development = {
        purpose              = "dev"
        vnet_address_space   = "10.1.0.0/16"
        subnet_address_prefix = "10.1.1.0/24"
        auto_purge_enabled   = true
        cross_env_rbac       = false
      }
      production = {
        purpose              = "prod"
        vnet_address_space   = "10.2.0.0/16"
        subnet_address_prefix = "10.2.1.0/24"
        auto_purge_enabled   = false
        cross_env_rbac       = true
      }
    }
    
    key_endpoints = {
      development = {
        workspace_endpoint   = "https://${azurerm_machine_learning_workspace.dev_workspace.name}.api.azureml.ms"
        registry_endpoint    = "https://${azurerm_machine_learning_registry.dev_registry.name}.registry.azureml.ms"
        container_registry   = "${module.dev_container_registry.container_registry_name}.azurecr.io"
        key_vault           = "https://${module.dev_keyvault.key_vault_name}.vault.azure.net"
        storage_account     = "https://${module.dev_storage_account.storage_account_name}.blob.core.windows.net"
      }
      production = {
        workspace_endpoint   = "https://${azurerm_machine_learning_workspace.prod_workspace.name}.api.azureml.ms"
        registry_endpoint    = "https://${azurerm_machine_learning_registry.prod_registry.name}.registry.azureml.ms"
        container_registry   = "${module.prod_container_registry.container_registry_name}.azurecr.io"
        key_vault           = "https://${module.prod_keyvault.key_vault_name}.vault.azure.net"
        storage_account     = "https://${module.prod_storage_account.storage_account_name}.blob.core.windows.net"
      }
    }
    
    resource_naming = {
      pattern      = "[prefix][service][purpose][location_code][random_string]"
      example_dev  = azurerm_machine_learning_workspace.dev_workspace.name
      example_prod = azurerm_machine_learning_workspace.prod_workspace.name
    }
  }
}
