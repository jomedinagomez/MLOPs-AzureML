resource "time_sleep" "wait_workspace_identity" {
  create_duration = "10s"

  triggers = {
    principal_id = azurerm_user_assigned_identity.workspace_identity.principal_id
  }
}

resource "azurerm_role_assignment" "workspace_key_vault_administrator" {
  name                 = uuidv5("dns", "${module.keyvault_aml.id}${azurerm_user_assigned_identity.workspace_identity.principal_id}keyvaultadministrator")
  scope                = module.keyvault_aml.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = azurerm_user_assigned_identity.workspace_identity.principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [time_sleep.wait_workspace_identity]
}

resource "azurerm_role_assignment" "workspace_storage_blob_contributor" {
  name                 = uuidv5("dns", "${module.storage_account_default.id}${azurerm_user_assigned_identity.workspace_identity.principal_id}blobdatacontributor")
  scope                = module.storage_account_default.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.workspace_identity.principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [time_sleep.wait_workspace_identity]
}

resource "azurerm_role_assignment" "workspace_storage_file_privileged_contributor" {
  name                 = uuidv5("dns", "${module.storage_account_default.id}${azurerm_user_assigned_identity.workspace_identity.principal_id}filedataprivilegedcontributor")
  scope                = module.storage_account_default.id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.workspace_identity.principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [azurerm_role_assignment.workspace_storage_blob_contributor]
}

resource "azurerm_role_assignment" "workspace_storage_table_contributor" {
  name                 = uuidv5("dns", "${module.storage_account_default.id}${azurerm_user_assigned_identity.workspace_identity.principal_id}tabledatacontributor")
  scope                = module.storage_account_default.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_user_assigned_identity.workspace_identity.principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [azurerm_role_assignment.workspace_storage_file_privileged_contributor]
}

resource "azurerm_role_assignment" "workspace_storage_queue_contributor" {
  name                 = uuidv5("dns", "${module.storage_account_default.id}${azurerm_user_assigned_identity.workspace_identity.principal_id}queuedatacontributor")
  scope                = module.storage_account_default.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_user_assigned_identity.workspace_identity.principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [azurerm_role_assignment.workspace_storage_table_contributor]
}

resource "azurerm_role_assignment" "workspace_storage_blob_private_endpoint_reader" {
  name                 = uuidv5("dns", "${module.private_endpoint_st_default_blob.id}${azurerm_user_assigned_identity.workspace_identity.principal_id}reader")
  scope                = module.private_endpoint_st_default_blob.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.workspace_identity.principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [azurerm_role_assignment.workspace_storage_queue_contributor]
}

resource "azurerm_role_assignment" "workspace_storage_file_private_endpoint_reader" {
  name                 = uuidv5("dns", "${module.private_endpoint_st_default_file.id}${azurerm_user_assigned_identity.workspace_identity.principal_id}reader")
  scope                = module.private_endpoint_st_default_file.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.workspace_identity.principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [azurerm_role_assignment.workspace_storage_blob_private_endpoint_reader]
}

resource "time_sleep" "wait_compute_cluster_identity" {
  create_duration = "10s"

  triggers = {
    identity_id  = var.compute_cluster_identity_id
    principal_id = var.compute_cluster_principal_id
  }
}

resource "azurerm_role_assignment" "compute_storage_table_contributor" {
  name                 = uuidv5("dns", "${module.storage_account_default.id}${var.compute_cluster_principal_id}tabledatacontributor")
  scope                = module.storage_account_default.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = var.compute_cluster_principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [time_sleep.wait_compute_cluster_identity]
}

resource "azurerm_role_assignment" "compute_storage_queue_contributor" {
  name                 = uuidv5("dns", "${module.storage_account_default.id}${var.compute_cluster_principal_id}queuedatacontributor")
  scope                = module.storage_account_default.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = var.compute_cluster_principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [azurerm_role_assignment.compute_storage_table_contributor]
}

locals {
  compute_cluster_role_assignment_ids = [
    azurerm_role_assignment.compute_ml_data_scientist.id,
    azurerm_role_assignment.compute_keyvault_secrets_user.id,
    azurerm_role_assignment.compute_storage_blob_contributor.id,
    azurerm_role_assignment.compute_storage_file_privileged_contributor.id,
    azurerm_role_assignment.compute_storage_table_contributor.id,
    azurerm_role_assignment.compute_storage_queue_contributor.id,
    azurerm_role_assignment.compute_acr_pull.id,
    azurerm_role_assignment.compute_acr_push.id,
    azurerm_role_assignment.compute_workspace_contributor.id,
    azurerm_role_assignment.compute_rg_reader.id
  ]
}

resource "time_sleep" "wait_compute_cluster_rbac" {
  create_duration = "120s"

  triggers = {
    principal_id        = var.compute_cluster_principal_id
    role_assignment_ids = sha256(join(",", sort(local.compute_cluster_role_assignment_ids)))
  }
}

resource "time_sleep" "wait_compute_instance_identity" {
  create_duration = "10s"

  triggers = {
    identity_id  = var.compute_instance_identity_id
    principal_id = var.compute_instance_principal_id
  }
}

resource "azurerm_role_assignment" "compute_instance_ml_data_scientist" {
  name                 = uuidv5("dns", "${azapi_resource.aml_workspace.id}${var.compute_instance_principal_id}mldatascientist")
  scope                = azapi_resource.aml_workspace.id
  role_definition_name = "AzureML Data Scientist"
  principal_id         = var.compute_instance_principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [time_sleep.wait_compute_instance_identity]
}

resource "azurerm_role_assignment" "compute_instance_storage_blob_contributor" {
  name                 = uuidv5("dns", "${module.storage_account_default.id}${var.compute_instance_principal_id}blobdatacontributor")
  scope                = module.storage_account_default.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.compute_instance_principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [azurerm_role_assignment.compute_instance_ml_data_scientist]
}

resource "azurerm_role_assignment" "compute_instance_storage_file_privileged_contributor" {
  name                 = uuidv5("dns", "${module.storage_account_default.id}${var.compute_instance_principal_id}filedataprivilegedcontributor")
  scope                = module.storage_account_default.id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = var.compute_instance_principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [azurerm_role_assignment.compute_instance_storage_blob_contributor]
}

resource "time_sleep" "wait_compute_instance_rbac" {
  create_duration = "120s"

  triggers = {
    principal_id = var.compute_instance_principal_id
    role_assignment_ids = sha256(join(",", sort([
      azurerm_role_assignment.compute_instance_ml_data_scientist.id,
      azurerm_role_assignment.compute_instance_storage_blob_contributor.id,
      azurerm_role_assignment.compute_instance_storage_file_privileged_contributor.id
    ])))
  }
}

resource "time_sleep" "wait_online_endpoint_identity" {
  create_duration = "10s"

  triggers = {
    identity_id  = var.online_endpoint_identity_id
    principal_id = var.online_endpoint_principal_id
  }
}

resource "azurerm_role_assignment" "online_endpoint_acr_pull" {
  name                 = uuidv5("dns", "${module.container_registry.id}${var.online_endpoint_principal_id}acrpull")
  scope                = module.container_registry.id
  role_definition_name = "AcrPull"
  principal_id         = var.online_endpoint_principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [time_sleep.wait_online_endpoint_identity]
}

resource "azurerm_role_assignment" "online_endpoint_storage_blob_reader" {
  name                 = uuidv5("dns", "${module.storage_account_default.id}${var.online_endpoint_principal_id}blobdatareader")
  scope                = module.storage_account_default.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.online_endpoint_principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [time_sleep.wait_online_endpoint_identity]
}

resource "azurerm_role_assignment" "online_endpoint_metrics_writer" {
  name                 = uuidv5("dns", "${azapi_resource.aml_workspace.id}${var.online_endpoint_principal_id}metricswriter")
  scope                = azapi_resource.aml_workspace.id
  role_definition_name = "AzureML Metrics Writer (preview)"
  principal_id         = var.online_endpoint_principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [time_sleep.wait_online_endpoint_identity]
}

resource "azurerm_role_assignment" "online_endpoint_deployer_operator" {
  for_each = var.online_endpoint_deployer_principal_ids

  name                 = uuidv5("dns", "${var.online_endpoint_identity_id}${each.value}managedidentityoperator")
  scope                = var.online_endpoint_identity_id
  role_definition_name = "Managed Identity Operator"
  principal_id         = each.value

  depends_on = [time_sleep.wait_online_endpoint_identity]
}

resource "azurerm_role_assignment" "online_endpoint_compute_deployer_operator" {
  name                 = uuidv5("dns", "${var.online_endpoint_identity_id}${var.compute_cluster_principal_id}managedidentityoperator")
  scope                = var.online_endpoint_identity_id
  role_definition_name = "Managed Identity Operator"
  principal_id         = var.compute_cluster_principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [time_sleep.wait_online_endpoint_identity]
}

resource "azurerm_role_assignment" "online_endpoint_compute_instance_deployer_operator" {
  name                 = uuidv5("dns", "${var.online_endpoint_identity_id}${var.compute_instance_principal_id}managedidentityoperator")
  scope                = var.online_endpoint_identity_id
  role_definition_name = "Managed Identity Operator"
  principal_id         = var.compute_instance_principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [
    time_sleep.wait_online_endpoint_identity,
    time_sleep.wait_compute_instance_identity
  ]
}

locals {
  online_endpoint_role_assignment_ids = concat(
    [
      azurerm_role_assignment.online_endpoint_acr_pull.id,
      azurerm_role_assignment.online_endpoint_storage_blob_reader.id,
      azurerm_role_assignment.online_endpoint_metrics_writer.id,
      azurerm_role_assignment.online_endpoint_compute_deployer_operator.id,
      azurerm_role_assignment.online_endpoint_compute_instance_deployer_operator.id
    ],
    [for assignment in azurerm_role_assignment.online_endpoint_deployer_operator : assignment.id]
  )
}

resource "time_sleep" "wait_online_endpoint_rbac" {
  create_duration = "120s"

  triggers = {
    principal_id        = var.online_endpoint_principal_id
    role_assignment_ids = sha256(join(",", sort(local.online_endpoint_role_assignment_ids)))
  }
}