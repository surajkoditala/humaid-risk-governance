#Azure Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.name != null ? var.name : "rg-${var.tags.product}-${var.tags.environment}"
  location = var.location
  tags     = merge(local.default_tags, var.tags)
}

#Azure Resource Group Lock
resource "azurerm_management_lock" "rg_lock" {
  count      = var.enable_lock ? 1 : 0
  name       = "rg-${var.tags.product}-${var.tags.environment}-lock"
  scope      = azurerm_resource_group.rg.id
  lock_level = var.lock_level
  notes      = "Lock created on rg-${var.tags.product}-${var.tags.environment} via Terraform"
}
