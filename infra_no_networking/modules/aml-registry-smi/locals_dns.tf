locals {
  # Conditional DNS zone IDs - only resolve when private networking is enabled
  dns_zone_aml_api_id = var.enable_private_networking ? (
    var.dns_zone_aml_api_id != null ? var.dns_zone_aml_api_id : "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.api.azureml.ms"
  ) : null
}
