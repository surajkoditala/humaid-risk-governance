# We need the tenant id for the key vault.
data "azurerm_client_config" "this" {}

module "keyvault" {
  source = "../../" # In reality, this will be like "app.terraform.io/<tfc-org-name>/<registry-name>/azure"; version = "<version>"

  location            = "eastus2"
  resource_group_name = "rg-gh-dev-sandbox"
  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }
  tenant_id = data.azurerm_client_config.this.tenant_id

  network_acls = {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = ["157.66.143.200/32", "210.14.21.200/32", "208.195.3.201/32"]                                                                                                                                                                                                                                                                                                                    #Company VPNs                                                                                                                                                                                                                                                                                                                      #VPN IPs
    virtual_network_subnet_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-cae-dev-sandbox-01", "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01"] #Subnets of the resources from which access is needed
  }

}