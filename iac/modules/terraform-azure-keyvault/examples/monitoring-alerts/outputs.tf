output "key_vault_name" {
  value = module.keyvault.key_vault_name
}

output "key_vault_metric_alert_ids" {
  value = module.keyvault.key_vault_metric_alert_ids
}

output "key_vault_delete_activity_log_alert_id" {
  value = module.keyvault.key_vault_delete_activity_log_alert_id
}

output "key_vault_action_group_id" {
  value = azurerm_monitor_action_group.ops.id
}
