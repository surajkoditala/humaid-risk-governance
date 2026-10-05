resource "azurerm_monitor_metric_alert" "storage_account" {
  for_each = {
    for key, alert in var.storage_account_alerts : key => alert
    if var.enable_monitoring_alerts && alert.enabled
  }

  name                = each.value.name != null ? each.value.name : "${var.tags.environment}-storage-${each.key}"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_storage_account.this.id]

  description = lookup(
    each.value,
    "description",
    "Storage Account (${var.tags.environment}) alert for ${each.value.metric_name}"
  )

  severity      = each.value.severity
  frequency     = each.value.frequency
  window_size   = each.value.window
  auto_mitigate = each.value.auto_mitigate

  dynamic "criteria" {
    for_each = each.value.criterion_type == "StaticThresholdCriterion" ? [1] : []

    content {
      metric_namespace = "Microsoft.Storage/storageAccounts"
      metric_name      = each.value.metric_name
      aggregation      = each.value.aggregation
      operator         = each.value.operator
      threshold        = each.value.threshold

      dynamic "dimension" {
        for_each = lookup(each.value, "dimensions", [])

        content {
          name     = dimension.value.name
          operator = dimension.value.operator
          values   = dimension.value.values
        }
      }
    }
  }

  dynamic "dynamic_criteria" {
    for_each = each.value.criterion_type == "DynamicThresholdCriterion" ? [1] : []

    content {
      metric_namespace         = "Microsoft.Storage/storageAccounts"
      metric_name              = each.value.metric_name
      aggregation              = each.value.aggregation
      operator                 = each.value.operator
      alert_sensitivity        = each.value.alert_sensitivity
      evaluation_failure_count = each.value.failing_periods.min_failing_periods_to_alert
      evaluation_total_count   = each.value.failing_periods.number_of_evaluation_periods

      dynamic "dimension" {
        for_each = lookup(each.value, "dimensions", [])

        content {
          name     = dimension.value.name
          operator = dimension.value.operator
          values   = dimension.value.values
        }
      }
    }
  }

  dynamic "action" {
    for_each = contains([0, 1], each.value.severity) && var.action_group_id != null ? [1] : []

    content {
      action_group_id = var.action_group_id
    }
  }
}
