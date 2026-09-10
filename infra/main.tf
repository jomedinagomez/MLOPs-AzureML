# Single-Deployment Azure ML Platform
# Complete multi-environment Azure ML platform with proper dependency ordering
# Everything is handled by Terraform without external scripts

terraform {
  required_version = "~> 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.32.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}

# Azure Resource Manager provider
provider "azurerm" {
  subscription_id     = var.subscription_id
  storage_use_azuread = true
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }
}

# Azure API provider for preview features
provider "azapi" {
  subscription_id = var.subscription_id
}

# Get current client configuration
data "azurerm_client_config" "current" {}

# Fixed naming suffix provided via var.naming_suffix

# ===============================
# LOCAL VALUES
# ===============================

locals {
  resource_prefixes = var.resource_prefixes
}

# ===============================
# STEP 1: CREATE ALL RESOURCE GROUPS
# ===============================

# Development Environment Resource Groups
resource "azurerm_resource_group" "dev_vnet_rg" {
  name     = "rg-${var.prefix}-vnet-dev-${var.location_code}-${var.naming_suffix}"
  location = var.location
  tags = merge(var.tags, {
    environment = "development"
    purpose     = "dev"
    component   = "vnet"
  })
}

resource "azurerm_resource_group" "dev_workspace_rg" {
  name     = "rg-${var.prefix}-ws-dev-${var.location_code}-${var.naming_suffix}"
  location = var.location
  tags = merge(var.tags, {
    environment = "development"
    purpose     = "dev"
    component   = "workspace"
  })
}

resource "azurerm_resource_group" "dev_registry_rg" {
  name     = "rg-${var.prefix}-reg-dev-${var.location_code}-${var.naming_suffix}"
  location = var.location
  tags = merge(var.tags, {
    environment = "development"
    purpose     = "dev"
    component   = "registry"
  })
}

# Production Environment Resource Groups
resource "azurerm_resource_group" "prod_vnet_rg" {
  name     = "rg-${var.prefix}-vnet-prod-${var.location_code}-${var.naming_suffix}"
  location = var.location
  tags = merge(var.tags, {
    environment = "production"
    purpose     = "prod"
    component   = "vnet"
  })
}

resource "azurerm_resource_group" "prod_workspace_rg" {
  name     = "rg-${var.prefix}-ws-prod-${var.location_code}-${var.naming_suffix}"
  location = var.location
  tags = merge(var.tags, {
    environment = "production"
    purpose     = "prod"
    component   = "workspace"
  })
}

resource "azurerm_resource_group" "prod_registry_rg" {
  name     = "rg-${var.prefix}-reg-prod-${var.location_code}-${var.naming_suffix}"
  location = var.location
  tags = merge(var.tags, {
    environment = "production"
    purpose     = "prod"
    component   = "registry"
  })
}


# ===============================
# FLAT NETWORK REFACTOR INTRO (no hub) - new shared DNS RG + direct VNets
# ===============================
resource "azurerm_resource_group" "shared_dns_rg" {
  name     = coalesce(var.shared_aml_dns_rg_name, "rg-${var.prefix}-dns-shared-${var.location_code}-${var.naming_suffix}")
  location = var.location
  tags = merge(var.tags, {
    environment = "shared"
    purpose     = "dns"
    component   = "shared-dns"
  })
}

# ===============================
# STEP 4: DEVELOPMENT ENVIRONMENT
# ===============================

## Dev VNet (flat) replacing module for custom subnet layout
resource "azurerm_virtual_network" "dev_vnet" {
  name                = "vnet-${var.prefix}-dev-${var.location_code}-${var.naming_suffix}"
  address_space       = var.dev_vnet_address_space
  location            = var.location
  resource_group_name = azurerm_resource_group.dev_vnet_rg.name
  dns_servers         = var.dns_servers
  tags                = merge(var.tags, { environment = "development", purpose = "dev", component = "vnet" })
}

resource "azurerm_subnet" "dev_pe" {
  name                 = "snet-${var.prefix}-pe-dev-${var.location_code}${var.naming_suffix}"
  resource_group_name  = azurerm_resource_group.dev_vnet_rg.name
  virtual_network_name = azurerm_virtual_network.dev_vnet.name
  address_prefixes     = [var.dev_pe_subnet_prefix]

  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_network_security_group" "dev_pe" {
  name                = "nsg-${var.prefix}-pe-dev-${var.location_code}${var.naming_suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.dev_vnet_rg.name
  tags                = merge(var.tags, { environment = "development", purpose = "private-endpoints" })
}

resource "azurerm_subnet_network_security_group_association" "dev_pe" {
  subnet_id                 = azurerm_subnet.dev_pe.id
  network_security_group_id = azurerm_network_security_group.dev_pe.id
}

# Shared Log Analytics & compute identities (flat network)
resource "azurerm_log_analytics_workspace" "dev_logs" {
  name                = "log-${var.prefix}-dev-${var.location_code}${var.naming_suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.dev_workspace_rg.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = merge(var.tags, { environment = "development", purpose = "logs" })
}

resource "azurerm_log_analytics_workspace" "prod_logs" {
  name                = "log-${var.prefix}-prod-${var.location_code}${var.naming_suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.prod_workspace_rg.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = merge(var.tags, { environment = "production", purpose = "logs" })
}

resource "azurerm_user_assigned_identity" "dev_cc" {
  name                = "dev-mi-compute"
  location            = var.location
  resource_group_name = azurerm_resource_group.dev_workspace_rg.name
  tags                = merge(var.tags, { environment = "development", purpose = "dev", component = "compute-mi" })
}

resource "azurerm_user_assigned_identity" "prod_cc" {
  name                = "prod-mi-compute"
  location            = var.location
  resource_group_name = azurerm_resource_group.prod_workspace_rg.name
  tags                = merge(var.tags, { environment = "production", purpose = "prod", component = "compute-mi" })
}

resource "azurerm_user_assigned_identity" "dev_ci" {
  name                = "dev-mi-compute-instance"
  location            = var.location
  resource_group_name = azurerm_resource_group.dev_workspace_rg.name
  tags                = merge(var.tags, { environment = "development", purpose = "dev", component = "compute-instance-mi" })
}

resource "azurerm_user_assigned_identity" "prod_ci" {
  name                = "prod-mi-compute-instance"
  location            = var.location
  resource_group_name = azurerm_resource_group.prod_workspace_rg.name
  tags                = merge(var.tags, { environment = "production", purpose = "prod", component = "compute-instance-mi" })
}

resource "azurerm_user_assigned_identity" "dev_online_endpoint" {
  name                = "dev-mi-online-endpoint"
  location            = var.location
  resource_group_name = azurerm_resource_group.dev_workspace_rg.name
  tags                = merge(var.tags, { environment = "development", purpose = "dev", component = "online-endpoint-mi" })
}

resource "azurerm_user_assigned_identity" "prod_online_endpoint" {
  name                = "prod-mi-online-endpoint"
  location            = var.location
  resource_group_name = azurerm_resource_group.prod_workspace_rg.name
  tags                = merge(var.tags, { environment = "production", purpose = "prod", component = "online-endpoint-mi" })
}

resource "terraform_data" "validate_dev_cmk_configuration" {
  input = {
    provision_prerequisites = var.dev_provision_cmk_prerequisites
    workspace_encryption    = var.dev_workspace_encryption
  }

  lifecycle {
    precondition {
      condition     = var.dev_workspace_encryption != "cmk" || var.dev_provision_cmk_prerequisites
      error_message = "dev_workspace_encryption can be cmk only when dev_provision_cmk_prerequisites is true."
    }
  }
}

resource "terraform_data" "validate_prod_cmk_configuration" {
  input = {
    provision_prerequisites = var.prod_provision_cmk_prerequisites
    workspace_encryption    = var.prod_workspace_encryption
  }

  lifecycle {
    precondition {
      condition     = var.prod_workspace_encryption != "cmk" || var.prod_provision_cmk_prerequisites
      error_message = "prod_workspace_encryption can be cmk only when prod_provision_cmk_prerequisites is true."
    }
  }
}

# Dev Managed Identity Module
module "dev_managed_umi" {
  source = "./modules/aml-managed-umi"

  prefix                             = var.prefix
  purpose                            = "dev"
  location                           = var.location
  location_code                      = var.location_code
  naming_suffix                      = var.naming_suffix
  resource_prefixes                  = local.resource_prefixes
  resource_group_name                = azurerm_resource_group.dev_workspace_rg.name
  subnet_id                          = azurerm_subnet.dev_pe.id
  log_analytics_workspace_id         = azurerm_log_analytics_workspace.dev_logs.id
  enable_auto_purge                  = var.enable_auto_purge
  key_vault_purge_protection_enabled = var.key_vault_purge_protection_enabled
  sub_id                             = var.subscription_id

  vnet_address_space          = "10.1.0.0/16"
  subnet_address_prefix       = "10.1.1.0/24"
  workload_vnet_location      = var.location
  workload_vnet_location_code = var.location_code
  resource_group_name_dns     = azurerm_resource_group.shared_dns_rg.name

  dns_zone_aml_api_id       = azurerm_private_dns_zone.shared_aml_api.id
  dns_zone_aml_notebooks_id = azurerm_private_dns_zone.shared_aml_notebooks.id
  dns_zone_aml_instances_id = azurerm_private_dns_zone.shared_aml_instances.id
  dns_zone_blob_id          = azurerm_private_dns_zone.shared_blob.id
  dns_zone_file_id          = azurerm_private_dns_zone.shared_file.id
  dns_zone_table_id         = azurerm_private_dns_zone.shared_table.id
  dns_zone_queue_id         = azurerm_private_dns_zone.shared_queue.id
  dns_zone_dfs_id           = azurerm_private_dns_zone.shared_dfs.id
  dns_zone_keyvault_id      = azurerm_private_dns_zone.shared_vault.id
  dns_zone_acr_id           = azurerm_private_dns_zone.shared_acr.id

  compute_cluster_identity_id            = azurerm_user_assigned_identity.dev_cc.id
  compute_cluster_principal_id           = azurerm_user_assigned_identity.dev_cc.principal_id
  compute_instance_identity_id           = azurerm_user_assigned_identity.dev_ci.id
  compute_instance_principal_id          = azurerm_user_assigned_identity.dev_ci.principal_id
  online_endpoint_identity_id            = azurerm_user_assigned_identity.dev_online_endpoint.id
  online_endpoint_principal_id           = azurerm_user_assigned_identity.dev_online_endpoint.principal_id
  online_endpoint_deployer_principal_ids = var.online_endpoint_deployer_principal_ids

  provision_cmk_prerequisites = var.dev_provision_cmk_prerequisites
  workspace_encryption        = var.dev_workspace_encryption
  key_vault_cmk_rbac_enabled  = var.key_vault_cmk_rbac_enabled

  tags = merge(var.tags, {
    environment = "development"
    purpose     = "dev"
  })

  depends_on = [
    azurerm_virtual_network.dev_vnet,
    azurerm_log_analytics_workspace.dev_logs,
    azurerm_user_assigned_identity.dev_cc,
    azurerm_user_assigned_identity.dev_ci,
    azurerm_user_assigned_identity.dev_online_endpoint,
    terraform_data.validate_dev_cmk_configuration
  ]
}

module "dev_registry" {
  source = "./modules/aml-registry-smi"

  prefix              = var.prefix
  purpose             = "dev"
  location            = var.location
  location_code       = var.location_code
  naming_suffix       = var.naming_suffix
  resource_prefixes   = local.resource_prefixes
  resource_group_name = azurerm_resource_group.dev_registry_rg.name

  workload_vnet_location            = var.location
  workload_vnet_location_code       = var.location_code
  resource_group_name_dns           = azurerm_resource_group.shared_dns_rg.name
  subnet_id                         = azurerm_subnet.dev_pe.id
  sub_id                            = var.subscription_id
  log_analytics_workspace_id        = azurerm_log_analytics_workspace.dev_logs.id
  managed_rg_assigned_principal_ids = var.registry_managed_rg_assigned_principal_ids
  dns_zone_aml_api_id               = azurerm_private_dns_zone.shared_aml_api.id
  dns_zone_blob_id                  = azurerm_private_dns_zone.shared_blob.id
  dns_zone_acr_id                   = azurerm_private_dns_zone.shared_acr.id

  tags = merge(var.tags, {
    environment = "development"
    purpose     = "dev"
  })
}

# ===============================
# STEP 5: PRODUCTION ENVIRONMENT
# ===============================

resource "azurerm_virtual_network" "prod_vnet" {
  name                = "vnet-${var.prefix}-prod-${var.location_code}-${var.naming_suffix}"
  address_space       = var.prod_vnet_address_space
  location            = var.location
  resource_group_name = azurerm_resource_group.prod_vnet_rg.name
  dns_servers         = var.dns_servers
  tags                = merge(var.tags, { environment = "production", purpose = "prod", component = "vnet" })
}

resource "azurerm_subnet" "prod_pe" {
  name                 = "snet-${var.prefix}-pe-prod-${var.location_code}${var.naming_suffix}"
  resource_group_name  = azurerm_resource_group.prod_vnet_rg.name
  virtual_network_name = azurerm_virtual_network.prod_vnet.name
  address_prefixes     = [var.prod_pe_subnet_prefix]

  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_network_security_group" "prod_pe" {
  name                = "nsg-${var.prefix}-pe-prod-${var.location_code}${var.naming_suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.prod_vnet_rg.name
  tags                = merge(var.tags, { environment = "production", purpose = "private-endpoints" })
}

resource "azurerm_subnet_network_security_group_association" "prod_pe" {
  subnet_id                 = azurerm_subnet.prod_pe.id
  network_security_group_id = azurerm_network_security_group.prod_pe.id
}

# Optional VNet peering between environments for admin VM access
resource "azurerm_virtual_network_peering" "dev_to_prod" {
  name                      = "dev-to-prod"
  resource_group_name       = azurerm_resource_group.dev_vnet_rg.name
  virtual_network_name      = azurerm_virtual_network.dev_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.prod_vnet.id

  # Tight defaults; do not allow transit or forwarded traffic
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false

  depends_on = [
    azurerm_virtual_network.dev_vnet,
    azurerm_virtual_network.prod_vnet
  ]
}

resource "azurerm_virtual_network_peering" "prod_to_dev" {
  name                      = "prod-to-dev"
  resource_group_name       = azurerm_resource_group.prod_vnet_rg.name
  virtual_network_name      = azurerm_virtual_network.prod_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.dev_vnet.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false

  depends_on = [
    azurerm_virtual_network.dev_vnet,
    azurerm_virtual_network.prod_vnet
  ]
}

# Prod Managed Identity Module
module "prod_managed_umi" {
  source = "./modules/aml-managed-umi"

  prefix                             = var.prefix
  purpose                            = "prod"
  location                           = var.location
  location_code                      = var.location_code
  naming_suffix                      = var.naming_suffix
  resource_prefixes                  = local.resource_prefixes
  resource_group_name                = azurerm_resource_group.prod_workspace_rg.name
  subnet_id                          = azurerm_subnet.prod_pe.id
  log_analytics_workspace_id         = azurerm_log_analytics_workspace.prod_logs.id
  enable_auto_purge                  = var.enable_auto_purge
  key_vault_purge_protection_enabled = var.key_vault_purge_protection_enabled
  sub_id                             = var.subscription_id

  # Network configuration
  vnet_address_space          = "10.2.0.0/16"
  subnet_address_prefix       = "10.2.1.0/24"
  workload_vnet_location      = var.location
  workload_vnet_location_code = var.location_code
  # Use shared DNS RG for consolidated AML private DNS zones
  resource_group_name_dns = azurerm_resource_group.shared_dns_rg.name


  # Use shared AML DNS zones (per-env AML zones disabled in prod_vnet)
  dns_zone_aml_api_id       = azurerm_private_dns_zone.shared_aml_api.id
  dns_zone_aml_notebooks_id = azurerm_private_dns_zone.shared_aml_notebooks.id
  dns_zone_aml_instances_id = azurerm_private_dns_zone.shared_aml_instances.id
  dns_zone_blob_id          = azurerm_private_dns_zone.shared_blob.id
  dns_zone_file_id          = azurerm_private_dns_zone.shared_file.id
  dns_zone_table_id         = azurerm_private_dns_zone.shared_table.id
  dns_zone_queue_id         = azurerm_private_dns_zone.shared_queue.id
  dns_zone_dfs_id           = azurerm_private_dns_zone.shared_dfs.id
  dns_zone_keyvault_id      = azurerm_private_dns_zone.shared_vault.id
  dns_zone_acr_id           = azurerm_private_dns_zone.shared_acr.id

  # Pass compute cluster identity (flat architecture)
  compute_cluster_identity_id            = azurerm_user_assigned_identity.prod_cc.id
  compute_cluster_principal_id           = azurerm_user_assigned_identity.prod_cc.principal_id
  compute_instance_identity_id           = azurerm_user_assigned_identity.prod_ci.id
  compute_instance_principal_id          = azurerm_user_assigned_identity.prod_ci.principal_id
  online_endpoint_identity_id            = azurerm_user_assigned_identity.prod_online_endpoint.id
  online_endpoint_principal_id           = azurerm_user_assigned_identity.prod_online_endpoint.principal_id
  online_endpoint_deployer_principal_ids = var.online_endpoint_deployer_principal_ids

  provision_cmk_prerequisites = var.prod_provision_cmk_prerequisites
  workspace_encryption        = var.prod_workspace_encryption
  key_vault_cmk_rbac_enabled  = var.key_vault_cmk_rbac_enabled

  # Cross-environment configuration for asset promotion (will be applied after dev registry is created)
  # (Removed unused cross-env inputs; RBAC is centralized in this file and no module-level cross-env is used.)

  tags = merge(var.tags, {
    environment = "production"
    purpose     = "prod"
  })

  depends_on = [
    module.dev_registry,
    azurerm_log_analytics_workspace.prod_logs,
    azurerm_user_assigned_identity.prod_cc,
    azurerm_user_assigned_identity.prod_ci,
    azurerm_user_assigned_identity.prod_online_endpoint,
    terraform_data.validate_prod_cmk_configuration
  ]
}


# Prod Registry Module
module "prod_registry" {
  source = "./modules/aml-registry-smi"

  prefix              = var.prefix
  purpose             = "prod"
  location            = var.location
  location_code       = var.location_code
  naming_suffix       = var.naming_suffix
  resource_prefixes   = local.resource_prefixes
  resource_group_name = azurerm_resource_group.prod_registry_rg.name

  # Additional required variables
  workload_vnet_location            = var.location
  workload_vnet_location_code       = var.location_code
  resource_group_name_dns           = azurerm_resource_group.shared_dns_rg.name
  subnet_id                         = azurerm_subnet.prod_pe.id
  sub_id                            = var.subscription_id
  log_analytics_workspace_id        = azurerm_log_analytics_workspace.prod_logs.id
  managed_rg_assigned_principal_ids = var.registry_managed_rg_assigned_principal_ids
  # Provide shared AML API private DNS zone id for registry private endpoint
  dns_zone_aml_api_id = azurerm_private_dns_zone.shared_aml_api.id
  dns_zone_blob_id    = azurerm_private_dns_zone.shared_blob.id
  dns_zone_acr_id     = azurerm_private_dns_zone.shared_acr.id


  tags = merge(var.tags, {
    environment = "production"
    purpose     = "prod"
  })

}

# ===============================
# STEP 6: CROSS-ENVIRONMENT CONNECTIVITY
# ===============================

# Dev compute to dev registry (local environment access)
resource "azurerm_role_assignment" "dev_compute_to_dev_registry" {
  scope                = module.dev_registry.registry_id
  role_definition_name = "AzureML Registry User"
  principal_id         = module.dev_managed_umi.compute_uami_principal_id

  depends_on = [
    module.dev_registry,
    module.dev_managed_umi
  ]
}

# Prod compute to prod registry (local environment access)
resource "azurerm_role_assignment" "prod_compute_to_prod_registry" {
  scope                = module.prod_registry.registry_id
  role_definition_name = "AzureML Registry User"
  principal_id         = module.prod_managed_umi.compute_uami_principal_id

  depends_on = [
    module.prod_registry,
    module.prod_managed_umi
  ]
}

# Network connection approver roles for workspaces to create outbound rules
# Allow dev workspace to create private endpoints to dev registry (local environment)
resource "azurerm_role_assignment" "dev_workspace_network_connection_approver" {
  scope                = module.dev_registry.registry_id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = module.dev_managed_umi.workspace_uami_principal_id

  depends_on = [
    module.dev_registry,
    module.dev_managed_umi
  ]
}

# Allow prod workspace to create private endpoints to prod registry (local environment)
resource "azurerm_role_assignment" "prod_workspace_to_prod_registry_network_approver" {
  scope                = module.prod_registry.registry_id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = module.prod_managed_umi.workspace_uami_principal_id

  depends_on = [
    module.prod_registry,
    module.prod_managed_umi
  ]
}

# Allow prod workspace to create private endpoints to dev registry (cross-environment)
resource "azurerm_role_assignment" "prod_workspace_network_connection_approver" {
  scope                = module.dev_registry.registry_id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = module.prod_managed_umi.workspace_uami_principal_id

  depends_on = [
    module.dev_registry,
    module.prod_managed_umi
  ]
}

# Allow production compute to access dev registry for cross-environment model access
resource "azurerm_role_assignment" "prod_compute_to_dev_registry" {
  scope                = module.dev_registry.registry_id
  role_definition_name = "AzureML Registry User"
  principal_id         = module.prod_managed_umi.compute_uami_principal_id

  depends_on = [
    module.dev_registry,
    module.prod_managed_umi
  ]
}

# Create outbound rule for dev workspace to access dev registry (local environment)
resource "azapi_resource" "dev_workspace_to_dev_registry_outbound_rule" {
  type      = "Microsoft.MachineLearningServices/workspaces/outboundRules@2024-10-01-preview"
  name      = "AllowDevRegistryAccess"
  parent_id = module.dev_managed_umi.workspace_id

  body = {
    properties = {
      type = "PrivateEndpoint"
      destination = {
        serviceResourceId = module.dev_registry.registry_id
        # Required subresourceTarget for registry private endpoint outbound rule
        subresourceTarget = "amlregistry"
      }
      category = "UserDefined"
    }
  }

  depends_on = [
    module.dev_managed_umi,
    module.dev_registry,
    azurerm_role_assignment.dev_workspace_network_connection_approver
  ]
}

# Create outbound rule for prod workspace to access prod registry (local environment)
resource "azapi_resource" "prod_workspace_to_prod_registry_outbound_rule" {
  type      = "Microsoft.MachineLearningServices/workspaces/outboundRules@2024-10-01-preview"
  name      = "AllowProdRegistryAccess"
  parent_id = module.prod_managed_umi.workspace_id

  body = {
    properties = {
      type = "PrivateEndpoint"
      destination = {
        serviceResourceId = module.prod_registry.registry_id
        # Required subresourceTarget for registry private endpoint outbound rule
        subresourceTarget = "amlregistry"
      }
      category = "UserDefined"
    }
  }

  depends_on = [
    module.prod_managed_umi,
    module.prod_registry,
    azurerm_role_assignment.prod_workspace_to_prod_registry_network_approver
  ]
}

# Create outbound rule for production workspace to access dev registry
resource "azapi_resource" "prod_workspace_to_dev_registry_outbound_rule" {
  type      = "Microsoft.MachineLearningServices/workspaces/outboundRules@2024-10-01-preview"
  name      = "AllowDevRegistryAccess"
  parent_id = module.prod_managed_umi.workspace_id

  body = {
    properties = {
      type = "PrivateEndpoint"
      destination = {
        serviceResourceId = module.dev_registry.registry_id
        # Required subresourceTarget for registry private endpoint outbound rule
        subresourceTarget = "amlregistry"
      }
      category = "UserDefined"
    }
  }

  depends_on = [
    module.prod_managed_umi,
    module.dev_registry,
    azurerm_role_assignment.prod_workspace_network_connection_approver
  ]
}

#################################
# SHARED PRIVATE DNS ZONES (FLAT)
#################################

resource "azurerm_private_dns_zone" "shared_aml_api" {
  name                = var.private_dns_zone_names.aml_api
  resource_group_name = azurerm_resource_group.shared_dns_rg.name
  tags                = merge(var.tags, { environment = "shared", scope = "aml-api" })
}

resource "azurerm_private_dns_zone" "shared_aml_notebooks" {
  name                = var.private_dns_zone_names.aml_notebooks
  resource_group_name = azurerm_resource_group.shared_dns_rg.name
  tags                = merge(var.tags, { environment = "shared", scope = "aml-notebooks" })
}

resource "azurerm_private_dns_zone" "shared_aml_instances" {
  name                = var.private_dns_zone_names.aml_instances
  resource_group_name = azurerm_resource_group.shared_dns_rg.name
  tags                = merge(var.tags, { environment = "shared", scope = "aml-instances" })
}

# Centralized wildcard A record for AML workspace compute instances across environments.
# Migrated from per-environment module resource (module.*_managed_umi.azurerm_private_dns_a_record.aml_workspace_compute_instance)
# to avoid duplicate definitions and enable multi-IP record aggregation.
# NOTE: Use the module outputs (workspace_private_endpoint_ip) instead of drilling into the child private endpoint module
# to avoid referencing internal structure and prevent null list values.
locals {
  aml_instances_private_endpoint_ips = distinct(compact([
    try(module.dev_managed_umi.workspace_private_endpoint_ip, null),
    try(module.prod_managed_umi.workspace_private_endpoint_ip, null)
  ]))
}

resource "azurerm_private_dns_a_record" "shared_aml_instances_wildcard" {
  depends_on = [
    azurerm_private_dns_zone.shared_aml_instances,
    module.dev_managed_umi,
    module.prod_managed_umi
  ]
  name                = "*.${var.location}"
  zone_name           = azurerm_private_dns_zone.shared_aml_instances.name
  resource_group_name = azurerm_private_dns_zone.shared_aml_instances.resource_group_name
  ttl                 = var.aml_instances_wildcard_ttl
  records             = local.aml_instances_private_endpoint_ips
}

# ------------------------------------------------------------------
# ADDITIONAL SHARED PRIVATE DNS ZONES (Storage, Key Vault, ACR)
# Needed so prod (and dev) storage, key vault, and container registry
# private endpoints can attach valid zone IDs (prior failure 400 InvalidPrivateDnsZoneIds).
# ------------------------------------------------------------------

resource "azurerm_private_dns_zone" "shared_blob" {
  name                = var.private_dns_zone_names.blob
  resource_group_name = azurerm_resource_group.shared_dns_rg.name
  tags                = merge(var.tags, { environment = "shared", scope = "blob" })
}

resource "azurerm_private_dns_zone" "shared_file" {
  name                = var.private_dns_zone_names.file
  resource_group_name = azurerm_resource_group.shared_dns_rg.name
  tags                = merge(var.tags, { environment = "shared", scope = "file" })
}

resource "azurerm_private_dns_zone" "shared_queue" {
  name                = var.private_dns_zone_names.queue
  resource_group_name = azurerm_resource_group.shared_dns_rg.name
  tags                = merge(var.tags, { environment = "shared", scope = "queue" })
}

resource "azurerm_private_dns_zone" "shared_table" {
  name                = var.private_dns_zone_names.table
  resource_group_name = azurerm_resource_group.shared_dns_rg.name
  tags                = merge(var.tags, { environment = "shared", scope = "table" })
}

resource "azurerm_private_dns_zone" "shared_dfs" {
  name                = var.private_dns_zone_names.dfs
  resource_group_name = azurerm_resource_group.shared_dns_rg.name
  tags                = merge(var.tags, { environment = "shared", scope = "dfs" })
}

resource "azurerm_private_dns_zone" "shared_vault" {
  name                = var.private_dns_zone_names.vault
  resource_group_name = azurerm_resource_group.shared_dns_rg.name
  tags                = merge(var.tags, { environment = "shared", scope = "vaultcore" })
}

resource "azurerm_private_dns_zone" "shared_acr" {
  name                = var.private_dns_zone_names.acr
  resource_group_name = azurerm_resource_group.shared_dns_rg.name
  tags                = merge(var.tags, { environment = "shared", scope = "acr" })
}

// Hub virtual network links removed (flat architecture).

# Dev links
resource "azurerm_private_dns_zone_virtual_network_link" "shared_dev_blob" {
  name                  = "dev-shared-blob"
  resource_group_name   = azurerm_resource_group.shared_dns_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.shared_blob.name
  virtual_network_id    = azurerm_virtual_network.dev_vnet.id
  registration_enabled  = false
  tags                  = merge(var.tags, { environment = "development", scope = "dev-blob-shared" })
}

resource "azurerm_private_dns_zone_virtual_network_link" "shared_dev_file" {
  name                  = "dev-shared-file"
  resource_group_name   = azurerm_resource_group.shared_dns_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.shared_file.name
  virtual_network_id    = azurerm_virtual_network.dev_vnet.id
  registration_enabled  = false
  tags                  = merge(var.tags, { environment = "development", scope = "dev-file-shared" })
}

resource "azurerm_private_dns_zone_virtual_network_link" "shared_dev_queue" {
  name                  = "dev-shared-queue"
  resource_group_name   = azurerm_resource_group.shared_dns_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.shared_queue.name
  virtual_network_id    = azurerm_virtual_network.dev_vnet.id
  registration_enabled  = false
  tags                  = merge(var.tags, { environment = "development", scope = "dev-queue-shared" })
}

resource "azurerm_private_dns_zone_virtual_network_link" "shared_dev_table" {
  name                  = "dev-shared-table"
  resource_group_name   = azurerm_resource_group.shared_dns_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.shared_table.name
  virtual_network_id    = azurerm_virtual_network.dev_vnet.id
  registration_enabled  = false
  tags                  = merge(var.tags, { environment = "development", scope = "dev-table-shared" })
}

resource "azurerm_private_dns_zone_virtual_network_link" "shared_dev_dfs" {
  name                  = "dev-shared-dfs"
  resource_group_name   = azurerm_resource_group.shared_dns_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.shared_dfs.name
  virtual_network_id    = azurerm_virtual_network.dev_vnet.id
  registration_enabled  = false
  tags                  = merge(var.tags, { environment = "development", scope = "dev-dfs-shared" })
}

resource "azurerm_private_dns_zone_virtual_network_link" "shared_dev_vault" {
  name                  = "dev-shared-vault"
  resource_group_name   = azurerm_resource_group.shared_dns_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.shared_vault.name
  virtual_network_id    = azurerm_virtual_network.dev_vnet.id
  registration_enabled  = false
  tags                  = merge(var.tags, { environment = "development", scope = "dev-vault-shared" })
}

resource "azurerm_private_dns_zone_virtual_network_link" "shared_dev_acr" {
  name                  = "dev-shared-acr"
  resource_group_name   = azurerm_resource_group.shared_dns_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.shared_acr.name
  virtual_network_id    = azurerm_virtual_network.dev_vnet.id
  registration_enabled  = false
  tags                  = merge(var.tags, { environment = "development", scope = "dev-acr-shared" })
}

# Prod links
resource "azurerm_private_dns_zone_virtual_network_link" "shared_prod_blob" {
  name                  = "prod-shared-blob"
  resource_group_name   = azurerm_resource_group.shared_dns_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.shared_blob.name
  virtual_network_id    = azurerm_virtual_network.prod_vnet.id
  registration_enabled  = false
  tags                  = merge(var.tags, { environment = "production", scope = "prod-blob-shared" })
}

resource "azurerm_private_dns_zone_virtual_network_link" "shared_prod_file" {
  name                  = "prod-shared-file"
  resource_group_name   = azurerm_resource_group.shared_dns_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.shared_file.name
  virtual_network_id    = azurerm_virtual_network.prod_vnet.id
  registration_enabled  = false
  tags                  = merge(var.tags, { environment = "production", scope = "prod-file-shared" })
}

resource "azurerm_private_dns_zone_virtual_network_link" "shared_prod_queue" {
  name                  = "prod-shared-queue"
  resource_group_name   = azurerm_resource_group.shared_dns_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.shared_queue.name
  virtual_network_id    = azurerm_virtual_network.prod_vnet.id
  registration_enabled  = false
  tags                  = merge(var.tags, { environment = "production", scope = "prod-queue-shared" })
}

resource "azurerm_private_dns_zone_virtual_network_link" "shared_prod_table" {
  name                  = "prod-shared-table"
  resource_group_name   = azurerm_resource_group.shared_dns_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.shared_table.name
  virtual_network_id    = azurerm_virtual_network.prod_vnet.id
  registration_enabled  = false
  tags                  = merge(var.tags, { environment = "production", scope = "prod-table-shared" })
}

resource "azurerm_private_dns_zone_virtual_network_link" "shared_prod_dfs" {
  name                  = "prod-shared-dfs"
  resource_group_name   = azurerm_resource_group.shared_dns_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.shared_dfs.name
  virtual_network_id    = azurerm_virtual_network.prod_vnet.id
  registration_enabled  = false
  tags                  = merge(var.tags, { environment = "production", scope = "prod-dfs-shared" })
}

resource "azurerm_private_dns_zone_virtual_network_link" "shared_prod_vault" {
  name                  = "prod-shared-vault"
  resource_group_name   = azurerm_resource_group.shared_dns_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.shared_vault.name
  virtual_network_id    = azurerm_virtual_network.prod_vnet.id
  registration_enabled  = false
  tags                  = merge(var.tags, { environment = "production", scope = "prod-vault-shared" })
}

resource "azurerm_private_dns_zone_virtual_network_link" "shared_prod_acr" {
  name                  = "prod-shared-acr"
  resource_group_name   = azurerm_resource_group.shared_dns_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.shared_acr.name
  virtual_network_id    = azurerm_virtual_network.prod_vnet.id
  registration_enabled  = false
  tags                  = merge(var.tags, { environment = "production", scope = "prod-acr-shared" })
}

# Initial hub links (add dev/prod links in later migration steps)
// Hub AML zone links removed.

# Spoke (dev) links to shared AML zones (migration Step 1)
resource "azurerm_private_dns_zone_virtual_network_link" "shared_dev_api" {
  name                  = "dev-shared-aml-api"
  resource_group_name   = azurerm_resource_group.shared_dns_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.shared_aml_api.name
  virtual_network_id    = azurerm_virtual_network.dev_vnet.id
  registration_enabled  = false
  tags                  = merge(var.tags, { environment = "development", scope = "dev-aml-api-shared" })
}

resource "azurerm_private_dns_zone_virtual_network_link" "shared_dev_notebooks" {
  name                  = "dev-shared-aml-notebooks"
  resource_group_name   = azurerm_resource_group.shared_dns_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.shared_aml_notebooks.name
  virtual_network_id    = azurerm_virtual_network.dev_vnet.id
  registration_enabled  = false
  tags                  = merge(var.tags, { environment = "development", scope = "dev-aml-notebooks-shared" })
}

resource "azurerm_private_dns_zone_virtual_network_link" "shared_dev_instances" {
  name                  = "dev-shared-aml-instances"
  resource_group_name   = azurerm_resource_group.shared_dns_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.shared_aml_instances.name
  virtual_network_id    = azurerm_virtual_network.dev_vnet.id
  registration_enabled  = false
  tags                  = merge(var.tags, { environment = "development", scope = "dev-aml-instances-shared" })
}

# Spoke (prod) links to shared AML zones (migration Step 1)
resource "azurerm_private_dns_zone_virtual_network_link" "shared_prod_api" {
  name                  = "prod-shared-aml-api"
  resource_group_name   = azurerm_resource_group.shared_dns_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.shared_aml_api.name
  virtual_network_id    = azurerm_virtual_network.prod_vnet.id
  registration_enabled  = false
  tags                  = merge(var.tags, { environment = "production", scope = "prod-aml-api-shared" })
}

resource "azurerm_private_dns_zone_virtual_network_link" "shared_prod_notebooks" {
  name                  = "prod-shared-aml-notebooks"
  resource_group_name   = azurerm_resource_group.shared_dns_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.shared_aml_notebooks.name
  virtual_network_id    = azurerm_virtual_network.prod_vnet.id
  registration_enabled  = false
  tags                  = merge(var.tags, { environment = "production", scope = "prod-aml-notebooks-shared" })
}

resource "azurerm_private_dns_zone_virtual_network_link" "shared_prod_instances" {
  name                  = "prod-shared-aml-instances"
  resource_group_name   = azurerm_resource_group.shared_dns_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.shared_aml_instances.name
  virtual_network_id    = azurerm_virtual_network.prod_vnet.id
  registration_enabled  = false
  tags                  = merge(var.tags, { environment = "production", scope = "prod-aml-instances-shared" })
}

output "shared_aml_dns_zone_ids" {
  value = {
    api       = azurerm_private_dns_zone.shared_aml_api.id
    notebooks = azurerm_private_dns_zone.shared_aml_notebooks.id
    instances = azurerm_private_dns_zone.shared_aml_instances.id
  }
}

/* Hub and spoke peering modules removed in flat architecture */

# ===============================
# STEP 12: HUMAN USER ROLE ASSIGNMENTS (Applied Last, centralized)
# ===============================

locals {
  _user_role_enable = var.assign_user_roles && !var.defer_user_role_assignments
  # All human user (data scientist) workspace + storage roles are centralized here in Step 12.
  # Enable direct workspace/storage role assignments at root to have a single source of truth.
  create_direct_user_ws_sa_roles = true
}

# Barrier to ensure user role assignments run after the rest of the deployment completes
resource "null_resource" "deployment_complete" {
  depends_on = [
    # Core modules that provision AML workspaces, storage and registries
    module.dev_managed_umi,
    module.dev_registry,
    module.prod_managed_umi,
    module.prod_registry,

    # Networking and access components
    azurerm_virtual_network.dev_vnet,
    azurerm_subnet.dev_pe,
    azurerm_virtual_network.prod_vnet,
    azurerm_subnet.prod_pe,

    # Shared AML private DNS zones and links
    azurerm_private_dns_zone.shared_aml_api,
    azurerm_private_dns_zone.shared_aml_notebooks,
    azurerm_private_dns_zone.shared_aml_instances,
    azurerm_private_dns_zone_virtual_network_link.shared_dev_api,
    azurerm_private_dns_zone_virtual_network_link.shared_dev_notebooks,
    azurerm_private_dns_zone_virtual_network_link.shared_dev_instances,
    azurerm_private_dns_zone_virtual_network_link.shared_prod_api,
    azurerm_private_dns_zone_virtual_network_link.shared_prod_notebooks,
    azurerm_private_dns_zone_virtual_network_link.shared_prod_instances
  ]
}

# Development Environment - Human User Role Assignments
resource "azurerm_role_assignment" "user_dev_rg_reader" {
  count                = local._user_role_enable ? 1 : 0
  scope                = azurerm_resource_group.dev_workspace_rg.id
  role_definition_name = "Reader"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [null_resource.deployment_complete]
}

# Human user: Key Vault Administrator on workspace Key Vaults (so the user can manage secrets/certs/keys)
resource "azurerm_role_assignment" "user_dev_kv_admin" {
  count                = local._user_role_enable ? 1 : 0
  scope                = module.dev_managed_umi.keyvault_id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [null_resource.deployment_complete]
}

resource "azurerm_role_assignment" "user_dev_workspace_data_scientist" {
  count                = local._user_role_enable && local.create_direct_user_ws_sa_roles ? 1 : 0
  scope                = module.dev_managed_umi.workspace_id
  role_definition_name = "AzureML Data Scientist"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [null_resource.deployment_complete]
}

resource "azurerm_role_assignment" "user_dev_workspace_ai_developer" {
  count                = local._user_role_enable && local.create_direct_user_ws_sa_roles ? 1 : 0
  scope                = module.dev_managed_umi.workspace_id
  role_definition_name = "Azure AI Developer"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [null_resource.deployment_complete]
}

resource "azurerm_role_assignment" "user_dev_workspace_compute_operator" {
  count                = local._user_role_enable && local.create_direct_user_ws_sa_roles ? 1 : 0
  scope                = module.dev_managed_umi.workspace_id
  role_definition_name = "AzureML Compute Operator"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [null_resource.deployment_complete]
}

resource "azurerm_role_assignment" "user_dev_storage_blob_contributor" {
  count                = local._user_role_enable && local.create_direct_user_ws_sa_roles ? 1 : 0
  scope                = module.dev_managed_umi.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [null_resource.deployment_complete]
}

resource "azurerm_role_assignment" "user_dev_storage_file_privileged_contributor" {
  count                = local._user_role_enable && local.create_direct_user_ws_sa_roles ? 1 : 0
  scope                = module.dev_managed_umi.storage_account_id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [null_resource.deployment_complete]
}

resource "azurerm_role_assignment" "user_dev_storage_table_contributor" {
  count                = local._user_role_enable && local.create_direct_user_ws_sa_roles ? 1 : 0
  scope                = module.dev_managed_umi.storage_account_id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [null_resource.deployment_complete]
}

resource "azurerm_role_assignment" "user_dev_storage_queue_contributor" {
  count                = local._user_role_enable && local.create_direct_user_ws_sa_roles ? 1 : 0
  scope                = module.dev_managed_umi.storage_account_id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [null_resource.deployment_complete]
}

resource "azurerm_role_assignment" "user_dev_registry_user" {
  count                = local._user_role_enable ? 1 : 0
  scope                = module.dev_registry.registry_id
  role_definition_name = "AzureML Registry User"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [null_resource.deployment_complete]
}

# Production Environment - Human User Role Assignments
resource "azurerm_role_assignment" "user_prod_rg_reader" {
  count                = local._user_role_enable ? 1 : 0
  scope                = azurerm_resource_group.prod_workspace_rg.id
  role_definition_name = "Reader"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [null_resource.deployment_complete]
}

resource "azurerm_role_assignment" "user_prod_kv_admin" {
  count                = local._user_role_enable ? 1 : 0
  scope                = module.prod_managed_umi.keyvault_id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [null_resource.deployment_complete]
}

resource "azurerm_role_assignment" "user_prod_workspace_data_scientist" {
  count                = local._user_role_enable && local.create_direct_user_ws_sa_roles ? 1 : 0
  scope                = module.prod_managed_umi.workspace_id
  role_definition_name = "AzureML Data Scientist"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [null_resource.deployment_complete]
}

resource "azurerm_role_assignment" "user_prod_workspace_ai_developer" {
  count                = local._user_role_enable && local.create_direct_user_ws_sa_roles ? 1 : 0
  scope                = module.prod_managed_umi.workspace_id
  role_definition_name = "Azure AI Developer"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [null_resource.deployment_complete]
}

resource "azurerm_role_assignment" "user_prod_workspace_compute_operator" {
  count                = local._user_role_enable && local.create_direct_user_ws_sa_roles ? 1 : 0
  scope                = module.prod_managed_umi.workspace_id
  role_definition_name = "AzureML Compute Operator"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [null_resource.deployment_complete]
}

resource "azurerm_role_assignment" "user_prod_storage_blob_contributor" {
  count                = local._user_role_enable && local.create_direct_user_ws_sa_roles ? 1 : 0
  scope                = module.prod_managed_umi.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [null_resource.deployment_complete]
}

resource "azurerm_role_assignment" "user_prod_storage_file_privileged_contributor" {
  count                = local._user_role_enable && local.create_direct_user_ws_sa_roles ? 1 : 0
  scope                = module.prod_managed_umi.storage_account_id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [null_resource.deployment_complete]
}

resource "azurerm_role_assignment" "user_prod_storage_table_contributor" {
  count                = local._user_role_enable && local.create_direct_user_ws_sa_roles ? 1 : 0
  scope                = module.prod_managed_umi.storage_account_id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [null_resource.deployment_complete]
}

resource "azurerm_role_assignment" "user_prod_storage_queue_contributor" {
  count                = local._user_role_enable && local.create_direct_user_ws_sa_roles ? 1 : 0
  scope                = module.prod_managed_umi.storage_account_id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [null_resource.deployment_complete]
}

resource "azurerm_role_assignment" "user_prod_registry_user" {
  count                = local._user_role_enable ? 1 : 0
  scope                = module.prod_registry.registry_id
  role_definition_name = "AzureML Registry User"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [null_resource.deployment_complete]
}
