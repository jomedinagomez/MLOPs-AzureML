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
  value       = azurerm_virtual_network.dev_vnet.id
}

output "dev_subnet_id" {
  description = "ID of the development subnet"
  value       = azurerm_subnet.dev_pe.id
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
  value       = azurerm_virtual_network.prod_vnet.id
}

output "prod_subnet_id" {
  description = "ID of the production subnet"
  value       = azurerm_subnet.prod_pe.id
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
      dev_registry_reader      = "Configured"
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
        purpose               = "dev"
        vnet_address_space    = "10.1.0.0/16"
        subnet_address_prefix = "10.1.1.0/24"
        auto_purge_enabled    = true
        cross_env_rbac        = false
      }
      production = {
        purpose               = "prod"
        vnet_address_space    = "10.2.0.0/16"
        subnet_address_prefix = "10.2.1.0/24"
        auto_purge_enabled    = false
        cross_env_rbac        = true
      }
    }

    key_endpoints = {
      development = {
        workspace_endpoint = "https://${module.dev_managed_umi.workspace_name}.api.azureml.ms"
        registry_endpoint  = "https://${module.dev_registry.registry_name}.registry.azureml.ms"
        container_registry = "${module.dev_managed_umi.container_registry_name}.azurecr.io"
        key_vault          = "https://${module.dev_managed_umi.keyvault_name}.vault.azure.net"
        storage_account    = "https://${module.dev_managed_umi.storage_account_name}.blob.core.windows.net"
      }
      production = {
        workspace_endpoint = "https://${module.prod_managed_umi.workspace_name}.api.azureml.ms"
        registry_endpoint  = "https://${module.prod_registry.registry_name}.registry.azureml.ms"
        container_registry = "${module.prod_managed_umi.container_registry_name}.azurecr.io"
        key_vault          = "https://${module.prod_managed_umi.keyvault_name}.vault.azure.net"
        storage_account    = "https://${module.prod_managed_umi.storage_account_name}.blob.core.windows.net"
      }
    }

    resource_naming = {
      pattern      = "[prefix][service][purpose][location_code][naming_suffix]"
      example_dev  = module.dev_managed_umi.workspace_name
      example_prod = module.prod_managed_umi.workspace_name
    }
    resource_groups = {
      dev_vnet_rg       = azurerm_resource_group.dev_vnet_rg.name
      dev_workspace_rg  = azurerm_resource_group.dev_workspace_rg.name
      dev_registry_rg   = azurerm_resource_group.dev_registry_rg.name
      prod_vnet_rg      = azurerm_resource_group.prod_vnet_rg.name
      prod_workspace_rg = azurerm_resource_group.prod_workspace_rg.name
      prod_registry_rg  = azurerm_resource_group.prod_registry_rg.name
      shared_dns_rg     = azurerm_resource_group.shared_dns_rg.name
    }
    key_vault_security = {
      purge_protection_enabled = var.key_vault_purge_protection_enabled
      auto_purge_enabled       = var.enable_auto_purge
    }
    tags_applied = var.tags
  }
}

# Convenience outputs
output "naming_suffix" {
  description = "Deterministic naming suffix applied to resources"
  value       = var.naming_suffix
}

output "resource_group_names" {
  description = "All core resource group names"
  value = {
    dev_vnet       = azurerm_resource_group.dev_vnet_rg.name
    dev_workspace  = azurerm_resource_group.dev_workspace_rg.name
    dev_registry   = azurerm_resource_group.dev_registry_rg.name
    prod_vnet      = azurerm_resource_group.prod_vnet_rg.name
    prod_workspace = azurerm_resource_group.prod_workspace_rg.name
    prod_registry  = azurerm_resource_group.prod_registry_rg.name
    shared_dns     = azurerm_resource_group.shared_dns_rg.name
  }
}

output "key_vault_purge_protection_enabled" {
  description = "Whether purge protection is enabled on Key Vaults created by the deployment"
  value       = var.key_vault_purge_protection_enabled
}

# ===============================
# HUB NETWORK OUTPUTS
# ===============================

// Hub & VPN outputs removed due to flat network architecture (no hub). If remote access is needed later, introduce a dedicated VPN gateway module and outputs.
output "vpn_gateway_info" {
  description = "VPN Gateway (P2S OpenVPN + Entra ID) info (present only if azure_ad_p2s_audience set)"
  value = var.azure_ad_p2s_audience != "" ? {
    gateway_name        = try(azurerm_virtual_network_gateway.prod_vpn_gw[0].name, null)
    public_ip           = try(azurerm_public_ip.prod_vpn_gw[0].ip_address, null)
    client_address_pool = join(",", var.vpn_client_address_pool)
    auth_method         = "EntraID-OpenVPN"
    audience            = var.azure_ad_p2s_audience
    tenant_id           = coalesce(var.azure_ad_p2s_tenant_id, data.azurerm_client_config.current.tenant_id)
  } : null
}

output "vpn_gateway_public_ip" {
  description = "Public IP address of the VPN gateway (null if gateway not deployed or IP not allocated yet)"
  value       = var.azure_ad_p2s_audience != "" ? try(azurerm_public_ip.prod_vpn_gw[0].ip_address, null) : null
}

# ===============================
# AML PRIVATE ENDPOINT FQDNS (Smoke Test Helpers)
# ===============================
output "dev_private_endpoint_fqdns" {
  description = "Expected private FQDNs (dev) to test DNS and connectivity after deployment"
  value = {
    workspace_api      = "${module.dev_managed_umi.workspace_name}.privatelink.api.azureml.ms"
    key_vault          = "${module.dev_managed_umi.keyvault_name}.vaultcore.azure.net"
    storage_blob       = "${module.dev_managed_umi.storage_account_name}.blob.core.windows.net"
    storage_file       = "${module.dev_managed_umi.storage_account_name}.file.core.windows.net"
    container_registry = "${module.dev_managed_umi.container_registry_name}.azurecr.io"
  }
}

output "prod_private_endpoint_fqdns" {
  description = "Expected private FQDNs (prod) to test DNS and connectivity after deployment"
  value = {
    workspace_api      = "${module.prod_managed_umi.workspace_name}.privatelink.api.azureml.ms"
    key_vault          = "${module.prod_managed_umi.keyvault_name}.vaultcore.azure.net"
    storage_blob       = "${module.prod_managed_umi.storage_account_name}.blob.core.windows.net"
    storage_file       = "${module.prod_managed_umi.storage_account_name}.file.core.windows.net"
    container_registry = "${module.prod_managed_umi.container_registry_name}.azurecr.io"
  }
}
