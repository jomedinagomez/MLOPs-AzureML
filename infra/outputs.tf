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
  value       = module.dev_managed_umi.workspace_name
}

output "dev_workspace_id" {
  description = "ID of the development Azure ML workspace"
  value       = module.dev_managed_umi.workspace_id
}

output "dev_registry_name" {
  description = "Name of the development Azure ML registry"
  value       = module.dev_registry.registry_name
}

output "dev_registry_id" {
  description = "ID of the development Azure ML registry"
  value       = module.dev_registry.registry_id
}

output "dev_container_registry_name" {
  description = "Name of the development container registry"
  value       = module.dev_managed_umi.container_registry_name
}

output "dev_key_vault_name" {
  description = "Name of the development key vault"
  value       = module.dev_managed_umi.keyvault_name
}

output "dev_storage_account_name" {
  description = "Name of the development storage account"
  value       = module.dev_managed_umi.storage_account_name
}

output "dev_vnet_id" {
  description = "ID of the development virtual network"
  value       = module.dev_vnet.vnet_id
}

output "dev_subnet_id" {
  description = "ID of the development subnet"
  value       = module.dev_vnet.subnet_id
}

output "dev_workspace_private_endpoint_ip" {
  description = "Private IP of the development workspace private endpoint (for DNS validation)"
  value       = module.dev_managed_umi.workspace_private_endpoint_ip
}

# ===============================
# PRODUCTION ENVIRONMENT OUTPUTS
# ===============================

output "prod_workspace_name" {
  description = "Name of the production Azure ML workspace"
  value       = module.prod_managed_umi.workspace_name
}

output "prod_workspace_id" {
  description = "ID of the production Azure ML workspace"
  value       = module.prod_managed_umi.workspace_id
}

output "prod_registry_name" {
  description = "Name of the production Azure ML registry"
  value       = module.prod_registry.registry_name
}

output "prod_registry_id" {
  description = "ID of the production Azure ML registry"
  value       = module.prod_registry.registry_id
}

output "prod_container_registry_name" {
  description = "Name of the production container registry"
  value       = module.prod_managed_umi.container_registry_name
}

output "prod_key_vault_name" {
  description = "Name of the production key vault"
  value       = module.prod_managed_umi.keyvault_name
}

output "prod_storage_account_name" {
  description = "Name of the production storage account"
  value       = module.prod_managed_umi.storage_account_name
}

output "prod_vnet_id" {
  description = "ID of the production virtual network"
  value       = module.prod_vnet.vnet_id
}

output "prod_subnet_id" {
  description = "ID of the production subnet"
  value       = module.prod_vnet.subnet_id
}

output "prod_workspace_private_endpoint_ip" {
  description = "Private IP of the production workspace private endpoint (for DNS validation)"
  value       = module.prod_managed_umi.workspace_private_endpoint_ip
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
        workspace_endpoint   = "https://${module.dev_managed_umi.workspace_name}.api.azureml.ms"
        registry_endpoint    = "https://${module.dev_registry.registry_name}.registry.azureml.ms"
        container_registry   = "${module.dev_managed_umi.container_registry_name}.azurecr.io"
        key_vault           = "https://${module.dev_managed_umi.keyvault_name}.vault.azure.net"
        storage_account     = "https://${module.dev_managed_umi.storage_account_name}.blob.core.windows.net"
      }
      production = {
        workspace_endpoint   = "https://${module.prod_managed_umi.workspace_name}.api.azureml.ms"
        registry_endpoint    = "https://${module.prod_registry.registry_name}.registry.azureml.ms"
        container_registry   = "${module.prod_managed_umi.container_registry_name}.azurecr.io"
        key_vault           = "https://${module.prod_managed_umi.keyvault_name}.vault.azure.net"
        storage_account     = "https://${module.prod_managed_umi.storage_account_name}.blob.core.windows.net"
      }
    }
    
    resource_naming = {
      pattern      = "[prefix][service][purpose][location_code][naming_suffix]"
      example_dev  = module.dev_managed_umi.workspace_name
      example_prod = module.prod_managed_umi.workspace_name
    }
  }
}

# ===============================
# HUB NETWORK OUTPUTS
# ===============================

output "hub_network_info" {
  description = "Hub network connectivity information"
  sensitive   = true
  value = var.vpn_root_certificate_data != "" ? {
    hub_vnet_id              = module.hub_network.hub_vnet_id
    hub_vnet_address_space   = module.hub_network.hub_vnet_address_space
    vpn_gateway_public_ip    = module.hub_network.vpn_gateway_public_ip
    vpn_client_address_space = module.hub_network.vpn_client_address_space
    connection_info = {
      gateway_address = module.hub_network.vpn_gateway_public_ip
      client_address_pool = module.hub_network.vpn_client_address_space
      dev_vnet_access = "10.1.0.0/16"
      prod_vnet_access = "10.2.0.0/16"
    }
  } : null
}

output "vpn_gateway_public_ip" {
  description = "Public IP address of the VPN Gateway for client configuration"
  sensitive   = true
  value       = var.vpn_root_certificate_data != "" ? module.hub_network.vpn_gateway_public_ip : null
}

# Additional explicit VPN outputs (always exposed for operator readiness)
# These complement the conditional outputs above so that operators can prepare
# VPN client configuration (e.g., exporting profile once root cert is provided)

output "vpn_gateway_id" {
  description = "Resource ID of the VPN Gateway (always exposed)"
  value       = module.hub_network.vpn_gateway_id
}

output "vpn_gateway_fqdn" {
  description = "FQDN of the VPN Gateway (may resolve after provisioning)"
  sensitive   = true
  value       = module.hub_network.vpn_gateway_fqdn
}

output "vpn_client_address_space" {
  description = "Address space reserved for VPN clients"
  value       = module.hub_network.vpn_client_address_space
}

output "vpn_client_profile_ready" {
  description = "Indicates if P2S auth is configured (AzureAD or Certificate)"
  value       = (var.vpn_root_certificate_data != "" || var.azure_ad_p2s_audience != "") ? true : false
  sensitive   = true
}

output "vpn_p2s_auth_method" {
  description = "Configured Point-to-Site authentication method (AzureAD | Certificate | None)"
  value       = module.hub_network.p2s_auth_method
  sensitive   = true
}
