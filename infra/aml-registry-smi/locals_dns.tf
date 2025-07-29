locals {
  # Conditional DNS zone IDs - use passed variables if available, otherwise construct from variables
  dns_zone_blob_id = var.dns_zone_blob_id != null ? var.dns_zone_blob_id : "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  
  dns_zone_file_id = var.dns_zone_file_id != null ? var.dns_zone_file_id : "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
  
  dns_zone_keyvault_id = var.dns_zone_keyvault_id != null ? var.dns_zone_keyvault_id : "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  
  dns_zone_acr_id = var.dns_zone_acr_id != null ? var.dns_zone_acr_id : "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
  
  dns_zone_aml_api_id = var.dns_zone_aml_api_id != null ? var.dns_zone_aml_api_id : "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.api.azureml.ms"
}
