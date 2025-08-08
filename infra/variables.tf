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

## Point-to-Site VPN (Entra ID OpenVPN) Configuration
# If azure_ad_p2s_audience is non-empty a Virtual Network Gateway + P2S config is created.
variable "azure_ad_p2s_audience" {
  description = "Application (client) ID of the Entra ID (Azure AD) 'Server App' used as audience for P2S AAD auth. Leave empty to disable the VPN gateway."
  type        = string
  default     = ""
}

variable "azure_ad_p2s_tenant_id" {
  description = "Tenant ID to use for Entra ID P2S VPN auth. Defaults to current context tenant when null."
  type        = string
  default     = null
}

variable "vpn_client_address_pool" {
  description = "List of IPv4 CIDR blocks handed out to VPN clients. Must not overlap any VNet address space."
  type        = list(string)
  default     = ["10.255.0.0/24"]
  validation {
    condition = alltrue([
      for cidr in var.vpn_client_address_pool : !contains(["10.1.0.0/16", "10.2.0.0/16"], cidr)
    ])
    error_message = "vpn_client_address_pool entries must not equal existing VNet CIDRs (10.1.0.0/16, 10.2.0.0/16)."
  }
}

variable "user_object_id" {
  description = "The object ID of the user who will manage the Azure Machine Learning Workspace"
  type        = string
  default     = null
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

variable "prod_gateway_subnet_prefix" {
  description = "CIDR prefix for the production GatewaySubnet"
  type        = string
  default     = "10.2.0.0/24"
}

variable "prod_pe_subnet_prefix" {
  description = "CIDR prefix for the production private endpoints subnet"
  type        = string
  default     = "10.2.1.0/24"
}

variable "dns_servers" {
  description = "List of custom DNS servers to apply to both VNets (defaults to Azure-provided wire server)."
  type        = list(string)
  default     = ["168.63.129.16"]
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
  default     = true
}

########################################
# VPN GATEWAY SETTINGS
########################################
variable "vpn_gateway_sku" {
  description = "SKU for the Virtual Network Gateway when created"
  type        = string
  default     = "VpnGw1"
}

variable "vpn_gateway_generation" {
  description = "Gateway generation (Generation1 or Generation2)"
  type        = string
  default     = "Generation1"
}

variable "vpn_public_ip_sku" {
  description = "Public IP SKU for VPN gateway"
  type        = string
  default     = "Basic"
}

variable "vpn_public_ip_allocation_method" {
  description = "Allocation method for VPN public IP"
  type        = string
  default     = "Dynamic"
}

variable "vpn_gateway_private_ip_allocation_method" {
  description = "Private IP allocation method for VPN gateway configuration"
  type        = string
  default     = "Dynamic"
}

variable "vpn_client_protocols" {
  description = "Protocols enabled for VPN clients"
  type        = list(string)
  default     = ["OpenVPN"]
}

########################################
# PRIVATE DNS ZONE NAMES (PARAMETERIZED)
########################################
variable "private_dns_zone_names" {
  description = "Object of private DNS zone names used for AML and dependent services"
  type = object({
    aml_api      = string
    aml_notebooks = string
    aml_instances = string
    blob         = string
    file         = string
    queue        = string
    table        = string
    vault        = string
    acr          = string
  })
  default = {
    aml_api       = "privatelink.api.azureml.ms"
    aml_notebooks = "privatelink.notebooks.azure.net"
    aml_instances = "instances.azureml.ms"
    blob          = "privatelink.blob.core.windows.net"
    file          = "privatelink.file.core.windows.net"
    queue         = "privatelink.queue.core.windows.net"
    table         = "privatelink.table.core.windows.net"
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
  description = "Enable Key Vault purge protection (should be true in production to prevent immediate purge). For sandbox/dev keep false so soft-deleted vaults can be purged automatically."
  type        = bool
  default     = false
}
