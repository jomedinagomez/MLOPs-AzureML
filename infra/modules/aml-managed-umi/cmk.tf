locals {
  cmk_key_vault_name = substr(lower(replace("kvcmk${var.purpose}${var.location_code}${local.resolved_suffix}", "-", "")), 0, 24)
}

resource "azurerm_key_vault" "cmk" {
  count = var.provision_cmk_prerequisites ? 1 : 0

  #checkov:skip=CKV2_AZURE_32: module.private_endpoint_cmk creates the private endpoint and DNS association for this vault.

  name                = local.cmk_key_vault_name
  location            = var.location
  resource_group_name = local.rg_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "premium"

  enable_rbac_authorization       = var.key_vault_cmk_rbac_enabled
  enabled_for_disk_encryption     = false
  enabled_for_deployment          = false
  enabled_for_template_deployment = false
  public_network_access_enabled   = false
  purge_protection_enabled        = true
  soft_delete_retention_days      = 90

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
  }

  tags = merge(var.tags, { component = "workspace-cmk" })

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

module "private_endpoint_cmk" {
  count = var.provision_cmk_prerequisites ? 1 : 0

  source              = "../private-endpoint"
  naming_suffix       = local.resolved_suffix
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = local.rg_name
  tags                = var.tags

  resource_name    = azurerm_key_vault.cmk[0].name
  resource_id      = azurerm_key_vault.cmk[0].id
  subresource_name = "vault"

  subnet_id            = var.subnet_id
  private_dns_zone_ids = [local.dns_zone_keyvault_id]
}

resource "azurerm_monitor_diagnostic_setting" "cmk_key_vault" {
  count = var.provision_cmk_prerequisites ? 1 : 0

  name                       = "${azurerm_key_vault.cmk[0].name}-diagnostics"
  target_resource_id         = azurerm_key_vault.cmk[0].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "time_offset" "cmk_key_expiration" {
  count = var.provision_cmk_prerequisites ? 1 : 0

  offset_years = 1
}

resource "azapi_resource" "workspace_cmk" {
  count = var.provision_cmk_prerequisites ? 1 : 0

  type                      = "Microsoft.KeyVault/vaults/keys@2024-11-01"
  name                      = var.cmk_key_name
  parent_id                 = azurerm_key_vault.cmk[0].id
  location                  = var.location
  schema_validation_enabled = false

  body = {
    properties = {
      attributes = {
        enabled = true
        exp     = time_offset.cmk_key_expiration[0].unix
      }
      keyOps  = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]
      keySize = 4096
      kty     = "RSA"
      rotationPolicy = {
        attributes = {
          expiryTime = "P1Y"
        }
        lifetimeActions = [
          {
            action = {
              type = "Rotate"
            }
            trigger = {
              timeBeforeExpiry = "P30D"
            }
          },
          {
            action = {
              type = "Notify"
            }
            trigger = {
              timeBeforeExpiry = "P30D"
            }
          }
        ]
      }
    }
  }

  response_export_values = ["properties.keyUriWithVersion"]

  depends_on = [module.private_endpoint_cmk]

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_role_assignment" "workspace_cmk_crypto_user" {
  count = var.provision_cmk_prerequisites && var.key_vault_cmk_rbac_enabled ? 1 : 0

  name                 = uuidv5("dns", "${azurerm_key_vault.cmk[0].id}${azurerm_user_assigned_identity.workspace_identity.principal_id}cryptouser")
  scope                = azurerm_key_vault.cmk[0].id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_user_assigned_identity.workspace_identity.principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [time_sleep.wait_workspace_identity]
}

resource "azurerm_role_assignment" "storage_cmk_crypto_service_encryption_user" {
  count = var.provision_cmk_prerequisites && var.key_vault_cmk_rbac_enabled ? 1 : 0

  name                 = uuidv5("dns", "${azurerm_key_vault.cmk[0].id}${module.storage_account_default.principal_id}cryptoserviceencryptionuser")
  scope                = azurerm_key_vault.cmk[0].id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = module.storage_account_default.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_key_vault_access_policy" "workspace_cmk" {
  count = var.provision_cmk_prerequisites && !var.key_vault_cmk_rbac_enabled ? 1 : 0

  key_vault_id = azurerm_key_vault.cmk[0].id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.workspace_identity.principal_id
  key_permissions = [
    "Get",
    "Recover",
    "Sign",
    "UnwrapKey",
    "WrapKey"
  ]

  depends_on = [time_sleep.wait_workspace_identity]
}

resource "azurerm_key_vault_access_policy" "storage_cmk" {
  count = var.provision_cmk_prerequisites && !var.key_vault_cmk_rbac_enabled ? 1 : 0

  key_vault_id = azurerm_key_vault.cmk[0].id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = module.storage_account_default.principal_id
  key_permissions = [
    "Get",
    "Recover",
    "UnwrapKey",
    "WrapKey"
  ]
}

locals {
  cmk_consumer_access_ids = var.provision_cmk_prerequisites ? (
    var.key_vault_cmk_rbac_enabled ? [
      azurerm_role_assignment.workspace_cmk_crypto_user[0].id,
      azurerm_role_assignment.storage_cmk_crypto_service_encryption_user[0].id
      ] : [
      azurerm_key_vault_access_policy.workspace_cmk[0].id,
      azurerm_key_vault_access_policy.storage_cmk[0].id
    ]
  ) : []
}

resource "time_sleep" "wait_cmk_consumer_access" {
  count = var.provision_cmk_prerequisites ? 1 : 0

  create_duration = "120s"

  triggers = {
    role_assignment_ids = sha256(join(",", sort(local.cmk_consumer_access_ids)))
    workspace_principal = azurerm_user_assigned_identity.workspace_identity.principal_id
    storage_principal   = module.storage_account_default.principal_id
  }
}

resource "azapi_resource" "storage_encryption_scope" {
  count = var.provision_cmk_prerequisites ? 1 : 0

  type                      = "Microsoft.Storage/storageAccounts/encryptionScopes@2026-04-01"
  name                      = "cmk-default"
  parent_id                 = module.storage_account_default.id
  schema_validation_enabled = false

  body = {
    properties = {
      source = "Microsoft.KeyVault"
      state  = "Enabled"
      keyVaultProperties = {
        keyUri = azapi_resource.workspace_cmk[0].output.properties.keyUriWithVersion
      }
      requireInfrastructureEncryption = true
    }
  }

  depends_on = [
    azapi_resource.workspace_cmk,
    time_sleep.wait_cmk_consumer_access
  ]

  lifecycle {
    ignore_changes = [body.properties.source]
  }
}

resource "terraform_data" "cmk_enabled_latch" {
  count = var.workspace_encryption == "cmk" ? 1 : 0

  input = {
    key_id       = azapi_resource.workspace_cmk[0].id
    workspace_id = azapi_resource.aml_workspace.id
  }

  depends_on = [azapi_resource.aml_workspace]

  lifecycle {
    prevent_destroy = true
  }
}