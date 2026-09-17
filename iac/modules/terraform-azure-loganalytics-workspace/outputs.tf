#Log analytics workspace outputs
output "log_analytics_workspace_resource" {
  description = <<-EOT
  "This is the full output for the Log Analytics resource. This is the default output for the module."
  Examples:
  - module.log_analytics.log_analytics_workspace_resource.id
  - module.log_analytics.log_analytics_workspace_resource.name
EOT
  sensitive   = true
  value       = azurerm_log_analytics_workspace.this
}

output "log_analytics_workspace_resource_id" {
  description = "The resource ID for the resource."
  value       = azurerm_log_analytics_workspace.this.id
}

# Application Insights outputs
output "application_insights_resource" {
  description = <<-EOT
  "This is the full output for the Application Insights resource. This is the default output for the module."
  Examples:
  - module.log_analytics.application_insights_resource.id
  - module.log_analytics.application_insights_resource.name
EOT
  sensitive   = true
  value       = var.application_insights_enabled == true ? azurerm_application_insights.this[0] : null
}

output "application_insights_app_id" {
  description = "App ID of the Application Insights"
  value       = var.application_insights_enabled == true ? azurerm_application_insights.this[0].app_id : null
}

output "application_insights_connection_string" {
  description = "Connection String of the Application Insights"
  sensitive   = true
  value       = var.application_insights_enabled == true ? azurerm_application_insights.this[0].connection_string : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation Key of the Application Insights"
  sensitive   = true
  value       = var.application_insights_enabled == true ? azurerm_application_insights.this[0].instrumentation_key : null
}

output "application_insights_name" {
  description = "Name of the Application Insights"
  value       = var.application_insights_enabled == true ? azurerm_application_insights.this[0].name : null
}

output "application_insights_resource_id" {
  description = "The ID of the Application Insights"
  value       = var.application_insights_enabled == true ? azurerm_application_insights.this[0].id : null
}