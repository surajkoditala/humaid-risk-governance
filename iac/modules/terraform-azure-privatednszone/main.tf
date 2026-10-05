# Resource level lock (Optional)
# Use this only for higherlevel environment (like prod) as necessary
resource "azurerm_management_lock" "this" {
  count = var.lock != null ? 1 : 0

  lock_level = var.lock.kind
  name       = coalesce(var.lock.name, "lock-pdns-${var.tags.product}-${var.tags.environment}-${local.user_preferred_index}")
  scope      = azurerm_private_dns_zone.this.id
  notes      = var.lock.kind == "CanNotDelete" ? "Cannot delete the resource or its child resources." : "Cannot delete or modify the resource or its child resources."
}

# Role assignment (Optional)
resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  principal_id                           = each.value.principal_id
  scope                                  = each.value.scope != null ? each.value.scope : azurerm_private_dns_zone.this.id
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
  principal_type                         = each.value.principal_type
  role_definition_id                     = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? each.value.role_definition_id_or_name : null
  role_definition_name                   = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? null : each.value.role_definition_id_or_name
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
}

# Private DNS Zone
resource "azurerm_private_dns_zone" "this" {

  name                = var.domain_name
  resource_group_name = var.resource_group_name
  tags                = merge(local.default_tags, var.tags)
}

# VNet Links (loop through all VNets passed in)
resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each              = { for v in var.vnets_to_link : v.name => v }
  name                  = "vnet-link-${each.value.name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = each.value.id
  tags                  = merge(local.default_tags, var.tags)
}