module "rg" {
  source = "../../" # In reality, this will be like "app.terraform.io/<tfc-org-name>/<registry-name>/azure"

  name = "rg-genius-hacks-dev-sandbox" # When you want to use a custom name for the resource group, you can do so by passing the optional name variable to the module.
  tags = {
    "business_unit" = "banking"
    "customer"      = "myridius"
    "environment"   = "dev-sandbox"
    "product"       = "genius-hacks"
    "owner"         = "devops"
    "region"        = "eastus2"
  }

  # When you want to disable the management lock for the resource group, you can do so by passing the optional enable_lock variable to the module.
  # For Production environments, it is recommended to enable the management lock.
  enable_lock = false
}