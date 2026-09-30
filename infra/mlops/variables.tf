# Variables for Single-Deployment Azure ML Platform

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  default     = "5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25"
}

variable "assign_user_roles" {
  description = "Whether to assign roles to the current user (data.azurerm_client_config.current.object_id)"
  type        = bool
  default     = true
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "canadacentral"
}

variable "location_code" {
  description = "Short code for the Azure region"
  type        = string
  default     = "cc"
}

variable "naming_suffix" {
  description = "Required deterministic suffix (e.g. 01, 02a). Always provided; no random generation."
  type        = string
}

variable "tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    project    = "ml-platform"
    created_by = "terraform"
    owner      = "ml-team"
  }
}

variable "prefix" {
  description = "Base prefix for all resource names to ensure uniqueness and consistency"
  type        = string
  default     = "aml"
}

variable "resource_prefixes" {
  description = "Specific prefixes for each resource type"
  type = object({
    vnet               = string
    subnet             = string
    workspace          = string
    registry           = string
    storage            = string
    container_registry = string
    key_vault          = string
    log_analytics      = string
  })
  default = {
    vnet               = "vnet-aml"
    subnet             = "snet-aml"
    dns                = "dns-aml"
    workspace          = "mlw"
    registry           = "mlr"
    storage            = "st"
    container_registry = "acr"
    key_vault          = "kv"
    log_analytics      = "log"
  }
}

variable "shared_aml_dns_rg_name" {
  description = "Optional explicit name for the shared AML private DNS resource group (if null a name is generated)."
  type        = string
  default     = null
}

variable "defer_user_role_assignments" {
  description = "If true, skip immediate user RBAC assignments so they can be applied at the end after core infra succeeds."
  type        = bool
  default     = false
}

########################################
# NETWORK ADDRESS SPACES (PARAMETERIZED)
########################################
variable "dev_vnet_address_space" {
  description = "Address space list for the development VNet"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "dev_pe_subnet_prefix" {
  description = "CIDR prefix for the development private endpoints subnet"
  type        = string
  default     = "10.1.1.0/24"
}

variable "prod_vnet_address_space" {
  description = "Address space list for the production VNet"
  type        = list(string)
  default     = ["10.2.0.0/16"]
}

variable "prod_pe_subnet_prefix" {
  description = "CIDR prefix for the production private endpoints subnet"
  type        = string
  default     = "10.2.1.0/24"
}

variable "dns_servers" {
  description = "List of custom DNS servers to apply to both VNets. Empty uses Azure-provided DNS."
  type        = list(string)
  default     = []
}

#############################
# LOG ANALYTICS CONFIG
#############################
variable "log_analytics_sku" {
  description = "SKU for the shared Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
}

variable "log_analytics_retention_days" {
  description = "Retention (days) for Log Analytics workspace"
  type        = number
  default     = 30
}

#############################
# AML MODULE BEHAVIOR
#############################
variable "enable_auto_purge" {
  description = "Enable auto purge for AML resources where supported"
  type        = bool
  default     = false
}

variable "dev_provision_cmk_prerequisites" {
  description = "Provision development CMK resources while allowing the workspace to remain on PMK"
  type        = bool
  default     = false
}

variable "prod_provision_cmk_prerequisites" {
  description = "Provision production CMK resources while allowing the workspace to remain on PMK"
  type        = bool
  default     = false
}

variable "dev_workspace_encryption" {
  description = "Encryption mode for the development AML workspace"
  type        = string
  default     = "pmk"

  validation {
    condition     = contains(["pmk", "cmk"], var.dev_workspace_encryption)
    error_message = "dev_workspace_encryption must be either pmk or cmk."
  }
}

variable "prod_workspace_encryption" {
  description = "Encryption mode for the production AML workspace"
  type        = string
  default     = "pmk"

  validation {
    condition     = contains(["pmk", "cmk"], var.prod_workspace_encryption)
    error_message = "prod_workspace_encryption must be either pmk or cmk."
  }
}

variable "key_vault_cmk_rbac_enabled" {
  description = "Use Azure RBAC instead of access policies for CMK authorization"
  type        = bool
  default     = true
}

variable "online_endpoint_deployer_principal_ids" {
  description = "Object IDs allowed to attach the environment-specific online endpoint UMI"
  type        = set(string)
  default     = []
}

variable "registry_managed_rg_assigned_principal_ids" {
  description = "Additional principal IDs granted access inside each AML registry managed resource group"
  type        = set(string)
  default     = []
}

variable "enable_data_collection_storage" {
  description = "Provision private ADLS Gen2 storage and AML datastores for managed online endpoint data collection"
  type        = bool
  default     = true
}

variable "data_collection_storage_replication_type" {
  description = "Replication type for the shared data-collection storage account"
  type        = string
  default     = "GRS"
}

########################################
# PRIVATE DNS ZONE NAMES (PARAMETERIZED)
########################################
variable "private_dns_zone_names" {
  description = "Object of private DNS zone names used for AML and dependent services"
  type = object({
    aml_api       = string
    aml_notebooks = string
    aml_instances = string
    blob          = string
    file          = string
    queue         = string
    table         = string
    dfs           = string
    vault         = string
    acr           = string
  })
  default = {
    aml_api       = "privatelink.api.azureml.ms"
    aml_notebooks = "privatelink.notebooks.azure.net"
    aml_instances = "instances.azureml.ms"
    blob          = "privatelink.blob.core.windows.net"
    file          = "privatelink.file.core.windows.net"
    queue         = "privatelink.queue.core.windows.net"
    table         = "privatelink.table.core.windows.net"
    dfs           = "privatelink.dfs.core.windows.net"
    vault         = "privatelink.vaultcore.azure.net"
    acr           = "privatelink.azurecr.io"
  }
}

variable "aml_instances_wildcard_ttl" {
  description = "TTL for AML instances wildcard A record"
  type        = number
  default     = 10
}

#############################
# KEY VAULT SECURITY
#############################
variable "key_vault_purge_protection_enabled" {
  description = "Enable purge protection on workspace Key Vaults."
  type        = bool
  default     = true
}
# End of root input variables.

