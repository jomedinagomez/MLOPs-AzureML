locals {
  # Dynamic naming convention using specific resource prefixes
  app_insights_prefix  = "${var.resource_prefixes.workspace}in"
  aml_workspace_prefix = var.resource_prefixes.workspace

  # Settings for Azure Key Vault
  sku_name            = "premium"
  rbac_enabled        = true
  deployment_vm       = true
  deployment_template = true

  # Settings for Azure OpenAI
  openai_region      = "eastus2"
  openai_region_code = "eus2"
}