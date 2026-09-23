locals {
  # Role assigments scope for the CAs  
  kv_scope              = module.keyvault.key_vault_resource_id
  storage_account_scope = module.storage.storage_account_resource_id

  # Environment variables for the CAs
  PEP_KEY_VAULT                         = module.keyvault.key_vault_uri                                #URI is used as alias for the private FQDN - this is used in the CAs to access the Key Vault
  BLOB_STORAGE_SERVICE_URI              = "https://${module.storage.storage_account_blob_public_fqdn}" #Azure will resolve this to the private IP via the Private DNS Zone using the private endpoint;this way DNS name matches the certificate and traffic still routes privately
  ASPNETCORE_ENVIRONMENT                = var.ASPNETCORE_ENVIRONMENT
  AI_PROVIDER                           = "AzureFoundry"
  FOUNDRY_PROJECT_ENDPOINT              = "https://proj-gh.services.ai.azure.com/api/projects/proj-gh"
  FOUNDRY_MODEL_DEPLOYMENT              = "gpt-4.1-mini"
  ANTHROPIC_MODEL                       = "claude-5-sonnet-20260630"
  CORS_ALLOWED_ORIGINS__0               = "https://ca-${var.container_app_ui_name}-${var.tags.environment}.${module.container_app_env.container_app_environment_default_domain}"
  MOCK_SYSTEMS_BASE_URL                 = "https://ca-${var.container_app_backend_app_name}-${var.tags.environment}.${module.container_app_env.container_app_environment_default_domain}"
  APPLICATIONINSIGHTS_CONNECTION_STRING = module.log_analytics_workspace.application_insights_connection_string

  # workbench variables
  AZURE_POSTGRESQL_ENDPOINT = "Server=${module.pgsql.postgresql_server_fqdn};Database=postgres;Port=5432;Ssl Mode=Require;User Id=ca-${var.container_app_ui_name}-${var.tags.environment};"

  # mockapi variables - backend_app
  BACKEND_APP_AZURE_POSTGRESQL_ENDPOINT = "Server=${module.pgsql.postgresql_server_fqdn};Database=postgres;Port=5432;Ssl Mode=Require;User Id=ca-${var.container_app_backend_app_name}-${var.tags.environment};"

}