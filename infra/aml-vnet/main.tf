resource "azurerm_resource_group" "aml_vnet_rg" {
  name     = "${local.vnet_resource_group_prefix}${var.purpose}${var.location_code}${var.random_string}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "aml_vnet" {
  name                = "${local.vnet_prefix}${var.purpose}${var.location_code}${var.random_string}"
  address_space       = [var.vnet_address_space]
  location            = azurerm_resource_group.aml_vnet_rg.location
  resource_group_name = azurerm_resource_group.aml_vnet_rg.name
  tags                = var.tags
}

resource "azurerm_subnet" "aml_subnet" {
  name                 = "${local.subnet_prefix}${var.purpose}${var.location_code}${var.random_string}"
  resource_group_name  = azurerm_resource_group.aml_vnet_rg.name
  virtual_network_name = azurerm_virtual_network.aml_vnet.name
  address_prefixes     = [var.subnet_address_prefix]
}


output "subnet_id" {
  value = azurerm_subnet.aml_subnet.id
}


# Managed Identity for Compute Cluster

resource "azurerm_user_assigned_identity" "cc" {
  name                = "${var.purpose}-mi-cluster"
  location            = var.location
  resource_group_name = azurerm_resource_group.aml_vnet_rg.name
  tags                = var.tags
}

# Managed Identity for Managed Online Endpoint

resource "azurerm_user_assigned_identity" "moe" {
  name                = "${var.purpose}-mi-endpoint"
  location            = var.location
  resource_group_name = azurerm_resource_group.aml_vnet_rg.name
  tags                = var.tags
}

output "cc_identity_id" {
  value = azurerm_user_assigned_identity.cc.id
}

output "moe_identity_id" {
  value = azurerm_user_assigned_identity.moe.id
}

##### Private DNS Zones for Azure ML and supporting services
#####

# Storage Account Private DNS Zones
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.aml_vnet_rg.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "file" {
  name                = "privatelink.file.core.windows.net"
  resource_group_name = azurerm_resource_group.aml_vnet_rg.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "table" {
  name                = "privatelink.table.core.windows.net"
  resource_group_name = azurerm_resource_group.aml_vnet_rg.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "queue" {
  name                = "privatelink.queue.core.windows.net"
  resource_group_name = azurerm_resource_group.aml_vnet_rg.name
  tags                = var.tags
}

# Key Vault Private DNS Zone
resource "azurerm_private_dns_zone" "keyvault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.aml_vnet_rg.name
  tags                = var.tags
}

# Container Registry Private DNS Zone
resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.aml_vnet_rg.name
  tags                = var.tags
}

# Azure ML Workspace Private DNS Zones
resource "azurerm_private_dns_zone" "aml_api" {
  name                = "privatelink.api.azureml.ms"
  resource_group_name = azurerm_resource_group.aml_vnet_rg.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "aml_notebooks" {
  name                = "privatelink.notebooks.azure.net"
  resource_group_name = azurerm_resource_group.aml_vnet_rg.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "aml_instances" {
  name                = "instances.azureml.ms"
  resource_group_name = azurerm_resource_group.aml_vnet_rg.name
  tags                = var.tags
}

##### VNet Links for Private DNS Zones
#####

resource "azurerm_private_dns_zone_virtual_network_link" "blob_link" {
  name                  = "blob-vnet-link"
  resource_group_name   = azurerm_resource_group.aml_vnet_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.aml_vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "file_link" {
  name                  = "file-vnet-link"
  resource_group_name   = azurerm_resource_group.aml_vnet_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.file.name
  virtual_network_id    = azurerm_virtual_network.aml_vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "table_link" {
  name                  = "table-vnet-link"
  resource_group_name   = azurerm_resource_group.aml_vnet_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.table.name
  virtual_network_id    = azurerm_virtual_network.aml_vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "queue_link" {
  name                  = "queue-vnet-link"
  resource_group_name   = azurerm_resource_group.aml_vnet_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.queue.name
  virtual_network_id    = azurerm_virtual_network.aml_vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault_link" {
  name                  = "keyvault-vnet-link"
  resource_group_name   = azurerm_resource_group.aml_vnet_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = azurerm_virtual_network.aml_vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr_link" {
  name                  = "acr-vnet-link"
  resource_group_name   = azurerm_resource_group.aml_vnet_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = azurerm_virtual_network.aml_vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aml_api_link" {
  name                  = "aml-api-vnet-link"
  resource_group_name   = azurerm_resource_group.aml_vnet_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.aml_api.name
  virtual_network_id    = azurerm_virtual_network.aml_vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aml_notebooks_link" {
  name                  = "aml-notebooks-vnet-link"
  resource_group_name   = azurerm_resource_group.aml_vnet_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.aml_notebooks.name
  virtual_network_id    = azurerm_virtual_network.aml_vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aml_instances_link" {
  name                  = "aml-instances-vnet-link"
  resource_group_name   = azurerm_resource_group.aml_vnet_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.aml_instances.name
  virtual_network_id    = azurerm_virtual_network.aml_vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

##### Outputs for other modules to reference
#####

output "resource_group_name" {
  description = "Name of the resource group containing VNet and DNS zones"
  value       = azurerm_resource_group.aml_vnet_rg.name
}

output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.aml_vnet.id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.aml_vnet.name
}

# DNS Zone Resource IDs (for private endpoint configuration)
output "dns_zone_blob_id" {
  description = "Resource ID of the blob storage DNS zone"
  value       = azurerm_private_dns_zone.blob.id
}

output "dns_zone_file_id" {
  description = "Resource ID of the file storage DNS zone"
  value       = azurerm_private_dns_zone.file.id
}

output "dns_zone_table_id" {
  description = "Resource ID of the table storage DNS zone"
  value       = azurerm_private_dns_zone.table.id
}

output "dns_zone_queue_id" {
  description = "Resource ID of the queue storage DNS zone"
  value       = azurerm_private_dns_zone.queue.id
}

output "dns_zone_keyvault_id" {
  description = "Resource ID of the Key Vault DNS zone"
  value       = azurerm_private_dns_zone.keyvault.id
}

output "dns_zone_acr_id" {
  description = "Resource ID of the Container Registry DNS zone"
  value       = azurerm_private_dns_zone.acr.id
}

output "dns_zone_aml_api_id" {
  description = "Resource ID of the Azure ML API DNS zone"
  value       = azurerm_private_dns_zone.aml_api.id
}

output "dns_zone_aml_notebooks_id" {
  description = "Resource ID of the Azure ML Notebooks DNS zone"
  value       = azurerm_private_dns_zone.aml_notebooks.id
}

output "dns_zone_aml_instances_id" {
  description = "Resource ID of the Azure ML Instances DNS zone"
  value       = azurerm_private_dns_zone.aml_instances.id
}
