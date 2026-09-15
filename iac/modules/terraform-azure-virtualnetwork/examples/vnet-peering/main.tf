module "vnet-1" {
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
      name             = "snet-la-dev-sandbox-01"
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

  vnet_peerings = {
    vnet-1-to-vnet-2 = {
      name_local      = "vnet-erc-dev-to-vnet-erc-dev-sandbox"
      rg_local        = "rg-erc-dev-sandbox"
      vnet_name_local = "vnet-erc-dev-sandbox"
      remote_vnet_id  = module.vnet-2.vnet_id #"/subscriptions/<subscription-id>/resourceGroups/<rg-name>/providers/Microsoft.Network/virtualNetworks/<vnet-name>"
    }
  }
}

module "vnet-2" {
  source = "../../" # In reality, this will be like "app.terraform.io/<tfc-org-name>/<registry-name>/azure"; version = "<version>"

  location            = "eastus2"
  resource_group_name = "rg-erc-dev-sandbox"
  address_space       = ["10.2.0.0/16"]
  subnets = [
    {
      name             = "snet-cae-dev-sandbox-01"
      address_prefixes = ["10.2.1.0/24"]
    },
    {
      name             = "snet-la-dev-sandbox-01"
      address_prefixes = ["10.2.2.0/24"]
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

  vnet_peerings = {
    vnet-2-to-vnet-1 = {
      name_local      = "vnet-erc-dev-sandbox-to-vnet-erc-dev"
      rg_local        = "rg-erc-dev-sandbox"
      vnet_name_local = "vnet-erc-dev-sandbox"
      remote_vnet_id  = module.vnet-1.vnet_id #"/subscriptions/<subscription-id>/resourceGroups/<rg-name>/providers/Microsoft.Network/virtualNetworks/<vnet-name>"
    }
  }
}