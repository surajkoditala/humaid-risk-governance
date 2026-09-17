locals {
  default_tags = {
    managed-by = "terraform"
  }
  user_preferred_index = format("%02d", var.user_preferred_index)

  role_definition_resource_substring = "/providers/Microsoft.Authorization/roleDefinitions"
}