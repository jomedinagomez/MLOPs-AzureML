resource "azurerm_key_vault" "kv" {
  name                = "${local.kv_name}${var.purpose}${var.location_code}${var.random_string}"
  location            = var.location
  resource_group_name = var.resource_group_name

  sku_name  = local.sku_name
  tenant_id = data.azurerm_subscription.current.tenant_id

  enabled_for_deployment          = local.deployment_vm
  enabled_for_template_deployment = local.deployment_template
  enable_rbac_authorization       = var.rbac_enabled
  public_network_access_enabled   = var.public_network_access_enabled

  enabled_for_disk_encryption = var.disk_encryption
  soft_delete_retention_days  = var.soft_delete_retention_days
  purge_protection_enabled    = var.purge_protection

  network_acls {
    default_action = var.firewall_default_action
    bypass         = var.firewall_bypass
    ip_rules       = var.firewall_ip_rules
  }
  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

resource "azurerm_role_assignment" "assign-admin" {

  count = var.rbac_enabled == true ? 1 : 0

  depends_on = [
    azurerm_key_vault.kv
  ]
  name                 = uuidv5("dns", "${azurerm_key_vault.kv.name}${var.kv_admin_object_id}")
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.KeyVault/vaults/${azurerm_key_vault.kv.name}"
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.kv_admin_object_id
}

resource "azurerm_key_vault_access_policy" "access-policy" {
  for_each = {
    for i, policy in var.access_policies : i => policy
  }

  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_subscription.current.tenant_id
  object_id    = each.value.object_id

  key_permissions         = each.value.key_permissions
  secret_permissions      = each.value.secret_permissions
  certificate_permissions = each.value.certificate_permissions
}

# Key Vault diagnostic settings with all supported log categories
resource "azurerm_monitor_diagnostic_setting" "diag-base" {
  depends_on = [
    azurerm_key_vault.kv,
    azurerm_role_assignment.assign-admin
  ]

  name                       = "${azurerm_key_vault.kv.name}-diagnostics-${var.purpose}-${var.random_string}"
  target_resource_id         = azurerm_key_vault.kv.id
  log_analytics_workspace_id = var.law_resource_id

  # Key Vault audit events - tracks all access to secrets, keys, and certificates
  enabled_log {
    category = "AuditEvent"
  }

  # Policy evaluation details for compliance monitoring
  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }

  # All metrics for performance and usage monitoring
  enabled_metric {
    category = "AllMetrics"
  }
}

# Automatic Key Vault purge on destroy (configurable for dev/test environments)
resource "null_resource" "keyvault_purge" {
  count      = var.enable_auto_purge ? 1 : 0
  depends_on = [azurerm_key_vault.kv]

  # This runs when the resource is destroyed
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      try {
        az keyvault purge --name ${self.triggers.kv_name} --location ${self.triggers.location}
        Write-Host "Key Vault ${self.triggers.kv_name} purged successfully"
      } catch {
        Write-Host "Key Vault already purged or not found: ${self.triggers.kv_name}"
      }
    EOT

    # Use PowerShell on Windows, bash on Linux/Mac
    interpreter = ["PowerShell", "-Command"]
  }

  triggers = {
    kv_name  = azurerm_key_vault.kv.name
    location = azurerm_key_vault.kv.location
  }

  lifecycle {
    # Prevent recreation when triggers change
    replace_triggered_by = [azurerm_key_vault.kv]
  }
}
