# Virtual Network
address_space = ["10.12.0.0/16"]

subnets = [
  {
    name              = "snet-pep-dev-01"
    address_prefixes  = ["10.12.50.0/24"]
    service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage", "Microsoft.Sql", "Microsoft.Web"]
  },
  {
    name              = "snet-cae-dev-01"
    address_prefixes  = ["10.12.240.0/20"]
    service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage", "Microsoft.Sql"]
    delegation = {
      name = "snet-cae-dev-01-delegation"
      service_delegation = {
        name = "Microsoft.App/environments"
        actions = [
          "Microsoft.Network/virtualNetworks/subnets/join/action"
        ]
      }
    }
  }
]

network_security_groups = [
  {
    name = "nsg-pep-dev-01"
    security_rules = [
      {
        name                       = "AllowAzureDNSInbound"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "168.63.129.16"
        destination_address_prefix = "*"
      },
      {
        name                       = "AllowAzureDNSOutbound"
        priority                   = 500
        direction                  = "Outbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "168.63.129.16"
        destination_address_prefix = "*"
      }
    ]
  },
  {
    name = "nsg-cae-dev-01"
    security_rules = [
      {
        name                       = "AllowAzureDNSInbound"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "168.63.129.16"
        destination_address_prefix = "*"
      },
      {
        name                       = "AllowAzureDNSOutbound"
        priority                   = 500
        direction                  = "Outbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "168.63.129.16"
        destination_address_prefix = "*"
      }
    ]
  }
]

subnet_nsg_map = {
  "snet-pep-dev-01" = "nsg-pep-dev-01"
  "snet-cae-dev-01" = "nsg-cae-dev-01"
}

route_tables           = {}
subnet_route_table_map = {}