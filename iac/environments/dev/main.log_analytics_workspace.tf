# Creates Log analytics workspace and Application Insights
module "log_analytics_workspace" {
  source = "../../modules/terraform-azure-loganalytics-workspace"

  location            = var.location
  resource_group_name = module.rg.resource_group_name
  tags                = var.tags

  # Hard cost cap: hackathon dev workload should never see more than 1GB/day.
  log_analytics_workspace_daily_quota_gb = 1
}