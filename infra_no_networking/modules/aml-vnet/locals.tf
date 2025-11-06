locals {
  # Dynamic naming convention using specific resource prefixes
  vnet_resource_group_prefix = "rg-${var.prefix}-vnet"
  vnet_prefix                = var.resource_prefixes.vnet
  subnet_prefix              = var.resource_prefixes.subnet
  log_analytics_prefix       = var.resource_prefixes.log_analytics
}
