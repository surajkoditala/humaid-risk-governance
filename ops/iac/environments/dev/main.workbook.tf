# Azure Monitor Workbook: Workbench AI monitoring (AI call volume, failures and
# latency by Workbench step and provider, from the Application Insights data
# the container apps already send -- US-18.1). Defined as code so the dashboard
# is versioned and reproducible; the panels live in workbooks/ai-monitoring.json.tftpl.
# Token counts are not charted yet because the AI clients do not record them.
#
# Open it in the portal: Application Insights > appi-<product>-<environment>
# > Workbooks (or Monitor > Workbooks), filtered to this resource group.
#
# A workbook's resource name must be a GUID; uuidv5 keeps it stable across
# plans without adding a random provider.
resource "azurerm_application_insights_workbook" "ai_monitoring" {
  name                = uuidv5("url", "workbook-ai-monitoring-${var.tags.product}-${var.tags.environment}")
  resource_group_name = module.rg.resource_group_name
  location            = var.location
  display_name        = "Workbench AI monitoring (${var.tags.environment})"
  source_id           = lower(module.log_analytics_workspace.log_analytics_workspace_resource_id)
  category            = "workbook"
  tags                = var.tags

  data_json = templatefile("${path.module}/workbooks/ai-monitoring.json.tftpl", {
    workspace_id = lower(module.log_analytics_workspace.log_analytics_workspace_resource_id)
  })
}
