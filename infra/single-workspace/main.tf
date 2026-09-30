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

provider "azapi" {
  subscription_id = var.subscription_id
}

data "azurerm_client_config" "current" {}

locals {
  resource_prefixes = var.resource_prefixes
  user_role_enabled = var.assign_user_roles
}

resource "azurerm_resource_group" "workspace" {
  name     = "rg-${var.prefix}-ws-${var.purpose}-${var.location_code}-${var.naming_suffix}"
  location = var.location
  tags = merge(var.tags, {
    environment = var.purpose
    component   = "workspace"
  })
}

resource "azurerm_log_analytics_workspace" "workspace" {
  name                = "log-${var.prefix}-${var.purpose}-${var.location_code}${var.naming_suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.workspace.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags = merge(var.tags, {
    environment = var.purpose
    component   = "monitoring"
  })
}

resource "azurerm_user_assigned_identity" "compute_cluster" {
  name                = "${var.purpose}-mi-compute"
  location            = var.location
  resource_group_name = azurerm_resource_group.workspace.name
  tags = merge(var.tags, {
    environment = var.purpose
    component   = "compute-cluster-identity"
  })
}

resource "azurerm_user_assigned_identity" "compute_instance" {
  name                = "${var.purpose}-mi-compute-instance"
  location            = var.location
  resource_group_name = azurerm_resource_group.workspace.name
  tags = merge(var.tags, {
    environment = var.purpose
    component   = "compute-instance-identity"
  })
}

resource "azurerm_user_assigned_identity" "online_endpoint" {
  name                = "${var.purpose}-mi-online-endpoint"
  location            = var.location
  resource_group_name = azurerm_resource_group.workspace.name
  tags = merge(var.tags, {
    environment = var.purpose
    component   = "online-endpoint-identity"
  })
}

module "workspace" {
  source = "./modules/aml-managed-umi"

  prefix                             = var.prefix
  purpose                            = var.purpose
  location                           = var.location
  location_code                      = var.location_code
  naming_suffix                      = var.naming_suffix
  resource_prefixes                  = local.resource_prefixes
  resource_group_name                = azurerm_resource_group.workspace.name
  log_analytics_workspace_id         = azurerm_log_analytics_workspace.workspace.id
  enable_auto_purge                  = var.enable_auto_purge
  key_vault_purge_protection_enabled = false
  sub_id                             = var.subscription_id
  allowed_public_ip_cidrs            = var.allowed_public_ip_cidrs
  network_profile                    = var.network_profile
  create_compute_resources           = var.create_compute_resources

  compute_cluster_identity_id                    = azurerm_user_assigned_identity.compute_cluster.id
  compute_cluster_principal_id                   = azurerm_user_assigned_identity.compute_cluster.principal_id
  compute_cluster_name                           = var.compute_cluster_name
  compute_cluster_vm_size                        = var.compute_cluster_vm_size
  compute_cluster_min_nodes                      = var.compute_cluster_min_nodes
  compute_cluster_max_nodes                      = var.compute_cluster_max_nodes
  compute_cluster_idle_seconds_before_scale_down = var.compute_cluster_idle_seconds_before_scale_down
  compute_instance_identity_id                   = azurerm_user_assigned_identity.compute_instance.id
  compute_instance_principal_id                  = azurerm_user_assigned_identity.compute_instance.principal_id
  compute_instance_name                          = var.compute_instance_name
  compute_instance_vm_size                       = var.compute_instance_vm_size
  assigned_user_object_id                        = var.assigned_user_object_id
  online_endpoint_identity_id                    = azurerm_user_assigned_identity.online_endpoint.id
  online_endpoint_principal_id                   = azurerm_user_assigned_identity.online_endpoint.principal_id
  online_endpoint_deployer_principal_ids         = var.online_endpoint_deployer_principal_ids
  provision_cmk_prerequisites                    = true
  workspace_encryption                           = "cmk"
  key_vault_cmk_rbac_enabled                     = true

  tags = merge(var.tags, {
    environment = var.purpose
    component   = "azureml"
  })

  depends_on = [
    azurerm_log_analytics_workspace.workspace,
    azurerm_user_assigned_identity.compute_cluster,
    azurerm_user_assigned_identity.compute_instance,
    azurerm_user_assigned_identity.online_endpoint
  ]
}

resource "terraform_data" "deployment_complete" {
  input = {
    workspace_id = module.workspace.workspace_id
  }

  depends_on = [module.workspace]
}

resource "azurerm_role_assignment" "user_resource_group_reader" {
  count                = local.user_role_enabled ? 1 : 0
  scope                = azurerm_resource_group.workspace.id
  role_definition_name = "Reader"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [terraform_data.deployment_complete]
}

resource "azurerm_role_assignment" "user_key_vault_administrator" {
  count                = local.user_role_enabled ? 1 : 0
  scope                = module.workspace.keyvault_id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [terraform_data.deployment_complete]
}

resource "azurerm_role_assignment" "user_workspace_data_scientist" {
  count                = local.user_role_enabled ? 1 : 0
  scope                = module.workspace.workspace_id
  role_definition_name = "AzureML Data Scientist"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [terraform_data.deployment_complete]
}

resource "azurerm_role_assignment" "user_workspace_ai_developer" {
  count                = local.user_role_enabled ? 1 : 0
  scope                = module.workspace.workspace_id
  role_definition_name = "Azure AI Developer"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [terraform_data.deployment_complete]
}

resource "azurerm_role_assignment" "user_workspace_compute_operator" {
  count                = local.user_role_enabled ? 1 : 0
  scope                = module.workspace.workspace_id
  role_definition_name = "AzureML Compute Operator"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [terraform_data.deployment_complete]
}

resource "azurerm_role_assignment" "user_storage_blob_contributor" {
  count                = local.user_role_enabled ? 1 : 0
  scope                = module.workspace.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [terraform_data.deployment_complete]
}

resource "azurerm_role_assignment" "user_storage_file_privileged_contributor" {
  count                = local.user_role_enabled ? 1 : 0
  scope                = module.workspace.storage_account_id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [terraform_data.deployment_complete]
}

resource "azurerm_role_assignment" "user_storage_table_contributor" {
  count                = local.user_role_enabled ? 1 : 0
  scope                = module.workspace.storage_account_id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [terraform_data.deployment_complete]
}

resource "azurerm_role_assignment" "user_storage_queue_contributor" {
  count                = local.user_role_enabled ? 1 : 0
  scope                = module.workspace.storage_account_id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [terraform_data.deployment_complete]
}
