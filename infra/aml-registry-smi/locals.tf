locals {
  # Dynamic naming convention using specific resource prefixes
  private_endpoint_prefix                 = "pe"
  private_endpoint_nic_prefix             = "nicpe"
  private_endpoint_conn_prefix            = "pec"
  private_endpoint_zone_group_conn_prefix = "pezgc"
  aml_registry_prefix                     = var.resource_prefixes.registry
}