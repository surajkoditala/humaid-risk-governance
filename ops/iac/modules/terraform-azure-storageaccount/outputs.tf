output "storage_account_name" {
  description = "The name of the storage account"
  value       = azurerm_storage_account.this.name
}

output "storage_account_resource_id" {
  description = "The ID of the Storage Account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_blob_public_fqdn" {
  description = "The public endpoint of the blob service"
  value       = "${azurerm_storage_account.this.name}.blob.core.windows.net"
}

output "storage_account_blob_private_fqdn" {
  description = "The private endpoint of the blob service"
  value       = "${azurerm_storage_account.this.name}.privatelink.blob.core.windows.net"
}

output "storage_account_private_endpoints" {
  description = "A map of private endpoints. The map key is the supplied input to var.private_endpoints. The map value is the entire azurerm_private_endpoint resource."
  value       = var.private_endpoints_manage_dns_zone_group ? azurerm_private_endpoint.this : null
}

output "storage_account_private_end_point_name" {
  description = "The name of the storage account private endpoint"
  value       = length(var.private_endpoints) > 0 ? { for k, v in var.private_endpoints : "${k}_name" => azurerm_private_endpoint.this[k].name } : {}
}

output "storage_account_private_end_point_id" {
  description = "The name of the storage account private endpoint"
  value       = length(var.private_endpoints) > 0 ? { for k, v in var.private_endpoints : "${k}_id" => azurerm_private_endpoint.this[k].id } : {}
}

output "storage_account_access_key" {
  description = "The access key for the storage account"
  value       = azurerm_storage_account.this.primary_access_key
  sensitive   = true
}

# Optional endpoints - Use these based on the availability and requirement
output "storage_account_file_public_fqdn" {
  description = "The public endpoint of the file service"
  value       = "${azurerm_storage_account.this.name}.file.core.windows.net"
}

output "storage_account_file_private_fqdn" {
  description = "The private endpoint of the file service"
  value       = "${azurerm_storage_account.this.name}.privatelink.file.core.windows.net"
}

output "storage_account_queue_public_fqdn" {
  description = "The public endpoint of the queue service"
  value       = "${azurerm_storage_account.this.name}.queue.core.windows.net"
}

output "storage_account_queue_private_fqdn" {
  description = "The private endpoint of the queue service"
  value       = "${azurerm_storage_account.this.name}.privatelink.queue.core.windows.net"
}

output "storage_account_table_public_fqdn" {
  description = "The public endpoint of the table service"
  value       = "${azurerm_storage_account.this.name}.table.core.windows.net"
}

output "storage_account_table_private_fqdn" {
  description = "The private endpoint of the table service"
  value       = "${azurerm_storage_account.this.name}.privatelink.table.core.windows.net"
}