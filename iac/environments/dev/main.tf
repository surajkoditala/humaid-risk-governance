# Resource group
module "rg" {
  source = "../../modules/terraform-azure-resourcegroup"

  tags        = var.tags
  enable_lock = false
}

# To access the configuration of the AzureRM provider such as tenant_id and subscription_id
data "azurerm_client_config" "this" {}