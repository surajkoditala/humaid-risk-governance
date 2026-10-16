module "container_app_env" {
  source = "../../modules/terraform-azure-containerappsenvironment"

  location            = var.location
  resource_group_name = module.rg.resource_group_name
  tags                = var.tags

  # Console + system logs for both container apps, capped by the workspace's daily quota.
  log_analytics_workspace_id = module.log_analytics_workspace.log_analytics_workspace_resource_id

  # No workload_profiles override -> defaults to [] -> pure Consumption plan.
  # A "D4" profile requests real Dedicated-plan VM cores
  workload_profiles = [
    {
      name                  = "Consumption"
      workload_profile_type = "Consumption"
      maximum_count         = 0
      minimum_count         = 0
    }
  ]

  # VNet integration: the environment keeps a public IP (internal_load_balancer_enabled
  # defaults to false) so the UI app's external ingress is unaffected. What this actually
  # changes: the backend app's external_enabled = false ingress becomes a real private
  # network boundary instead of just a label, since the environment's internal DNS is now
  # bound to this VNet. vnets_to_link is required for the module's private DNS zone to
  # actually resolve within the VNet -- without it, internal app-to-app calls would fail.
  infrastructure_subnet_id = module.vnet.subnet_ids["snet-cae-${var.tags.environment}-01"]
  vnets_to_link = [
    {
      name = module.vnet.vnet_name
      id   = module.vnet.vnet_id
    }
  ]

  managed_identities = {
    system_assigned = true
  }

}
