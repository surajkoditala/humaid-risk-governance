output "container_app_environment_id" {
  description = "ID of the Azure Container App Environment."
  value       = azurerm_container_app_environment.this.id
}

output "container_app_environment_name" {
  description = "Name of the Azure Container App Environment."
  value       = azurerm_container_app_environment.this.name
}

output "container_app_environment_default_domain" {
  description = "Default domain of the Azure Container App Environment."
  value       = azurerm_container_app_environment.this.default_domain
}

output "container_app_environment_static_ip_address" {
  description = "Static IP address of the Azure Container App Environment."
  value       = azurerm_container_app_environment.this.static_ip_address
}

output "container_app_environment_log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace if created."
  value       = var.create_log_analytics_workspace ? azurerm_log_analytics_workspace.log_analytics_workspace[0].id : null
}