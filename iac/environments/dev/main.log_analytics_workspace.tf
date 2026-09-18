# Creates Log analytics workspace and Application Insights
module "log_analytics_workspace" {
  source = "../../modules/terraform-azure-loganalytics-workspace"

  location            = var.location
  resource_group_name = module.rg.resource_group_name
  tags                = var.tags
}