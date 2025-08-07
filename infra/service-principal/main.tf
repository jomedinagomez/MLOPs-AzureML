# ===========================================
# SERVICE PRINCIPAL CREATION (INDEPENDENT)
# Creates the single service principal before any environment deployment
# This SP will have permissions across all 6 resource groups (3 dev + 3 prod)
# ===========================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.115"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.53"
    }
  }
  required_version = ">= 1.3"
}

# Configure the Azure Provider
provider "azurerm" {
  features {}
}

# Configure the Azure AD Provider
provider "azuread" {}

# Get current client configuration
data "azurerm_client_config" "current" {}

# ===========================================
# SERVICE PRINCIPAL RESOURCES
# ===========================================

# Create Azure AD Application for the service principal
resource "azuread_application" "deployment_sp_app" {
  display_name = "sp-aml-deployment-platform"
  description  = "Service Principal for Azure ML platform deployment automation (all environments)"
  
  owners = [data.azurerm_client_config.current.object_id]

  tags = [
    "Purpose:MLOps-Deployment",
    "ManagedBy:Terraform",
    "Scope:AllEnvironments"
  ]
}

# Create the service principal
resource "azuread_service_principal" "deployment_sp" {
  client_id                    = azuread_application.deployment_sp_app.client_id
  app_role_assignment_required = false
  description                  = "Service Principal for Azure ML platform deployment via Terraform (all environments)"
  
  owners = [data.azurerm_client_config.current.object_id]

  tags = [
    "Purpose:MLOps-Deployment", 
    "ManagedBy:Terraform",
    "Scope:AllEnvironments"
  ]
}

# Create a client secret for the service principal
resource "azuread_application_password" "deployment_sp_secret" {
  application_id = azuread_application.deployment_sp_app.id
  display_name   = "Terraform Deployment Secret - Platform"
  
  # Secret expires in 2 years
  end_date = timeadd(timestamp(), "${var.service_principal_secret_expiry_hours}h")
}

# ===========================================
# RBAC ASSIGNMENTS ACROSS ALL 6 RESOURCE GROUPS
# Per deployment strategy: Contributor + User Access Administrator + Network Contributor
# ===========================================

# Development Environment Resource Groups
data "azurerm_resource_group" "dev_vnet" {
  name = var.dev_vnet_resource_group_name
}

data "azurerm_resource_group" "dev_workspace" {
  name = var.dev_workspace_resource_group_name
}

data "azurerm_resource_group" "dev_registry" {
  name = var.dev_registry_resource_group_name
}

# Production Environment Resource Groups
data "azurerm_resource_group" "prod_vnet" {
  name = var.prod_vnet_resource_group_name
}

data "azurerm_resource_group" "prod_workspace" {
  name = var.prod_workspace_resource_group_name
}

data "azurerm_resource_group" "prod_registry" {
  name = var.prod_registry_resource_group_name
}

# ===========================================
# DEVELOPMENT ENVIRONMENT RBAC
# ===========================================

# Dev VNet Resource Group
resource "azurerm_role_assignment" "sp_contributor_dev_vnet" {
  scope                = data.azurerm_resource_group.dev_vnet.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to deploy dev ML networking infrastructure"
}

resource "azurerm_role_assignment" "sp_user_access_admin_dev_vnet" {
  scope                = data.azurerm_resource_group.dev_vnet.id
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to configure RBAC in dev VNet RG"
}

resource "azurerm_role_assignment" "sp_network_contributor_dev_vnet" {
  scope                = data.azurerm_resource_group.dev_vnet.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to configure dev networking"
}

# Dev Workspace Resource Group
resource "azurerm_role_assignment" "sp_contributor_dev_workspace" {
  scope                = data.azurerm_resource_group.dev_workspace.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to deploy dev ML workspace infrastructure"
}

resource "azurerm_role_assignment" "sp_user_access_admin_dev_workspace" {
  scope                = data.azurerm_resource_group.dev_workspace.id
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to configure RBAC in dev workspace RG"
}

resource "azurerm_role_assignment" "sp_network_contributor_dev_workspace" {
  scope                = data.azurerm_resource_group.dev_workspace.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to configure dev workspace networking"
}

# Dev Registry Resource Group
resource "azurerm_role_assignment" "sp_contributor_dev_registry" {
  scope                = data.azurerm_resource_group.dev_registry.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to deploy dev ML registry infrastructure"
}

resource "azurerm_role_assignment" "sp_user_access_admin_dev_registry" {
  scope                = data.azurerm_resource_group.dev_registry.id
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to configure RBAC in dev registry RG"
}

resource "azurerm_role_assignment" "sp_network_contributor_dev_registry" {
  scope                = data.azurerm_resource_group.dev_registry.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to configure dev registry networking"
}

# ===========================================
# PRODUCTION ENVIRONMENT RBAC
# ===========================================

# Prod VNet Resource Group
resource "azurerm_role_assignment" "sp_contributor_prod_vnet" {
  scope                = data.azurerm_resource_group.prod_vnet.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to deploy prod ML networking infrastructure"
}

resource "azurerm_role_assignment" "sp_user_access_admin_prod_vnet" {
  scope                = data.azurerm_resource_group.prod_vnet.id
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to configure RBAC in prod VNet RG"
}

resource "azurerm_role_assignment" "sp_network_contributor_prod_vnet" {
  scope                = data.azurerm_resource_group.prod_vnet.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to configure prod networking"
}

# Prod Workspace Resource Group
resource "azurerm_role_assignment" "sp_contributor_prod_workspace" {
  scope                = data.azurerm_resource_group.prod_workspace.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to deploy prod ML workspace infrastructure"
}

resource "azurerm_role_assignment" "sp_user_access_admin_prod_workspace" {
  scope                = data.azurerm_resource_group.prod_workspace.id
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to configure RBAC in prod workspace RG"
}

resource "azurerm_role_assignment" "sp_network_contributor_prod_workspace" {
  scope                = data.azurerm_resource_group.prod_workspace.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to configure prod workspace networking"
}

# Prod Registry Resource Group
resource "azurerm_role_assignment" "sp_contributor_prod_registry" {
  scope                = data.azurerm_resource_group.prod_registry.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to deploy prod ML registry infrastructure"
}

resource "azurerm_role_assignment" "sp_user_access_admin_prod_registry" {
  scope                = data.azurerm_resource_group.prod_registry.id
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to configure RBAC in prod registry RG"
}

resource "azurerm_role_assignment" "sp_network_contributor_prod_registry" {
  scope                = data.azurerm_resource_group.prod_registry.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.deployment_sp.object_id
  description          = "Allows sp-aml-deployment-platform to configure prod registry networking"
}
