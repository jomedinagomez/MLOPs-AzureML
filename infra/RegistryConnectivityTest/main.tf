terraform {
  required_version = "~> 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.32.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.13.0"
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
    storage {
      data_plane_available = false
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

locals {
  name = "${var.prefix}-${var.purpose}-${var.location_code}-${var.naming_suffix}"
  resource_prefixes = {
    vnet               = "vnet"
    subnet             = "snet"
    workspace          = "mlw"
    registry           = "mlr"
    storage            = "st"
    container_registry = "acr"
    key_vault          = "kv"
    log_analytics      = "log"
  }
  dns_zones = {
    aml_api       = "privatelink.api.azureml.ms"
    aml_notebooks = "privatelink.notebooks.azure.net"
    aml_instances = "instances.azureml.ms"
    blob          = "privatelink.blob.core.windows.net"
    file          = "privatelink.file.core.windows.net"
    table         = "privatelink.table.core.windows.net"
    queue         = "privatelink.queue.core.windows.net"
    dfs           = "privatelink.dfs.core.windows.net"
    keyvault      = "privatelink.vaultcore.azure.net"
    acr           = "privatelink.azurecr.io"
  }
  owner_roles = {
    project_reader = { scope = azurerm_resource_group.platform.id, role = "Reader" }
    workspace_user = { scope = module.workspace.workspace_id, role = "AzureML Data Scientist" }
    storage_blob   = { scope = module.workspace.storage_account_id, role = "Storage Blob Data Contributor" }
    storage_file   = { scope = module.workspace.storage_account_id, role = "Storage File Data Privileged Contributor" }
    acr_pull       = { scope = module.workspace.container_registry_id, role = "AcrPull" }
  }
}

resource "azurerm_resource_group" "platform" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "workload" {
  name                = "vnet-${local.name}"
  resource_group_name = azurerm_resource_group.platform.name
  location            = var.location
  address_space       = var.vnet_address_space
  tags                = var.tags
}

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "${azurerm_virtual_network.workload.name}-snet-private-endpoints-nsg-${var.location}"
  resource_group_name = azurerm_resource_group.platform.name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_subnet" "private_endpoints" {
  name                              = "snet-private-endpoints"
  resource_group_name               = azurerm_resource_group.platform.name
  virtual_network_name              = azurerm_virtual_network.workload.name
  address_prefixes                  = [var.private_endpoint_subnet_prefix]
  private_endpoint_network_policies = "Enabled"

  depends_on = [azurerm_network_security_group.private_endpoints]
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}

resource "azurerm_private_dns_zone" "service" {
  for_each = local.dns_zones

  name                = each.value
  resource_group_name = azurerm_resource_group.platform.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "workload" {
  for_each = local.dns_zones

  name                  = "${var.purpose}-${each.key}"
  resource_group_name   = azurerm_resource_group.platform.name
  private_dns_zone_name = azurerm_private_dns_zone.service[each.key].name
  virtual_network_id    = azurerm_virtual_network.workload.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_log_analytics_workspace" "workspace" {
  name                = "log-${local.name}"
  resource_group_name = azurerm_resource_group.platform.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "compute" {
  for_each = toset(["cluster", "instance", "online-endpoint"])

  name                = "${var.purpose}-mi-${each.key}"
  resource_group_name = azurerm_resource_group.platform.name
  location            = var.location
  tags                = var.tags
}

module "workspace" {
  source = "../mlops/modules/aml-managed-umi"

  prefix                      = var.prefix
  purpose                     = var.purpose
  location                    = var.location
  location_code               = var.location_code
  naming_suffix               = var.naming_suffix
  resource_prefixes           = local.resource_prefixes
  resource_group_name         = azurerm_resource_group.platform.name
  sub_id                      = var.subscription_id
  log_analytics_workspace_id  = azurerm_log_analytics_workspace.workspace.id
  subnet_id                   = azurerm_subnet.private_endpoints.id
  vnet_address_space          = var.vnet_address_space[0]
  subnet_address_prefix       = var.private_endpoint_subnet_prefix
  workload_vnet_location      = var.location
  workload_vnet_location_code = var.location_code
  resource_group_name_dns     = azurerm_resource_group.platform.name

  dns_zone_aml_api_id       = azurerm_private_dns_zone.service["aml_api"].id
  dns_zone_aml_notebooks_id = azurerm_private_dns_zone.service["aml_notebooks"].id
  dns_zone_aml_instances_id = azurerm_private_dns_zone.service["aml_instances"].id
  dns_zone_blob_id          = azurerm_private_dns_zone.service["blob"].id
  dns_zone_file_id          = azurerm_private_dns_zone.service["file"].id
  dns_zone_table_id         = azurerm_private_dns_zone.service["table"].id
  dns_zone_queue_id         = azurerm_private_dns_zone.service["queue"].id
  dns_zone_dfs_id           = azurerm_private_dns_zone.service["dfs"].id
  dns_zone_keyvault_id      = azurerm_private_dns_zone.service["keyvault"].id
  dns_zone_acr_id           = azurerm_private_dns_zone.service["acr"].id

  compute_cluster_identity_id        = azurerm_user_assigned_identity.compute["cluster"].id
  compute_cluster_principal_id       = azurerm_user_assigned_identity.compute["cluster"].principal_id
  compute_instance_identity_id       = azurerm_user_assigned_identity.compute["instance"].id
  compute_instance_principal_id      = azurerm_user_assigned_identity.compute["instance"].principal_id
  compute_cluster_name               = "cc${var.location_code}${var.naming_suffix}"
  compute_instance_name              = "ci${var.location_code}${var.naming_suffix}"
  online_endpoint_identity_id        = azurerm_user_assigned_identity.compute["online-endpoint"].id
  online_endpoint_principal_id       = azurerm_user_assigned_identity.compute["online-endpoint"].principal_id
  assigned_user_object_id            = var.assigned_user_object_id
  allowed_public_ip_cidrs            = []
  asset_sharing_registry_ids         = []
  enable_legacy_queue_logging        = false
  validate_workspace_schema          = true
  provision_network_now              = false
  provision_cmk_prerequisites        = false
  workspace_encryption               = "pmk"
  enable_auto_purge                  = false
  key_vault_purge_protection_enabled = false
  tags                               = var.tags

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.workload,
    azurerm_subnet_network_security_group_association.private_endpoints,
  ]
}

resource "azurerm_private_dns_a_record" "compute_instances" {
  name                = "*.${var.location}"
  zone_name           = azurerm_private_dns_zone.service["aml_instances"].name
  resource_group_name = azurerm_resource_group.platform.name
  ttl                 = 300
  records             = [module.workspace.workspace_private_endpoint_ip]
}

resource "azurerm_role_assignment" "owner" {
  for_each = local.owner_roles

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = var.assigned_user_object_id
  principal_type       = "User"
}

resource "azurerm_role_assignment" "registry_network_connection_approver" {
  scope                = var.registry_id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = module.workspace.workspace_uami_principal_id
  principal_type       = "ServicePrincipal"
}
