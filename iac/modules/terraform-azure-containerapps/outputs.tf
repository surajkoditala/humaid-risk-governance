# Outputs for Azure Container App
output "container_app_id" {
  description = "The ID of the Azure Container App."
  value       = azurerm_container_app.this.id
}

output "container_app_name" {
  description = "The name of the Azure Container App."
  value       = azurerm_container_app.this.name
}

output "container_app_fqdn" {
  description = "The FQDN of the container app"
  value       = azurerm_container_app.this.ingress[0].fqdn
}

output "container_app_registry" {
  description = "The container registry block used in the Azure Container App."
  value       = var.registry != null ? azurerm_container_app.this.registry : null
}

output "container_app_system_assigned_identity_principal_id" {
  description = "Principal ID of the System Assigned Managed Identity for the Container App"
  value       = azurerm_container_app.this.identity[0].principal_id
}

