module "private_dns" {
  source = "../../"

  resource_group_name = "rg-gh-dev-sandbox"
  domain_name         = "privatelink.servicebus.windows.net" #domain name of the private dns zone

  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }

  vnets_to_link = [
    {
      name = "vnet-gh-dev01"
      id   = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev01/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev01"
    },
    {
      name = "vnet-gh-test"
      id   = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-test/providers/Microsoft.Network/virtualNetworks/vnet-gh-test"
    }
  ]
}
