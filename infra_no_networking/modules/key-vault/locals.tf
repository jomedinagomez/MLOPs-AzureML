locals {
  # Dynamic naming convention using specific resource prefixes
  kv_name = var.resource_prefixes.key_vault

  # Settings for Azure Key Vault
  sku_name            = "premium"
  deployment_vm       = true
  deployment_template = true
}