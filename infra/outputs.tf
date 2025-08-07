# Terraform orchestration outputs
# These outputs provide access to key resource information from all modules

###### VNet Module Outputs ######
output "vnet_id" {
  description = "ID of the created Virtual Network"
  value       = module.aml_vnet.vnet_id
}

output "subnet_id" {
  description = "ID of the created subnet"
  value       = module.aml_vnet.subnet_id
}

output "resource_group_name_dns" {
  description = "Name of the DNS resource group"
  value       = module.aml_vnet.resource_group_name_dns
}

output "dns_zone_ids" {
  description = "Map of all DNS zone IDs"
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

output "managed_identity_cc_id" {
  description = "ID of the compute cluster managed identity from VNet module"
  value       = module.aml_vnet.cc_identity_id
}

output "managed_identity_cc_name" {
  description = "Name of the compute cluster managed identity from VNet module"
  value       = module.aml_vnet.cc_identity_name
}

output "managed_identity_cc_principal_id" {
  description = "Principal ID of the compute cluster managed identity from VNet module"
  value       = module.aml_vnet.cc_identity_principal_id
  sensitive   = true
}

output "managed_identity_moe_id" {
  description = "ID of the managed online endpoint identity from VNet module"
  value       = module.aml_vnet.moe_identity_id
}

output "managed_identity_moe_name" {
  description = "Name of the managed online endpoint identity from VNet module"
  value       = module.aml_vnet.moe_identity_name
}

output "managed_identity_moe_principal_id" {
  description = "Principal ID of the managed online endpoint identity from VNet module"
  value       = module.aml_vnet.moe_identity_principal_id
  sensitive   = true
}

###### ML Workspace Module Outputs ######
output "workspace_id" {
  description = "ID of the Azure Machine Learning workspace"
  value       = module.aml_workspace.workspace_id
  sensitive   = false
}

output "workspace_name" {
  description = "Name of the Azure Machine Learning workspace"
  value       = module.aml_workspace.workspace_name
}

output "workspace_principal_id" {
  description = "Principal ID of the Azure ML workspace system-managed identity"
  value       = module.aml_workspace.workspace_principal_id
  sensitive   = true
}

output "workspace_resource_group_name" {
  description = "Resource group name of the ML workspace"
  value       = module.aml_workspace.resource_group_name
}

output "storage_account_name" {
  description = "Name of the storage account associated with the ML workspace"
  value       = module.aml_workspace.storage_account_name
}

output "storage_account_id" {
  description = "ID of the storage account associated with the ML workspace"
  value       = module.aml_workspace.storage_account_id
}

output "keyvault_name" {
  description = "Name of the Key Vault associated with the ML workspace"
  value       = module.aml_workspace.keyvault_name
}

output "keyvault_id" {
  description = "ID of the Key Vault associated with the ML workspace"
  value       = module.aml_workspace.keyvault_id
}

output "container_registry_name" {
  description = "Name of the Container Registry associated with the ML workspace"
  value       = module.aml_workspace.container_registry_name
}

output "container_registry_id" {
  description = "ID of the Container Registry associated with the ML workspace"
  value       = module.aml_workspace.container_registry_id
}

# Note: Application Insights outputs not available in current module
# output "application_insights_name" {
#   description = "Name of the Application Insights associated with the ML workspace"
#   value       = module.aml_workspace.application_insights_name
# }

# output "application_insights_id" {
#   description = "ID of the Application Insights associated with the ML workspace"
#   value       = module.aml_workspace.application_insights_id
# }

# Note: User-assigned managed identity outputs not available in current module
# output "managed_identity_id" {
#   description = "ID of the user-assigned managed identity"
#   value       = module.aml_workspace.managed_identity_id
# }

# output "managed_identity_principal_id" {
#   description = "Principal ID of the user-assigned managed identity"
#   value       = module.aml_workspace.managed_identity_principal_id
#   sensitive   = true
# }

###### ML Registry Module Outputs ######
output "registry_id" {
  description = "ID of the Azure Machine Learning registry"
  value       = module.aml_registry.registry_id
}

output "registry_name" {
  description = "Name of the Azure Machine Learning registry"
  value       = module.aml_registry.registry_name
}

output "registry_resource_group_name" {
  description = "Resource group name of the ML registry"
  value       = module.aml_registry.resource_group_name
}

# Note: Registry storage, keyvault, and container registry outputs not available in current module
# output "registry_storage_account_name" {
#   description = "Name of the storage account associated with the ML registry"
#   value       = module.aml_registry.storage_account_name
# }

# output "registry_keyvault_name" {
#   description = "Name of the Key Vault associated with the ML registry"
#   value       = module.aml_registry.keyvault_name
# }

# output "registry_container_registry_name" {
#   description = "Name of the Container Registry associated with the ML registry"
#   value       = module.aml_registry.container_registry_name
# }

###### Summary Output ######
output "deployment_summary" {
  description = "Summary of all deployed resources"
  value = {
    environment = var.purpose
    location    = var.location
    resources = {
      workspace = {
        name = module.aml_workspace.workspace_name
        id   = module.aml_workspace.workspace_id
      }
      registry = {
        name = module.aml_registry.registry_name
        id   = module.aml_registry.registry_id
      }
      networking = {
        vnet_id   = module.aml_vnet.vnet_id
        subnet_id = module.aml_vnet.subnet_id
      }
    }
  }
}

###### Service Principal Outputs ######
output "service_principal_id" {
  description = "Object ID of the deployment service principal"
  value       = var.create_service_principal ? azuread_service_principal.deployment_sp[0].object_id : null
  sensitive   = true
}

output "service_principal_application_id" {
  description = "Application (client) ID of the deployment service principal"
  value       = var.create_service_principal ? azuread_service_principal.deployment_sp[0].client_id : null
  sensitive   = true
}

output "service_principal_display_name" {
  description = "Display name of the deployment service principal"
  value       = var.create_service_principal ? azuread_service_principal.deployment_sp[0].display_name : null
}

output "service_principal_secret" {
  description = "Client secret for the deployment service principal (expires in 2 years)"
  value       = var.create_service_principal ? azuread_application_password.deployment_sp_secret[0].value : null
  sensitive   = true
}

output "service_principal_secret_id" {
  description = "ID of the service principal secret"
  value       = var.create_service_principal ? azuread_application_password.deployment_sp_secret[0].key_id : null
  sensitive   = true
}

output "service_principal_auth_instructions" {
  description = "Instructions for using the service principal for authentication"
  value = var.create_service_principal ? {
    client_id       = azuread_service_principal.deployment_sp[0].client_id
    tenant_id       = data.azurerm_client_config.current.tenant_id
    subscription_id = data.azurerm_client_config.current.subscription_id
    instructions    = "Use these values to set ARM_CLIENT_ID, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID environment variables. Get the secret from 'service_principal_secret' output."
  } : null
  sensitive = true
}
