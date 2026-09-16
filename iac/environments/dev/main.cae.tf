module "container_app_env" {
  source = "../../modules/terraform-azure-containerappsenvironment"

  location            = var.location
  resource_group_name = module.rg.resource_group_name
  tags                = var.tags

  # log_analytics_workspace_id = module.log_analytics_workspace.log_analytics_workspace_resource_id #disabled for now to avoid costs

  # No workload_profiles override -> defaults to [] -> pure Consumption plan.
  # A "D4" profile requests real Dedicated-plan VM cores

  managed_identities = {
    system_assigned = true
  }

}