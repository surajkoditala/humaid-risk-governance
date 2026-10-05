output "action_group_id" {
  value = azurerm_monitor_action_group.ops.id
}

output "storage_account_name" {
  value = module.storage.storage_account_name
}

output "storage_account_resource_id" {
  value = module.storage.storage_account_resource_id
}
