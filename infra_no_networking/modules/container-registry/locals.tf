locals {
  # Dynamic naming convention using specific resource prefixes
  acr_name = var.resource_prefixes.container_registry

  # Resource specific settings
  sku_name               = "Premium"
  local_admin_enabled    = false
  anonymous_pull_enabled = false
}