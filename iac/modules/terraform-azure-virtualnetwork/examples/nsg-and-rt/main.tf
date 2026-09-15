module "vnet" {
  source = "../../" # In reality, this will be like "app.terraform.io/<tfc-org-name>/<registry-name>/azure"; version = "<version>"

  location            = "eastus2"
  resource_group_name = "rg-erc-dev-sandbox"
  address_space       = ["10.1.0.0/16"]
  ddos_protection_plan = {
    enable = true
    id     = azurerm_network_ddos_protection_plan.ddos_protection_plan.id
  }
  dns_servers = ["10.1.0.4", "10.1.0.5", "10.1.0.6", "10.1.0.7"]
  subnets = [
    {
      name             = "snet-cae-dev-sandbox-01"
      address_prefixes = ["10.1.1.0/24"]
      delegation = {
        name = "snet-cae-dev-sandbox-01-delegation"

        service_delegation = {
          name    = "Microsoft.App/environments"
          actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
        }
      }
    },
    {
      name              = "snet-la-dev-sandbox-01"
      address_prefixes  = ["10.1.2.0/24"]
      service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage", "Microsoft.Sql"]
      delegation = {
        name = "snet-la-dev-sandbox-02-delegation"

        service_delegation = {
          name    = "Microsoft.Web/serverFarms"
          actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
        }
      }
    }
  ]
  network_security_groups = [
    {
      name = "nsg-cae-dev-sandbox-01"
      security_rules = [
        {
          name                       = "Allow-HTTP"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "80"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
        }
      ]
    },
    {
      name = "nsg-la-dev-sandbox-01"
      security_rules = [
        {
          name                         = "Allow-HTTPS"
          priority                     = 110
          direction                    = "Inbound"
          access                       = "Allow"
          protocol                     = "Tcp"
          source_port_ranges           = ["0-50000", "51000-65535"]
          destination_port_ranges      = ["80", "443"]
          source_address_prefix        = "*"
          destination_address_prefixes = ["172.16.0.0/16", "10.16.0.0/24"]
        }
      ]
    }
  ]

  subnet_nsg_map = {
    "snet-cae-dev-sandbox-01" = "nsg-cae-dev-sandbox-01"
    "snet-la-dev-sandbox-01"  = "nsg-la-dev-sandbox-01"
  }

  route_tables = {
    rt-cae-dev-sandbox-01 = {
      name = "rt-cae-dev-sandbox-01"
      routes = [
        {
          name           = "internet-default"
          address_prefix = "0.0.0.0/0"
          next_hop_type  = "Internet"
        }
      ]
    }
  }

  subnet_route_table_map = {
    "snet-cae-dev-sandbox-01" = "rt-cae-dev-sandbox-01"
  }
  tags = {
    "business_unit" = "insurity-product"
    "customer"      = "erc-client"
    "environment"   = "dev-sandbox"
    "product"       = "erc"
    "owner"         = "devops"
    "region"        = "eastus2"
  }
}

#DDos protect plan if one doesn't already exists
resource "azurerm_network_ddos_protection_plan" "ddos_protection_plan" {
  name                = "my-ddos-plan"
  location            = "eastus2"
  resource_group_name = "rg-erc-dev-sandbox"
  tags = {
    "business_unit" = "insurity-product"
    "customer"      = "erc-client"
    "environment"   = "dev-sandbox"
    "product"       = "erc"
    "owner"         = "devops"
    "region"        = "eastus2"
  }
}
