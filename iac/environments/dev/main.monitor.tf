# Action Group: routes Azure Monitor alerts (Smart Detection anomalies + the
# scheduled query rules below) to the team by email.
resource "azurerm_monitor_action_group" "sre" {
  name                = "ag-sre-${var.tags.product}-${var.tags.environment}"
  resource_group_name = module.rg.resource_group_name
  short_name          = "sre-alerts"
  tags                = var.tags

  email_receiver {
    name          = "francis"
    email_address = "Francis.Daray@myridius.com"
  }
  email_receiver {
    name          = "suraj"
    email_address = "skoditala@gmail.com"
  }
  email_receiver {
    name          = "suleman"
    email_address = "Mohd.Suleman@myridius.com"
  }
  email_receiver {
    name          = "shanthi"
    email_address = "Shanthi.Subramanian@myridius.com"
  }
}

# Smart Detection (US-18.2's "before the breach" layer) -- free, ML-based
# anomaly baseline built into Application Insights, no thresholds to tune.
# One rule covers both apps: FailureAnomaliesDetector breaks results down by
# AppRoleName internally.
resource "azurerm_monitor_smart_detector_alert_rule" "failure_anomalies" {
  name                = "smart-failure-anomalies-${var.tags.product}-${var.tags.environment}"
  resource_group_name = module.rg.resource_group_name
  severity            = "Sev2"
  scope_resource_ids  = [module.log_analytics_workspace.application_insights_resource_id]
  frequency           = "PT1M"
  detector_type       = "FailureAnomaliesDetector"
  tags                = var.tags

  action_group {
    ids = [azurerm_monitor_action_group.sre.id]
  }
}

# Deterministic threshold layer -- fires on an actual breach (mirrors what the
# SRE watchdog pipeline also checks, so the same conditions get an
# AI-narrated GitHub issue in addition to this email).
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "failed_request_burst" {
  name                    = "alert-failed-requests-${var.tags.product}-${var.tags.environment}"
  resource_group_name     = module.rg.resource_group_name
  location                = var.location
  scopes                  = [module.log_analytics_workspace.log_analytics_workspace_resource_id]
  severity                = 2
  evaluation_frequency    = "PT5M"
  window_duration         = "PT15M"
  auto_mitigation_enabled = true
  tags                    = var.tags

  criteria {
    query                   = "AppRequests | where Success == false"
    time_aggregation_method = "Count"
    threshold               = 5
    operator                = "GreaterThan"
  }

  action {
    action_groups = [azurerm_monitor_action_group.sre.id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "unhandled_exceptions" {
  name                    = "alert-unhandled-exceptions-${var.tags.product}-${var.tags.environment}"
  resource_group_name     = module.rg.resource_group_name
  location                = var.location
  scopes                  = [module.log_analytics_workspace.log_analytics_workspace_resource_id]
  severity                = 2
  evaluation_frequency    = "PT5M"
  window_duration         = "PT15M"
  auto_mitigation_enabled = true
  tags                    = var.tags

  criteria {
    query                   = "AppExceptions"
    time_aggregation_method = "Count"
    threshold               = 3
    operator                = "GreaterThan"
  }

  action {
    action_groups = [azurerm_monitor_action_group.sre.id]
  }
}
