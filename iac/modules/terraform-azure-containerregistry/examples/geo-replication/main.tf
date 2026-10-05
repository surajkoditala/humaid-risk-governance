module "containerregistry" {
  source = "../../"

  location                = "eastus2"
  resource_group_name     = "rg-gh-dev-sandbox"
  zone_redundancy_enabled = true

  georeplications = [
    {
      location                = "centralus"
      zone_redundancy_enabled = true
      tags = {
        "product"       = "gh"
        "environment"   = "dev"
        "customer"      = "myridius"
        "business_unit" = "banking"
        "owner"         = "devops"
        "region"        = "eastus2"
      }
    }
  ]

  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }
}