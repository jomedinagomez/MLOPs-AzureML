output "subscription_id" {
  description = "Azure subscription containing the Spark-ready workspace stack"
  value       = var.subscription_id
}

output "resource_group_name" {
  description = "Resource group containing the Spark-ready workspace stack"
  value       = azurerm_resource_group.workspace.name
}

output "workspace_name" {
  description = "Azure Machine Learning workspace name"
  value       = module.workspace.workspace_name
}

output "workspace_id" {
  description = "Azure Machine Learning workspace resource ID"
  value       = module.workspace.workspace_id
}

output "workspace_identity" {
  description = "Workspace user-assigned managed identity"
  value = {
    resource_id  = module.workspace.workspace_identity_id
    principal_id = module.workspace.workspace_uami_principal_id
  }
}

output "compute_cluster" {
  description = "Compute cluster and identity details"
  value = {
    name                  = module.workspace.compute_cluster_uami_name
    resource_id           = module.workspace.compute_cluster_uami_id
    identity_resource_id  = azurerm_user_assigned_identity.compute_cluster.id
    identity_client_id    = azurerm_user_assigned_identity.compute_cluster.client_id
    identity_principal_id = azurerm_user_assigned_identity.compute_cluster.principal_id
    min_nodes             = var.compute_cluster_min_nodes
    max_nodes             = var.compute_cluster_max_nodes
    vm_size               = var.compute_cluster_vm_size
  }
}

output "compute_instance" {
  description = "Compute instance and identity details"
  value = {
    name                  = module.workspace.compute_instance_uami_name
    resource_id           = module.workspace.compute_instance_uami_id
    identity_resource_id  = azurerm_user_assigned_identity.compute_instance.id
    identity_client_id    = azurerm_user_assigned_identity.compute_instance.client_id
    identity_principal_id = azurerm_user_assigned_identity.compute_instance.principal_id
    vm_size               = var.compute_instance_vm_size
  }
}

output "online_endpoint_identity" {
  description = "Reserved managed identity for future online endpoints"
  value = {
    resource_id  = azurerm_user_assigned_identity.online_endpoint.id
    client_id    = azurerm_user_assigned_identity.online_endpoint.client_id
    principal_id = azurerm_user_assigned_identity.online_endpoint.principal_id
  }
}

output "linked_resources" {
  description = "Workspace-linked Azure resources"
  value = {
    storage_account_name    = module.workspace.storage_account_name
    storage_account_id      = module.workspace.storage_account_id
    key_vault_name          = module.workspace.keyvault_name
    key_vault_id            = module.workspace.keyvault_id
    container_registry_name = module.workspace.container_registry_name
    container_registry_id   = module.workspace.container_registry_id
    log_analytics_workspace = azurerm_log_analytics_workspace.workspace.name
  }
}

output "cmk" {
  description = "Customer-managed encryption resources"
  value = {
    key_vault_id                = module.workspace.cmk_key_vault_id
    key_id                      = module.workspace.cmk_key_id
    key_uri                     = module.workspace.cmk_key_uri
    storage_encryption_scope_id = module.workspace.storage_encryption_scope_id
  }
}

output "network_policy" {
  description = "Selected-IP ingress and managed-network egress policy"
  value = {
    allowed_public_ip_cidrs = var.allowed_public_ip_cidrs
    managed_network_mode    = module.workspace.managed_network_isolation_mode
  }
}

output "spark_data_lake" {
  description = "ADLS Gen2 storage used by Azure ML serverless Spark jobs"
  value = {
    account_name    = azurerm_storage_account.spark_data_lake.name
    account_id      = azurerm_storage_account.spark_data_lake.id
    filesystem_name = azurerm_storage_data_lake_gen2_filesystem.spark.name
    input_uri       = "abfss://${azurerm_storage_data_lake_gen2_filesystem.spark.name}@${azurerm_storage_account.spark_data_lake.name}.dfs.core.windows.net/data/titanic.csv"
    output_uri      = "abfss://${azurerm_storage_data_lake_gen2_filesystem.spark.name}@${azurerm_storage_account.spark_data_lake.name}.dfs.core.windows.net/output/titanic/"
  }
}
