module "vnet" {
  source = "../../" # In reality, this will be like "app.terraform.io/<tfc-org-name>/<registry-name>/azure"; version = "<version>"

  location            = "eastus2"
  resource_group_name = "rg-gh-dev-sandbox"
  address_space       = ["10.1.0.0/16"]
  ddos_protection_plan = {
    enable = true
    id     = azurerm_network_ddos_protection_plan.ddos_protection_plan.id
  }
  dns_servers = ["10.1.0.4", "10.1.0.5", "10.1.0.6", "10.1.0.7"]
  subnets = [
    {
      name              = "snet-cae-dev-sandbox-01"
      address_prefixes  = ["10.1.1.0/24"]
      service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage", "Microsoft.Sql"]
      delegation = {
        name = "snet-cae-dev-sandbox-01-delegation"

        service_delegation = {
          name    = "Microsoft.App/environments"
          actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
        }
      }
    },
    {
      name              = "snet-la-dev-sandbox-sandbox-01"
      address_prefixes  = ["10.1.2.0/24"]
      service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage", "Microsoft.Sql"]
      delegation = {
        name = "snet-la-dev-sandbox-01-delegation"

        service_delegation = {
          name    = "Microsoft.Web/serverFarms"
          actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
        }
      }
    }
  ]
  tags = {
    "business_unit" = "banking"
    "customer"      = "myridius"
    "environment"   = "dev"
    "product"       = "gh"
    "owner"         = "devops"
    "region"        = "eastus2"
  }
}

#DDos protect plan if one doesn't already exists
resource "azurerm_network_ddos_protection_plan" "ddos_protection_plan" {
  name                = "my-ddos-plan"
  location            = "eastus2"
  resource_group_name = "rg-gh-dev-sandbox"
  tags = {
    "business_unit" = "banking"
    "customer"      = "myridius"
    "environment"   = "dev"
    "product"       = "gh"
    "owner"         = "devops"
    "region"        = "eastus2"
  }
}
