output "key_vault_name" {
  description = "The name of the key vault."
  value       = azurerm_key_vault.this.name
}

output "key_vault_resource_id" {
  description = "The Azure resource id of the key vault."
  value       = azurerm_key_vault.this.id
}

output "key_vault_uri" {
  description = "The URI of the vault for performing operations on keys and secrets"
  value       = azurerm_key_vault.this.vault_uri
}

output "key_vault_private_fqdn" {
  description = "The private fqdn of the key vault"
  value       = "${azurerm_key_vault.this.name}.privatelink.vaultcore.azure.net"
}

output "key_vault_private_endpoints" {
  description = "A map of private endpoints. The map key is the supplied input to var.private_endpoints. The map value is the entire azurerm_private_endpoint resource."
  value       = var.private_endpoints_manage_dns_zone_group ? azurerm_private_endpoint.this : azurerm_private_endpoint.this_unmanaged_dns_zone_groups
}

output "key_vault_private_end_point_name" {
  description = "The name of the KV private endpoint"
  value       = length(var.private_endpoints) > 0 ? { for k, v in var.private_endpoints : "${k}_name" => azurerm_private_endpoint.this[k].name } : {}
}

output "key_vault_private_end_point_id" {
  description = "The name of the KV private endpoint"
  value       = length(var.private_endpoints) > 0 ? { for k, v in var.private_endpoints : "${k}_id" => azurerm_private_endpoint.this[k].id } : {}
}

output "key_vault_metric_alert_ids" {
  description = "A map of Key Vault metric alert resource IDs."
  value       = { for k, v in azurerm_monitor_metric_alert.keyvault : k => v.id }
}

output "key_vault_delete_activity_log_alert_id" {
  description = "The resource ID of the Key Vault delete activity log alert."
  value       = try(azurerm_monitor_activity_log_alert.keyvault_delete[0].id, null)
}
