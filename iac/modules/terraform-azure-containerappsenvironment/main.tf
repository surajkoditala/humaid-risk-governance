#Resource level lock (Optional)
#Use this only for higherlevel environment (like prod) as necessary
resource "azurerm_management_lock" "this" {
  count = var.lock != null ? 1 : 0

  lock_level = var.lock.kind
  name       = coalesce(var.lock.name, "lock-cae-${var.tags.product}-${var.tags.environment}-${local.user_preferred_index}")
  scope      = azurerm_container_app_environment.this.id
  notes      = var.lock.kind == "CanNotDelete" ? "Cannot delete the resource or its child resources." : "Cannot delete or modify the resource or its child resources."
}

# Role assignment (Optional)
resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  principal_id                           = each.value.principal_id
  scope                                  = azurerm_container_app_environment.this.id
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
  principal_type                         = each.value.principal_type
  role_definition_id                     = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? each.value.role_definition_id_or_name : null
  role_definition_name                   = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? null : each.value.role_definition_id_or_name
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
}

#Create Log analytics workspace (Optional)
resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  count               = var.create_log_analytics_workspace ? 1 : 0
  name                = "log-cae-${var.tags.product}-${var.tags.environment}-${local.user_preferred_index}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = merge(local.default_tags, var.tags)
}

#Private DNS Zone for Container app environment
resource "azurerm_private_dns_zone" "cae_dns_zone" {
  count               = var.infrastructure_subnet_id != null ? 1 : 0
  name                = azurerm_container_app_environment.this.default_domain
  resource_group_name = var.resource_group_name
}

# VNet Links (loop through all VNets passed in)
resource "azurerm_private_dns_zone_virtual_network_link" "cae_dns_vnet_links" {
  for_each              = var.infrastructure_subnet_id != null ? { for v in var.vnets_to_link : v.name => v } : {}
  name                  = "vnet-link-cae-${each.value.name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.cae_dns_zone[0].name
  virtual_network_id    = each.value.id
}

#Create a wildcard record for the Container app environment
resource "azurerm_private_dns_a_record" "cae_wildcard_record" {
  count               = var.infrastructure_subnet_id != null ? 1 : 0
  name                = "*"
  zone_name           = azurerm_private_dns_zone.cae_dns_zone[0].name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_container_app_environment.this.static_ip_address]
}

#Create Container app environment
resource "azurerm_container_app_environment" "this" {
  name                                        = var.name != null ? var.name : "cae-${var.tags.product}-${var.tags.environment}-${local.user_preferred_index}"
  location                                    = var.location
  resource_group_name                         = var.resource_group_name
  tags                                        = merge(local.default_tags, var.tags)
  dapr_application_insights_connection_string = var.dapr_application_insights_connection_string
  internal_load_balancer_enabled              = var.infrastructure_subnet_id != null ? var.internal_load_balancer_enabled : null
  zone_redundancy_enabled                     = var.infrastructure_subnet_id != null ? var.zone_redundancy_enabled : null
  infrastructure_subnet_id                    = var.infrastructure_subnet_id
  infrastructure_resource_group_name          = var.infrastructure_resource_group_name
  logs_destination                            = var.logs_destination
  log_analytics_workspace_id                  = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : (var.create_log_analytics_workspace ? azurerm_log_analytics_workspace.log_analytics_workspace[0].id : null)

  dynamic "workload_profile" {
    for_each = var.workload_profiles
    content {
      name                  = workload_profile.value.name
      workload_profile_type = workload_profile.value.workload_profile_type
      maximum_count         = workload_profile.value.maximum_count
      minimum_count         = workload_profile.value.minimum_count
    }
  }

  dynamic "identity" {
    for_each = (var.managed_identities.system_assigned || length(var.managed_identities.user_assigned_resource_ids) > 0) ? { this = var.managed_identities } : {}

    content {
      type         = identity.value.system_assigned && length(identity.value.user_assigned_resource_ids) > 0 ? "SystemAssigned, UserAssigned" : length(identity.value.user_assigned_resource_ids) > 0 ? "UserAssigned" : "SystemAssigned"
      identity_ids = identity.value.user_assigned_resource_ids
    }
  }

  mutual_tls_enabled = var.mutual_tls_enabled
}