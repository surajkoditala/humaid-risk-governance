# Resource level lock (Optional)
# Use this only for higherlevel environment (like prod) as necessary
resource "azurerm_management_lock" "this" {
  count = var.lock != null ? 1 : 0

  lock_level = var.lock.kind
  name       = coalesce(var.lock.name, "lock-log-${var.tags.product}-${var.tags.environment}-${local.user_preferred_index}")
  scope      = azurerm_log_analytics_workspace.this.id
  notes      = var.lock.kind == "CanNotDelete" ? "Cannot delete the resource or its child resources." : "Cannot delete or modify the resource or its child resources."
}

# Role assignment (Optional)
resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  principal_id                           = each.value.principal_id
  scope                                  = each.value.scope != null ? each.value.scope : azurerm_log_analytics_workspace.this.id
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
  principal_type                         = each.value.principal_type
  role_definition_id                     = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? each.value.role_definition_id_or_name : null
  role_definition_name                   = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? null : each.value.role_definition_id_or_name
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
}

# Diagnostic settings
resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = var.diagnostic_settings

  name                           = each.value.name != null ? each.value.name : "diag-log-${var.tags.product}-${var.tags.environment}-${local.user_preferred_index}"
  target_resource_id             = azurerm_log_analytics_workspace.this.id
  eventhub_authorization_rule_id = each.value.event_hub_authorization_rule_resource_id #Only a placeholder, we really don't use this on in our environment
  eventhub_name                  = each.value.event_hub_name                           #Only a placeholder, we really don't use this on in our environment
  log_analytics_destination_type = each.value.log_analytics_destination_type == "Dedicated" ? null : each.value.log_analytics_destination_type
  log_analytics_workspace_id     = each.value.workspace_resource_id
  partner_solution_id            = each.value.marketplace_partner_resource_id #Only a placeholder, we really don't use this on in our environment
  storage_account_id             = each.value.storage_account_resource_id     #Only a placeholder, we really don't use this on in our environment

  dynamic "enabled_log" {
    for_each = each.value.log_categories

    content {
      category = enabled_log.value
    }
  }
  dynamic "enabled_log" {
    for_each = each.value.log_groups

    content {
      category_group = enabled_log.value
    }
  }
  dynamic "enabled_metric" {
    for_each = each.value.metric_categories

    content {
      category = enabled_metric.value
    }
  }
}

#Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "this" {
  location                           = var.location
  name                               = var.name != null ? var.name : "log-${var.tags.product}-${var.tags.environment}-${local.user_preferred_index}"
  resource_group_name                = var.resource_group_name
  allow_resource_only_permissions    = var.log_analytics_workspace_allow_resource_only_permissions
  cmk_for_query_forced               = var.log_analytics_workspace_cmk_for_query_forced
  daily_quota_gb                     = var.log_analytics_workspace_daily_quota_gb
  internet_ingestion_enabled         = var.log_analytics_workspace_internet_ingestion_enabled == "true" ? true : false
  internet_query_enabled             = var.log_analytics_workspace_internet_query_enabled == "true" ? true : false
  local_authentication_enabled       = var.log_analytics_workspace_local_authentication_enabled
  reservation_capacity_in_gb_per_day = var.log_analytics_workspace_reservation_capacity_in_gb_per_day
  retention_in_days                  = var.log_analytics_workspace_retention_in_days
  sku                                = var.log_analytics_workspace_sku
  tags                               = merge(local.default_tags, var.tags)

  dynamic "identity" {
    for_each = (var.managed_identities.system_assigned || length(var.managed_identities.user_assigned_resource_ids) > 0) ? { this = var.managed_identities } : {}

    content {
      type         = identity.value.system_assigned && length(identity.value.user_assigned_resource_ids) > 0 ? "SystemAssigned, UserAssigned" : length(identity.value.user_assigned_resource_ids) > 0 ? "UserAssigned" : "SystemAssigned"
      identity_ids = identity.value.user_assigned_resource_ids
    }
  }

  dynamic "timeouts" {
    for_each = var.log_analytics_workspace_timeouts == null ? [] : [var.log_analytics_workspace_timeouts]

    content {
      create = timeouts.value.create
      delete = timeouts.value.delete
      read   = timeouts.value.read
      update = timeouts.value.update
    }
  }
}

# Application Insights
resource "azurerm_application_insights" "this" {
  count                                = var.application_insights_enabled ? 1 : 0
  name                                 = var.application_insights_name != null ? var.application_insights_name : "appi-${var.tags.product}-${var.tags.environment}-${local.user_preferred_index}"
  location                             = var.location
  resource_group_name                  = var.resource_group_name
  application_type                     = var.application_type
  daily_data_cap_in_gb                 = var.daily_data_cap_in_gb
  daily_data_cap_notifications_enabled = var.daily_data_cap_notifications_enabled
  ip_masking_enabled                   = var.ip_masking_enabled
  force_customer_storage_for_profiler  = var.force_customer_storage_for_profiler
  internet_ingestion_enabled           = var.internet_ingestion_enabled
  internet_query_enabled               = var.internet_query_enabled
  local_authentication_enabled         = var.local_authentication_enabled
  retention_in_days                    = var.retention_in_days
  sampling_percentage                  = var.sampling_percentage
  tags                                 = merge(local.default_tags, var.tags)
  workspace_id                         = var.workspace_id != null ? var.workspace_id : azurerm_log_analytics_workspace.this.id
}