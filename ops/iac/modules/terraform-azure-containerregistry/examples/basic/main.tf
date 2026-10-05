module "containerregistry" {
  source = "../../"

  location                 = "eastus2"
  resource_group_name      = "rg-gh-dev-sandbox"
  sku                      = "Standard"
  retention_policy_in_days = null #ACR retention policy can only be applied when using the Premium Sku.
  zone_redundancy_enabled  = false

  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }
}