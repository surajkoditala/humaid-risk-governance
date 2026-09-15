# Private DNS zone for ACR
resource "azurerm_private_dns_zone" "this" {
  name                = "privatelink.azurecr.io"
  resource_group_name = "rg-gh-dev-sandbox"
}

# This is the module call
# To have this working, ensure the networking from ADO or other external services are configured
module "containerregistry" {
  source = "../../"

  location                      = "eastus2"
  resource_group_name           = "rg-gh-dev-sandbox"
  public_network_access_enabled = false
  private_endpoints = {
    primary = {
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.this.id]
      subnet_resource_id            = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01" #PEP subnet ID
    }
  }

  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }
}