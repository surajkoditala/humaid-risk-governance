module "vnet" {
  source = "../../" # In reality, this will be like "app.terraform.io/<tfc-org-name>/<registry-name>/azure"; version = "<version>"

  location            = "eastus2"
  resource_group_name = "rg-erc-dev-sandbox"
  address_space       = ["10.1.0.0/16"]
  subnets = [
    {
      name             = "snet-cae-dev-sandbox-01"
      address_prefixes = ["10.1.1.0/24"]
    },
    {
      name             = "snet-pep-dev-sandbox-01"
      address_prefixes = ["10.1.2.0/24"]
    }
  ]
  tags = {
    "business_unit" = "insurity-product"
    "customer"      = "erc-client"
    "environment"   = "dev-sandbox"
    "product"       = "erc"
    "owner"         = "devops"
    "region"        = "eastus2"
  }
}