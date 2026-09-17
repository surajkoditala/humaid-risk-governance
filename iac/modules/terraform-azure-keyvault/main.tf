# Resource level lock (Optional)
# Use this only for higherlevel environment (like prod) as necessary
resource "azurerm_management_lock" "this" {
  count = var.lock != null ? 1 : 0

  lock_level = var.lock.kind
  name       = coalesce(var.lock.name, "lock-kv-${var.tags.product}-${var.tags.environment}-${local.user_preferred_index}")
  scope      = azurerm_key_vault.this.id
  notes      = var.lock.kind == "CanNotDelete" ? "Cannot delete the resource or its child resources." : "Cannot delete or modify the resource or its child resources."
}

# Role assignment (Optional)
resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  principal_id                           = each.value.principal_id
  scope                                  = each.value.scope != null ? each.value.scope : azurerm_key_vault.this.id
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

  name                           = each.value.name != null ? each.value.name : "diag-kv-${var.tags.product}-${var.tags.environment}-${local.user_preferred_index}"
  target_resource_id             = azurerm_key_vault.this.id
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

# Azure Key Vault
resource "azurerm_key_vault" "this" {
  location                        = var.location
  name                            = var.name != null ? var.name : "kv-${var.tags.product}-${var.tags.environment}-${var.tags.region}-${local.user_preferred_index}" #kv-gh-dev-eastus2-01
  resource_group_name             = var.resource_group_name
  sku_name                        = var.sku_name
  tenant_id                       = var.tenant_id
  rbac_authorization_enabled      = !var.legacy_access_policies_enabled
  enabled_for_deployment          = var.enabled_for_deployment
  enabled_for_disk_encryption     = var.enabled_for_disk_encryption
  enabled_for_template_deployment = var.enabled_for_template_deployment
  public_network_access_enabled   = var.public_network_access_enabled
  purge_protection_enabled        = var.purge_protection_enabled
  soft_delete_retention_days      = var.soft_delete_retention_days
  tags                            = merge(local.default_tags, var.tags)

  # Only one network_acls block is allowed.
  # Create it if the variable is not null.
  dynamic "network_acls" {
    for_each = var.network_acls != null ? { this = var.network_acls } : {}

    content {
      bypass                     = network_acls.value.bypass
      default_action             = network_acls.value.default_action
      ip_rules                   = network_acls.value.ip_rules
      virtual_network_subnet_ids = network_acls.value.virtual_network_subnet_ids
    }
  }
}