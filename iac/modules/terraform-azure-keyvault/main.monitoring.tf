resource "azurerm_monitor_metric_alert" "keyvault" {
  for_each = {
    for key, alert in var.keyvault_alerts : key => alert
    if var.enable_monitoring_alerts && alert.enabled
  }

  name = coalesce(
    each.value.name,
    "${var.tags.environment}-keyvault-${each.key}"
  )

  resource_group_name = var.resource_group_name
  scopes              = [azurerm_key_vault.this.id]
  description         = coalesce(each.value.description, "Key Vault alert for ${each.value.metric_name}")
  severity            = each.value.severity
  frequency           = each.value.frequency
  window_size         = each.value.window
  auto_mitigate       = each.value.auto_mitigate

  dynamic "criteria" {
    for_each = each.value.criterion_type == "StaticThresholdCriterion" ? [1] : []

    content {
      metric_namespace       = each.value.metric_namespace
      metric_name            = each.value.metric_name
      aggregation            = each.value.aggregation
      operator               = each.value.operator
      threshold              = each.value.threshold
      skip_metric_validation = each.value.skip_metric_validation

      dynamic "dimension" {
        for_each = each.value.dimensions

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
      metric_namespace         = each.value.metric_namespace
      metric_name              = each.value.metric_name
      aggregation              = each.value.aggregation
      operator                 = each.value.operator
      alert_sensitivity        = coalesce(each.value.alert_sensitivity, "Medium")
      evaluation_failure_count = each.value.failing_periods.min_failing_periods_to_alert
      evaluation_total_count   = each.value.failing_periods.number_of_evaluation_periods
      skip_metric_validation   = each.value.skip_metric_validation

      dynamic "dimension" {
        for_each = each.value.dimensions

        content {
          name     = dimension.value.name
          operator = dimension.value.operator
          values   = dimension.value.values
        }
      }
    }
  }

  dynamic "action" {
    for_each = each.value.severity <= 1 && var.action_group_id != null ? [1] : []

    content {
      action_group_id = var.action_group_id
    }
  }
}

resource "azurerm_monitor_activity_log_alert" "keyvault_delete" {
  count = var.enable_monitoring_alerts && var.enable_keyvault_delete_alert ? 1 : 0

  name                = "${var.tags.environment}-keyvault-delete"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_key_vault.this.id]
  description         = "Activity Log Alert for Key Vault Delete"
  location            = "global"

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.KeyVault/vaults/delete"
    status         = "Succeeded"
  }

  dynamic "action" {
    for_each = var.action_group_id != null ? [1] : []

    content {
      action_group_id = var.action_group_id
    }
  }
}
