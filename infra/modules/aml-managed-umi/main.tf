##### Data Sources
#####

## Get current client configuration for compute instance assignment
data "azurerm_client_config" "current" {}

##### Resource Group Context (passed from root)
#####

locals {
  rg_name = var.resource_group_name
  rg_id   = "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name}"
  resolved_suffix = coalesce(var.naming_suffix, "")
}

## Create a Log Analytics Workspace where resources in this deployment will send their diagnostic logs
##

##### Create resources required by AML workspace
#####

## Create Application Insights for AML Workspace
##
resource "azurerm_application_insights" "aml-appins" {
  name                = "${local.app_insights_prefix}${var.purpose}${var.location_code}${local.resolved_suffix}"
  location            = var.location
  resource_group_name = local.rg_name
  workspace_id        = var.log_analytics_workspace_id
  name                = "${local.app_insights_prefix}${var.purpose}${var.location_code}${local.resolved_suffix}"
  application_type    = "other"
}

## Create the Container Registry for the Azure Machine Learning workspace
##
module "container_registry" {
  source              = "../container-registry"
  prefix              = var.prefix
  resource_prefixes   = var.resource_prefixes
  purpose             = var.purpose
  naming_suffix       = local.resolved_suffix
  location            = var.location
  location_code       = var.location_code
  resource_group_name = local.rg_name
  law_resource_id     = var.log_analytics_workspace_id
  enable_auto_purge   = var.enable_auto_purge

  tags = var.tags
}

## Create storage account which will be default storage account for AML Workspace
##
module "storage_account_default" {

  source              = "../storage-account"
  prefix              = var.prefix
  resource_prefixes   = var.resource_prefixes
  purpose             = var.purpose
  naming_suffix       = local.resolved_suffix
  location            = var.location
  location_code       = var.location_code
  resource_group_name = local.rg_name
  tags                = var.tags

  # Identity controls
  key_based_authentication = true

  # Networking controls
  allow_blob_public_access = false
  network_access_default   = "Deny"
  network_trusted_services_bypass = [
    "AzureServices"
  ]
  resource_access = [
    {
      endpoint_resource_id = "/subscriptions/${var.sub_id}/resourcegroups/*/providers/Microsoft.MachineLearningServices/workspaces/*"
    }
  ]
  law_resource_id = var.log_analytics_workspace_id

  # Enable auto-purge for dev/test environments
  enable_auto_purge = var.enable_auto_purge
}

## Create Key Vault which will hold secrets for the AML workspace and assign user the Key Vault Administrator role over it
##
module "keyvault_aml" {

  source              = "../key-vault"
  prefix              = var.prefix
  resource_prefixes   = var.resource_prefixes
  naming_suffix       = local.resolved_suffix
  location            = var.location
  location_code       = var.location_code
  resource_group_name = local.rg_name
  purpose             = var.purpose
  law_resource_id     = var.log_analytics_workspace_id
  tags                = var.tags

  kv_admin_object_id = var.user_object_id

  firewall_default_action = "Deny"
  firewall_bypass         = "AzureServices"

  # Enable auto-purge for dev/test environments
  enable_auto_purge = var.enable_auto_purge
}

##### Create the Azure Machine Learning Workspace and its child resources
#####

## Create User-Assigned Managed Identity for the workspace
## This will replace the system-assigned managed identity
##
resource "azurerm_user_assigned_identity" "workspace_identity" {
  name                = "${var.purpose}-mi-workspace"
  location            = var.location
  resource_group_name = local.rg_name
  tags                = var.tags
}

## Create the Azure Machine Learning Workspace in a managed vnet configuration
##
resource "azapi_resource" "aml_workspace" {
  depends_on = [
    azurerm_application_insights.aml-appins,
    module.storage_account_default,
    module.keyvault_aml,
    module.container_registry,
    azurerm_user_assigned_identity.workspace_identity
  ]

  type                      = "Microsoft.MachineLearningServices/workspaces@2025-04-01-preview"
  name                      = "${local.aml_workspace_prefix}${var.purpose}${var.location_code}${local.resolved_suffix}"
  parent_id                 = local.rg_id
  location                  = var.location
  schema_validation_enabled = false

  body = {

    # Create the AML Workspace with a user-assigned managed identity
    identity = {
      type = "UserAssigned"
      userAssignedIdentities = {
        "${azurerm_user_assigned_identity.workspace_identity.id}" = {}
      }
    }

    # Create a non hub-based AML workspace
    kind = "Default"

    properties = {
      description = "Azure Machine Learning Workspace for testing"

      # The version of the managed network model to use; unsure what v2 is
      managedNetworkKind = "V1"
  name                      = "${local.aml_workspace_prefix}${var.purpose}${var.location_code}${local.resolved_suffix}"
      # The resources that will be associated with the AML Workspace
      applicationInsights = azurerm_application_insights.aml-appins.id
      keyVault            = module.keyvault_aml.id
      storageAccount      = module.storage_account_default.id
      containerRegistry   = module.container_registry.id

      # Block access to the AML Workspace over the public endpoint
      publicNetworkAccess = "disabled"

      # Configure the AML workspace to use the managed virtual network model
      managedNetwork = {
        # Managed virtual network will block all outbound traffic unless explicitly allowed
        isolationMode = "AllowOnlyApprovedOutbound"
        # Use Azure Firewall Standard SKU to support FQDN-based rules
        firewallSku = "Standard"

        # Create a series of outbound rules to allow access to other private endpoints and FQDNs on the Internet
        outboundRules = {
          # Create required FQDN rules to support usage of Python package managers such as pip and conda
          AllowPypi = {
            type        = "FQDN"
            destination = "pypi.org"
            category    = "UserDefined"
          }
          AllowPythonHostedWildcard = {
            type        = "FQDN"
            destination = "*.pythonhosted.org"
            category    = "UserDefined"
          }
          AllowAnacondaCom = {
            type        = "FQDN"
            destination = "anaconda.com"
            category    = "UserDefined"
          }
          AllowAnacondaComWildcard = {
            type        = "FQDN"
            destination = "*.anaconda.com"
            category    = "UserDefined"
          }
          AllowAnacondaOrgWildcard = {
            type        = "FQDN"
            destination = "*.anaconda.org"
            category    = "UserDefined"
          }
          # Create fqdn rules to allow for pulling Docker images like Python, Jupyter, and other images
          AllowDockerIo = {
            type        = "FQDN"
            destination = "docker.io"
            category    = "UserDefined"
          }
          AllowDockerIoWildcard = {
            type        = "FQDN"
            destination = "*.docker.io"
            category    = "UserDefined"
          }
          AllowDockerComWildcard = {
            type        = "FQDN"
            destination = "*.docker.com"
            category    = "UserDefined"
          }
          AllowDockerCloudFlareProduction = {
            type        = "FQDN"
            destination = "production.cloudflare.docker.com"
            category    = "UserDefined"
          }

          # Create fqdn rules to allow for using models from HuggingFace
          AllowCdnAuth0Com = {
            type        = "FQDN"
            destination = "cdn.auth0.com"
            category    = "UserDefined"
          }
          AllowCdnHuggingFaceCo = {
            type        = "FQDN"
            destination = "cdn-lfs.huggingface.co"
            category    = "UserDefined"
          }

          # Create fqdn rules to support usage of SSH to compute instances in a managed virtual network from Visual Studio Code
          AllowVsCodeDevWildcard = {
            type        = "FQDN"
            destination = "*.vscode.dev"
            category    = "UserDefined"
          }
          AllowVsCodeBlob = {
            type        = "FQDN"
            destination = "vscode.blob.core.windows.net"
            category    = "UserDefined"
          }
          AllowGalleryCdnWildcard = {
            type        = "FQDN"
            destination = "*.gallerycdn.vsassets.io"
            category    = "UserDefined"
          }
          AllowRawGithub = {
            type        = "FQDN"
            destination = "raw.githubusercontent.com"
            category    = "UserDefined"
          }
          AllowVsCodeUnpkWildcard = {
            type        = "FQDN"
            destination = "*.vscode-unpkg.net"
            category    = "UserDefined"
          }
          AllowVsCodeCndWildcard = {
            type        = "FQDN"
            destination = "*.vscode-cdn.net"
            category    = "UserDefined"
          }
          AllowVsCodeExperimentsWildcard = {
            type        = "FQDN"
            destination = "*.vscodeexperiments.azureedge.net"
            category    = "UserDefined"
          }
          AllowDefaultExpTas = {
            type        = "FQDN"
            destination = "default.exp-tas.com"
            category    = "UserDefined"
          }
          AllowCodeVisualStudio = {
            type        = "FQDN"
            destination = "code.visualstudio.com"
            category    = "UserDefined"
          }
          AllowUpdateCodeVisualStudio = {
            type        = "FQDN"
            destination = "update.code.visualstudio.com"
            category    = "UserDefined"
          }
          AllowVsMsecndNet = {
            type        = "FQDN"
            destination = "*.vo.msecnd.net"
            category    = "UserDefined"
          }
          AllowMarketplaceVisualStudio = {
            type        = "FQDN"
            destination = "marketplace.visualstudio.com"
            category    = "UserDefined"
          }
          AllowVsCodeDownload = {
            type        = "FQDN"
            destination = "vscode.download.prss.microsoft.com"
            category    = "UserDefined"
          }

          # Cross-environment connectivity rules for asset promotion
          # Allow connectivity to Azure ML services in other regions for cross-environment operations
          AllowAzureMLWildcard = {
            type        = "FQDN"
            destination = "*.ml.azure.com"
            category    = "UserDefined"
          }
          AllowAzureMLApiWildcard = {
            type        = "FQDN"
            destination = "*.azureml.net"
            category    = "UserDefined"
          }
          AllowAzureMLStudioWildcard = {
            type        = "FQDN"
            destination = "*.azureml.ms"
            category    = "UserDefined"
          }
          # Allow connectivity to Azure Resource Manager for cross-subscription operations
          AllowAzureResourceManager = {
            type        = "FQDN"
            destination = "management.azure.com"
            category    = "UserDefined"
          }
        }
      }
      # Allow the platform to grant the SMI for the workspace AI Administrator on the resource group the AML workspace
      # is deployed to.
      allowRoleAssignmentOnRG = true
      # The default storage account associated with AML workspace will use Entra ID for authentication instad of storage access keys
      systemDatastoresAuthMode = "identity"
      # Create the manage virtual network for the AML workspace upon creation vs waiting for the first compute resource to be created
      provisionNetworkNow = true
    }

    tags = var.tags
  }
  # No longer exporting identity.principalId since we're using user-assigned identity
  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

##### Create a Private Endpoints workspace required resources including default storage account
##### Key Vault, and Container Registry

## Create Private Endpoints in the customer virtual network for default storage account for blob and file, 
## Key Vault, and Container Registry
module "private_endpoint_st_default_blob" {
  depends_on = [
    module.storage_account_default
  ]

  source              = "../private-endpoint"
  naming_suffix       = local.resolved_suffix
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = local.rg_name
  tags                = var.tags

  resource_name    = module.storage_account_default.name
  resource_id      = module.storage_account_default.id
  subresource_name = "blob"

  subnet_id            = var.subnet_id
  private_dns_zone_ids = [local.dns_zone_blob_id]
}

module "private_endpoint_st_default_file" {
  depends_on = [
    module.private_endpoint_st_default_blob
  ]

  source              = "../private-endpoint"
  naming_suffix       = local.resolved_suffix
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = local.rg_name
  tags                = var.tags

  resource_name    = module.storage_account_default.name
  resource_id      = module.storage_account_default.id
  subresource_name = "file"

  subnet_id            = var.subnet_id
  private_dns_zone_ids = [local.dns_zone_file_id]
}

module "private_endpoint_st_default_table" {
  depends_on = [
    module.private_endpoint_st_default_file
  ]

  source              = "../private-endpoint"
  naming_suffix       = local.resolved_suffix
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = local.rg_name
  tags                = var.tags

  resource_name    = module.storage_account_default.name
  resource_id      = module.storage_account_default.id
  subresource_name = "table"

  subnet_id            = var.subnet_id
  private_dns_zone_ids = [local.dns_zone_table_id]
}

module "private_endpoint_st_default_queue" {
  depends_on = [
    module.private_endpoint_st_default_table
  ]

  source              = "../private-endpoint"
  naming_suffix       = local.resolved_suffix
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = local.rg_name
  tags                = var.tags

  resource_name    = module.storage_account_default.name
  resource_id      = module.storage_account_default.id
  subresource_name = "queue"

  subnet_id            = var.subnet_id
  private_dns_zone_ids = [local.dns_zone_queue_id]
}

module "private_endpoint_kv" {
  depends_on = [
    module.private_endpoint_st_default_queue
  ]

  source              = "../private-endpoint"
  naming_suffix       = local.resolved_suffix
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = local.rg_name
  tags                = var.tags

  resource_name    = module.keyvault_aml.name
  resource_id      = module.keyvault_aml.id
  subresource_name = "vault"


  subnet_id            = var.subnet_id
  private_dns_zone_ids = [local.dns_zone_keyvault_id]
}

module "private_endpoint_container_registry" {
  depends_on = [
    module.private_endpoint_kv
  ]

  source              = "../private-endpoint"
  naming_suffix       = local.resolved_suffix
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = local.rg_name
  tags                = var.tags

  resource_name    = module.container_registry.name
  resource_id      = module.container_registry.id
  subresource_name = "registry"

  subnet_id            = var.subnet_id
  private_dns_zone_ids = [local.dns_zone_acr_id]
}

##### Create Private Endpoint for AML Workspace and the A record for the AML Workspace compute instances
#####

## Create Private Endpoint for AML Workspace
##
module "private_endpoint_aml_workspace" {
  depends_on = [
    module.private_endpoint_container_registry
  ]

  source              = "../private-endpoint"
  naming_suffix       = local.resolved_suffix
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = local.rg_name
  tags                = var.tags

  resource_name    = azapi_resource.aml_workspace.name
  resource_id      = azapi_resource.aml_workspace.id
  subresource_name = "amlworkspace"

  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    local.dns_zone_aml_api_id,
    local.dns_zone_aml_notebooks_id
  ]
}

## Create the A record for the AML Workspace compute instances
##
resource "azurerm_private_dns_a_record" "aml_workspace_compute_instance" {
  depends_on = [
    module.private_endpoint_aml_workspace
  ]

  name                = "*.${var.location}"
  zone_name           = "instances.azureml.ms"
  resource_group_name = var.resource_group_name_dns
  ttl                 = 10
  records = [
    module.private_endpoint_aml_workspace.private_endpoint_ip
  ]
}

##### Create non-human role assignments
#####

resource "time_sleep" "wait_aml_workspace_identities" {
  depends_on = [
    azapi_resource.aml_workspace,
    azurerm_user_assigned_identity.workspace_identity
  ]
  create_duration = "10s"
}

## Create role assignments granting Reader role over the resource group to AML Workspace's
## user-assigned managed identity
resource "azurerm_role_assignment" "rg_reader" {
  depends_on = [
    time_sleep.wait_aml_workspace_identities
  ]
  name                 = uuidv5("dns", "${local.rg_name}${azurerm_user_assigned_identity.workspace_identity.principal_id}reader")
  scope                = local.rg_id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.workspace_identity.principal_id
}

## Create role assignments granting Azure AI Enterprise Network Connection Approver role over the resource group to the AML Workspace's
## user-assigned managed identity
resource "azurerm_role_assignment" "ai_network_connection_approver" {
  depends_on = [
    azurerm_role_assignment.rg_reader
  ]
  name                 = uuidv5("dns", "${local.rg_name}${azurerm_user_assigned_identity.workspace_identity.principal_id}netapprover")
  scope                = local.rg_id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = azurerm_user_assigned_identity.workspace_identity.principal_id
}

## Create role assignments granting Azure AI Administrator role over the resource group to the AML Workspace's
## user-assigned managed identity - Required for image creation and registry operations
resource "azurerm_role_assignment" "ai_administrator" {
  depends_on = [
    azurerm_role_assignment.ai_network_connection_approver
  ]
  name                 = uuidv5("dns", "${local.rg_name}${azurerm_user_assigned_identity.workspace_identity.principal_id}aiadmin")
  scope                = local.rg_id
  role_definition_name = "Azure AI Administrator"
  principal_id         = azurerm_user_assigned_identity.workspace_identity.principal_id
}

##### Create human role assignments
#####

## Create Azure RBAC Role Assignment granting the Azure AI Developer Role to the user.
## This allows the user to deploy models from the catalog to serverless compute resources
##
resource "azurerm_role_assignment" "wk_perm_ai_developer" {
  depends_on = [
    azapi_resource.aml_workspace
  ]
  name                 = uuidv5("dns", "${local.rg_name}${var.user_object_id}${azapi_resource.aml_workspace.name}aidev")
  scope                = azapi_resource.aml_workspace.id
  role_definition_name = "Azure AI Developer"
  principal_id         = var.user_object_id
}

## Create Azure RBAC Role Assignment granting the Azure Machine Learning Compute Operator role to the user.
## This allows the user to perform all actions on compute resources within the workspace.
##
resource "azurerm_role_assignment" "wk_perm_compute_operator" {
  depends_on = [
    azapi_resource.aml_workspace
  ]
  name                 = uuidv5("dns", "${local.rg_name}${var.user_object_id}${azapi_resource.aml_workspace.name}computeoperator")
  scope                = azapi_resource.aml_workspace.id
  role_definition_name = "AzureML Compute Operator"
  principal_id         = var.user_object_id
}

## Create Azure RBAC Role Assignment granting the Azure Machine Learning Data Scientist role to the user.
## This allows the user to perform all actions except for creating compute resources.
##
resource "azurerm_role_assignment" "wk_perm_data_scientist" {
  depends_on = [
    azapi_resource.aml_workspace
  ]
  name                 = uuidv5("dns", "${local.rg_name}${var.user_object_id}${azapi_resource.aml_workspace.name}datascientist")
  scope                = azapi_resource.aml_workspace.id
  role_definition_name = "AzureML Data Scientist"
  principal_id         = var.user_object_id
}

## Create role assignments for the data scientist granting them the Storage Blob Data Contributor and Storage File Data Privileged Contributor roles
## over the default storage account
##
resource "azurerm_role_assignment" "blob_perm_default_sa" {
  name                 = uuidv5("dns", "${local.rg_name}${var.user_object_id}${module.storage_account_default.name}blob")
  scope                = module.storage_account_default.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.user_object_id
}

resource "azurerm_role_assignment" "file_perm_default_sa" {
  name                 = uuidv5("dns", "${local.rg_name}${var.user_object_id}${module.storage_account_default.name}file")
  scope                = module.storage_account_default.id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = var.user_object_id
}

##### Cross-environment RBAC for asset promotion (centralized in parent module)
#####
# Intentionally removed module-level cross-environment role assignments to avoid duplication and drift.
# Cross-environment RBAC is now managed centrally in infra/main.tf.

##### Create compute cluster role assignments
#####

## Use the compute cluster managed identity passed from the VNet module
## The managed identity IDs are always passed from the parent module
##
locals {
  # Use the managed identity values passed from the VNet module
  compute_cluster_identity_id  = var.compute_cluster_identity_id
  compute_cluster_principal_id = var.compute_cluster_principal_id
}

## Assign AzureML Data Scientist role to compute identity for the workspace
## This allows compute clusters to perform ML operations within the workspace
##
resource "azurerm_role_assignment" "compute_ml_data_scientist" {
  depends_on = [
    azapi_resource.aml_workspace
  ]

  name                 = uuidv5("dns", "${local.rg_name}${local.compute_cluster_principal_id}mldatascientist")
  scope                = azapi_resource.aml_workspace.id # Individual workspace resource
  role_definition_name = "AzureML Data Scientist"
  principal_id         = local.compute_cluster_principal_id
}

## Assign Key Vault Secrets User role to compute identity for workspace Key Vault
## This allows compute clusters to access secrets needed for training
##
resource "azurerm_role_assignment" "compute_keyvault_secrets_user" {
  depends_on = [
    module.keyvault_aml
  ]

  name                 = uuidv5("dns", "${local.rg_name}${local.compute_cluster_principal_id}${module.keyvault_aml.name}secretsuser")
  scope                = module.keyvault_aml.id # Individual Key Vault resource
  role_definition_name = "Key Vault Secrets User"
  principal_id         = local.compute_cluster_principal_id
}

## Assign Storage Blob Data Contributor role to compute identity for workspace storage
## This allows compute clusters to read/write training data and model artifacts
##
resource "azurerm_role_assignment" "compute_storage_blob_contributor" {
  depends_on = [
    module.storage_account_default
  ]

  name                 = uuidv5("dns", "${local.rg_name}${local.compute_cluster_principal_id}${module.storage_account_default.name}blobcontrib")
  scope                = module.storage_account_default.id # Individual storage account resource
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = local.compute_cluster_principal_id
}

## Assign Storage File Data Privileged Contributor role to compute identity for workspace storage
## This allows compute instances using this managed identity to access workspace file shares and notebooks
##
resource "azurerm_role_assignment" "compute_storage_file_privileged_contributor" {
  depends_on = [
    module.storage_account_default
  ]

  name                 = uuidv5("dns", "${local.rg_name}${local.compute_cluster_principal_id}${module.storage_account_default.name}filepriv")
  scope                = module.storage_account_default.id # Individual storage account resource
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = local.compute_cluster_principal_id
}

## Assign AcrPull role to compute identity for workspace container registry
## This allows compute clusters to pull base images for ML training and inference environments
##
resource "azurerm_role_assignment" "compute_acr_pull" {
  depends_on = [
    module.container_registry
  ]

  name                 = uuidv5("dns", "${local.rg_name}${local.compute_cluster_principal_id}${module.container_registry.name}acrpull")
  scope                = module.container_registry.id # Individual ACR resource
  role_definition_name = "AcrPull"
  principal_id         = local.compute_cluster_principal_id
}

## Assign AcrPush role to compute identity for workspace container registry
## This allows compute clusters to build and store custom training environments and inference images
##
resource "azurerm_role_assignment" "compute_acr_push" {
  depends_on = [
    azurerm_role_assignment.compute_acr_pull
  ]

  name                 = uuidv5("dns", "${local.rg_name}${local.compute_cluster_principal_id}${module.container_registry.name}acrpush")
  scope                = module.container_registry.id # Individual ACR resource
  role_definition_name = "AcrPush"
  principal_id         = local.compute_cluster_principal_id
}

## Assign Contributor role to compute identity for the workspace
## This enables automatic shutdown of idle compute instances
##
resource "azurerm_role_assignment" "compute_workspace_contributor" {
  depends_on = [
    azapi_resource.aml_workspace
  ]

  name                 = uuidv5("dns", "${local.rg_name}${local.compute_cluster_principal_id}${azapi_resource.aml_workspace.name}contributor")
  scope                = azapi_resource.aml_workspace.id # Individual workspace resource
  role_definition_name = "Contributor"
  principal_id         = local.compute_cluster_principal_id
}

## Assign Reader role to compute identity for the resource group
## This allows compute clusters to discover resources during pipeline execution
##
resource "azurerm_role_assignment" "compute_rg_reader" {
  depends_on = [
    azapi_resource.aml_workspace
  ]

  name                 = uuidv5("dns", "${local.rg_name}${local.compute_cluster_principal_id}reader")
  scope                = local.rg_id # Resource group scope
  role_definition_name = "Reader"
  principal_id         = local.compute_cluster_principal_id
}

## Assign Storage Blob Data Owner role to workspace user-assigned managed identity for workspace storage
## This allows the workspace to manage data and models in the storage account for registry operations
##
resource "azurerm_role_assignment" "workspace_storage_blob_owner" {
  depends_on = [
    module.storage_account_default,
    time_sleep.wait_aml_workspace_identities
  ]

  name                 = uuidv5("dns", "${local.rg_name}${azurerm_user_assigned_identity.workspace_identity.principal_id}${module.storage_account_default.name}blobowner")
  scope                = module.storage_account_default.id # Individual storage account resource
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_user_assigned_identity.workspace_identity.principal_id
}

##### Diagnostic Settings for Monitoring
#####

# Diagnostic settings for Application Insights
resource "azurerm_monitor_diagnostic_setting" "appinsights_diagnostics" {
  name                       = "${azurerm_application_insights.aml-appins.name}-diagnostics-${var.purpose}-${local.resolved_suffix}"
  target_resource_id         = azurerm_application_insights.aml-appins.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AppAvailabilityResults"
  }

  enabled_log {
    category = "AppBrowserTimings"
  }

  enabled_log {
    category = "AppDependencies"
  }

  enabled_log {
    category = "AppEvents"
  }

  enabled_log {
    category = "AppExceptions"
  }

  enabled_log {
    category = "AppMetrics"
  }

  enabled_log {
    category = "AppPageViews"
  }

  enabled_log {
    category = "AppPerformanceCounters"
  }

  enabled_log {
    category = "AppRequests"
  }

  enabled_log {
    category = "AppSystemEvents"
  }

  enabled_log {
    category = "AppTraces"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# Azure ML workspace diagnostic settings with ALL supported log categories
resource "azurerm_monitor_diagnostic_setting" "ml_workspace_diagnostics" {
  name                       = "${azapi_resource.aml_workspace.name}-diagnostics-${var.purpose}-${local.resolved_suffix}"
  target_resource_id         = azapi_resource.aml_workspace.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # Compute-related log categories
  enabled_log {
    category = "AmlComputeClusterEvent"
  }

  enabled_log {
    category = "AmlComputeClusterNodeEvent"
  }

  enabled_log {
    category = "AmlComputeJobEvent"
  }

  enabled_log {
    category = "AmlComputeCpuGpuUtilization"
  }

  enabled_log {
    category = "ComputeInstanceEvent"
  }

  # Run and experiment-related log categories
  enabled_log {
    category = "AmlRunStatusChangedEvent"
  }

  enabled_log {
    category = "RunEvent"
  }

  enabled_log {
    category = "RunReadEvent"
  }

  # Data-related log categories
  enabled_log {
    category = "DataSetChangeEvent"
  }

  enabled_log {
    category = "DataSetReadEvent"
  }

  enabled_log {
    category = "DataStoreChangeEvent"
  }

  enabled_log {
    category = "DataStoreReadEvent"
  }

  enabled_log {
    category = "DataLabelChangeEvent"
  }

  enabled_log {
    category = "DataLabelReadEvent"
  }

  # Model-related log categories
  enabled_log {
    category = "ModelsChangeEvent"
  }

  enabled_log {
    category = "ModelsReadEvent"
  }

  enabled_log {
    category = "ModelsActionEvent"
  }

  # Environment-related log categories
  enabled_log {
    category = "EnvironmentChangeEvent"
  }

  enabled_log {
    category = "EnvironmentReadEvent"
  }

  # Pipeline-related log categories
  enabled_log {
    category = "PipelineChangeEvent"
  }

  enabled_log {
    category = "PipelineReadEvent"
  }

  # Deployment and inference log categories
  enabled_log {
    category = "DeploymentReadEvent"
  }

  enabled_log {
    category = "DeploymentEventACI"
  }

  enabled_log {
    category = "DeploymentEventAKS"
  }

  enabled_log {
    category = "InferencingOperationAKS"
  }

  enabled_log {
    category = "InferencingOperationACI"
  }

  # All metrics
  enabled_metric {
    category = "AllMetrics"
  }
}

##### Create Compute Cluster
#####

## Create compute cluster with user-assigned managed identity
##
resource "azapi_resource" "compute_cluster_uami" {
  depends_on = [
    azapi_resource.aml_workspace,
    module.private_endpoint_aml_workspace,
    # Wait for all local compute role assignments to be created first
    azurerm_role_assignment.compute_ml_data_scientist,
    azurerm_role_assignment.compute_keyvault_secrets_user,
    azurerm_role_assignment.compute_storage_blob_contributor,
    azurerm_role_assignment.compute_storage_file_privileged_contributor,
    azurerm_role_assignment.compute_acr_pull,
    azurerm_role_assignment.compute_acr_push,
    azurerm_role_assignment.compute_workspace_contributor,
    azurerm_role_assignment.compute_rg_reader
  ]

  type      = "Microsoft.MachineLearningServices/workspaces/computes@2024-10-01"
  name      = "cpu-cluster-uami"
  parent_id = azapi_resource.aml_workspace.id
  location  = var.location

  body = {
    identity = {
      type = "UserAssigned"
      userAssignedIdentities = {
        "${var.compute_cluster_identity_id}" = {}
      }
    }
    properties = {
      computeType = "AmlCompute"
      properties = {
        vmSize                      = "Standard_F8s_v2"
        enableNodePublicIp          = false
        isolatedNetwork             = false
        osType                      = "Linux"
        remoteLoginPortPublicAccess = "Disabled"
        scaleSettings = {
          maxNodeCount                = 4
          minNodeCount                = 2
          nodeIdleTimeBeforeScaleDown = "PT2M"
        }
      }
      description = "CPU compute cluster with user-assigned managed identity for ML training workloads"
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

##### Create Compute Instance
#####

## Create compute instance with user-assigned managed identity for interactive development
##
resource "azapi_resource" "compute_instance_uami" {
  depends_on = [
    azapi_resource.aml_workspace,
    module.private_endpoint_aml_workspace,
    # Wait for all local compute role assignments to be created first
    azurerm_role_assignment.compute_ml_data_scientist,
    azurerm_role_assignment.compute_keyvault_secrets_user,
    azurerm_role_assignment.compute_storage_blob_contributor,
    azurerm_role_assignment.compute_storage_file_privileged_contributor,
    azurerm_role_assignment.compute_acr_pull,
    azurerm_role_assignment.compute_acr_push,
    azurerm_role_assignment.compute_workspace_contributor,
    azurerm_role_assignment.compute_rg_reader
  ]

  type      = "Microsoft.MachineLearningServices/workspaces/computes@2024-10-01"
  name      = "ci-dev-${var.purpose}"
  parent_id = azapi_resource.aml_workspace.id
  location  = var.location

  body = {
    identity = {
      type = "UserAssigned"
      userAssignedIdentities = {
        "${var.compute_cluster_identity_id}" = {}
      }
    }
    properties = {
      computeType = "ComputeInstance"
      properties = {
        vmSize                      = "Standard_F8s_v2"
        enableNodePublicIp          = false
        personalComputeInstanceSettings = {
          assignedUser = {
            objectId = data.azurerm_client_config.current.object_id
            tenantId = data.azurerm_client_config.current.tenant_id
          }
        }
        sshSettings = {
          sshPublicAccess = "Disabled"
        }
        applicationSharingPolicy = "Personal"
        computeInstanceAuthorizationType = "personal"
      }
      description = "Personal compute instance with user-assigned managed identity for interactive ML development"
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

##### Configure Image Build Compute
#####

## Add a delay to ensure compute resources are fully provisioned
resource "time_sleep" "wait_for_compute_resources" {
  depends_on = [
    azapi_resource.compute_cluster_uami,
    azapi_resource.compute_instance_uami
  ]
  create_duration = "180s"  # Increased to 180 seconds
}

## Configure workspace to use compute cluster for image builds since ACR is private
## Using the same API version as workspace creation for consistency
resource "azapi_update_resource" "workspace_image_build_config" {
  depends_on = [
    azapi_resource.aml_workspace,
    time_sleep.wait_for_compute_resources,
    module.private_endpoint_aml_workspace
  ]

  type        = "Microsoft.MachineLearningServices/workspaces@2025-04-01-preview"
  resource_id = azapi_resource.aml_workspace.id

  body = {
    properties = {
      imageBuildCompute = azapi_resource.compute_cluster_uami.name
    }
  }

  # Add verification step
  provisioner "local-exec" {
  command = "Start-Sleep -Seconds 10; Write-Host 'Image build compute configuration applied. Please verify manually with: az ml workspace show --name ${azapi_resource.aml_workspace.name} --resource-group ${local.rg_name} --query image_build_compute'"
    interpreter = ["pwsh", "-Command"]
  }
}



