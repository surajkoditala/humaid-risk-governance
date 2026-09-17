# User assigned identity for the container apps to pull the image from ACR
resource "azurerm_user_assigned_identity" "ca_uai" {
  location            = var.location #"eastus2"
  name                = "id-ca-${var.tags.product}-${var.tags.environment}"
  resource_group_name = module.rg.resource_group_name
}

# Role assignment for user identity to pull the images as needed
resource "azurerm_role_assignment" "acr_pull" {
  scope                = module.acr.resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.ca_uai.principal_id
}

#Containerapp - gh_riskgovernance_service
module "container_app_gh_riskgovernance_ui" {
  source = "../../modules/terraform-azure-containerapps"

  # Can be used for Prod resource
  # lock = {
  #   name = "lock-ca-${var.tags.product}-${var.tags.environment}" # optional
  #   kind = "CanNotDelete"
  # }

  container_app_service_name   = var.container_app_service_name
  container_app_environment_id = module.container_app_env.container_app_environment_id
  resource_group_name          = module.rg.resource_group_name
  ingress                      = var.ingress
  tags                         = var.tags
  workload_profile_name        = "Consumption"

  template = {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas
    container = [
      {
        name   = "ca-${var.container_app_service_name}-${var.tags.environment}"
        memory = "2"
        cpu    = 1
        image  = "${module.acr.login_server}/hello-dotnet-http:v1" #Only a test image for the initial deployment to be successful, actual image deployment happens via ADO pipeline
        env = [
          {
            name  = "ENV"
            value = var.tags.environment
          }
        ]
      }
    ]
  }

  managed_identities = {
    system_assigned            = true
    user_assigned_resource_ids = toset([azurerm_user_assigned_identity.ca_uai.id])
  }

  registry = [
    {
      server   = "${module.acr.login_server}"
      identity = azurerm_user_assigned_identity.ca_uai.id
    }
  ]

  /*
  role_assignments = { #Role assignments for the system identity - to access KV and Storage
    "kv1" = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = module.container_app_erc_integration_service.container_app_system_assigned_identity_principal_id
      scope                      = local.kv_scope #Key vault
    }
    "kv2" = {
      role_definition_id_or_name = "Key Vault Certificate User"
      principal_id               = module.container_app_erc_integration_service.container_app_system_assigned_identity_principal_id
      scope                      = local.kv_scope #Key vault
    }
    "storage_blob_reader" = {
      role_definition_id_or_name = "Storage Blob Data Reader"
      principal_id               = module.container_app_erc_integration_service.container_app_system_assigned_identity_principal_id
      scope                      = local.storage_account_scope #Storage account
    }
    "storage_blob_contributor" = {
      role_definition_id_or_name = "Storage Blob Data Contributor"
      principal_id               = module.container_app_erc_integration_service.container_app_system_assigned_identity_principal_id
      scope                      = local.storage_account_scope #Storage account
    }
    "storage_queue_contributor" = {
      role_definition_id_or_name = "Storage Queue Data Contributor"
      principal_id               = module.container_app_erc_integration_service.container_app_system_assigned_identity_principal_id
      scope                      = local.storage_account_scope #Storage account
    }
  }
*/
}

# container app for backend app
#Containerapp - gh_riskgovernance_backend_app
module "container_app_gh_riskgovernance_backend_app" {
  source = "../../modules/terraform-azure-containerapps"

  # Can be used for Prod resource
  # lock = {
  #   name = "lock-ca-${var.tags.product}-${var.tags.environment}" # optional
  #   kind = "CanNotDelete"
  # }

  container_app_service_name   = var.container_app_backend_app_name
  container_app_environment_id = module.container_app_env.container_app_environment_id
  resource_group_name          = module.rg.resource_group_name
  ingress                      = var.backend_app_ingress
  tags                         = var.tags
  workload_profile_name        = "Consumption"

  template = {
    min_replicas = var.backend_app_min_replicas
    max_replicas = var.backend_app_max_replicas
    container = [
      {
        name   = "ca-${var.container_app_backend_app_name}-${var.tags.environment}"
        memory = "2"
        cpu    = 1
        image  = "${module.acr.login_server}/hello-dotnet-http:v1" #Only a test image for the initial deployment to be successful, actual image deployment happens via ADO pipeline
        env = [
          {
            name  = "ENV"
            value = var.tags.environment
          }
        ]
      }
    ]
  }

  managed_identities = {
    system_assigned            = true
    user_assigned_resource_ids = toset([azurerm_user_assigned_identity.ca_uai.id])
  }

  registry = [
    {
      server   = "${module.acr.login_server}"
      identity = azurerm_user_assigned_identity.ca_uai.id
    }
  ]

  /*
  role_assignments = { #Role assignments for the system identity - to access KV and Storage
    "kv1" = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = module.container_app_erc_integration_service.container_app_system_assigned_identity_principal_id
      scope                      = local.kv_scope #Key vault
    }
    "kv2" = {
      role_definition_id_or_name = "Key Vault Certificate User"
      principal_id               = module.container_app_erc_integration_service.container_app_system_assigned_identity_principal_id
      scope                      = local.kv_scope #Key vault
    }
    "storage_blob_reader" = {
      role_definition_id_or_name = "Storage Blob Data Reader"
      principal_id               = module.container_app_erc_integration_service.container_app_system_assigned_identity_principal_id
      scope                      = local.storage_account_scope #Storage account
    }
    "storage_blob_contributor" = {
      role_definition_id_or_name = "Storage Blob Data Contributor"
      principal_id               = module.container_app_erc_integration_service.container_app_system_assigned_identity_principal_id
      scope                      = local.storage_account_scope #Storage account
    }
    "storage_queue_contributor" = {
      role_definition_id_or_name = "Storage Queue Data Contributor"
      principal_id               = module.container_app_erc_integration_service.container_app_system_assigned_identity_principal_id
      scope                      = local.storage_account_scope #Storage account
    }
  }
*/
}