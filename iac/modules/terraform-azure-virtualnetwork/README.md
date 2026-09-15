<!-- BEGIN_TF_DOCS -->


## Introduction

This Terraform module is designed to provision a robust, and secure Azure Virtual Network (VNet) architecture. It encapsulates the creation of VNets, subnets, DNS servers, network security groups (NSGs), route tables, and their associations. It is built to quickly roll out and manage consistent networking configurations across environments.

## 📘 Overview

This module enables:

- Creation of a Virtual Network with custom address spaces
- Optional DNS server configuration per VNet
- Creation of multiple subnets using `for_each`, including optional service delegation
- NSG creation and security rule definitions using `dynamic` blocks with `try()` for optional attributes
- NSG-to-subnet associations
- Route table provisioning using `for_each`, with optional routes
- Subnet-to-route table associations
- Optional DDoS protection plan integration

#Basic Example

```hcl
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



# Virtual Network full object
output "vnet" {
  description = "The full Azure Virtual Network resource"
  value       = module.vnet.vnet
}

# Virtual Network ID
output "vnet_id" {
  description = "The ID of the Azure Virtual Network"
  value       = module.vnet.vnet_id
}

# Virtual Network name
output "vnet_name" {
  description = "The name of the Azure Virtual Network"
  value       = module.vnet.vnet_name
}

# Subnet map
output "subnets" {
  description = "Map of subnets created in the VNet"
  value       = module.vnet.subnets
}

# Subnet IDs
output "subnet_ids" {
  description = "Map of subnet names to their IDs"
  value       = module.vnet.subnet_ids
}

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0, < 5.0.0"
    }
  }
  required_version = ">= 1.9, < 2.0"

  # During Infra Provisioning in Myridius, the backend will be configured to use TFC
  # This is to ensure that the state file is stored in TFC and not on the local machine
  # cloud {
  #   organization = "Myridius"

  #   workspaces {
  #     name = "your-workspace-name"
  #   }
  # }

  # If you want to use a azure storage account as the backend, you can do so by uncommenting the following block
  # backend "azurerm" {
  #   resource_group_name = "your-resource-group-name"
  #   storage_account_name = "your-storage-account-name"
  #   container_name = "your-container-name"
  #   key = "your-key"
  # }

}

provider "azurerm" {
  features {}
}
```

#VNet with DNS servers and subnets delegation Example

```hcl
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



# Virtual Network full object
output "vnet" {
  description = "The full Azure Virtual Network resource"
  value       = module.vnet.vnet
}

# Virtual Network ID
output "vnet_id" {
  description = "The ID of the Azure Virtual Network"
  value       = module.vnet.vnet_id
}

# Virtual Network name
output "vnet_name" {
  description = "The name of the Azure Virtual Network"
  value       = module.vnet.vnet_name
}

# Subnet map
output "subnets" {
  description = "Map of subnets created in the VNet"
  value       = module.vnet.subnets
}

# Subnet IDs
output "subnet_ids" {
  description = "Map of subnet names to their IDs"
  value       = module.vnet.subnet_ids
}

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0, < 5.0.0"
    }
  }
  required_version = ">= 1.9, < 2.0"

  # During Infra Provisioning in Myridius, the backend will be configured to use TFC
  # This is to ensure that the state file is stored in TFC and not on the local machine
  # cloud {
  #   organization = "Myridius"

  #   workspaces {
  #     name = "your-workspace-name"
  #   }
  # }

  # If you want to use a azure storage account as the backend, you can do so by uncommenting the following block
  # backend "azurerm" {
  #   resource_group_name = "your-resource-group-name"
  #   storage_account_name = "your-storage-account-name"
  #   container_name = "your-container-name"
  #   key = "your-key"
  # }

}

provider "azurerm" {
  features {}
}
```

#Complete Example with NSG and RT

```hcl
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



# Virtual Network full object
output "vnet" {
  description = "The full Azure Virtual Network resource"
  value       = module.vnet.vnet
}

# Virtual Network ID
output "vnet_id" {
  description = "The ID of the Azure Virtual Network"
  value       = module.vnet.vnet_id
}

# Virtual Network name
output "vnet_name" {
  description = "The name of the Azure Virtual Network"
  value       = module.vnet.vnet_name
}

# Subnet map
output "subnets" {
  description = "Map of subnets created in the VNet"
  value       = module.vnet.subnets
}

# Subnet IDs
output "subnet_ids" {
  description = "Map of subnet names to their IDs"
  value       = module.vnet.subnet_ids
}

# NSGs created
output "network_security_groups" {
  description = "Map of Network Security Group resources"
  value       = module.vnet.network_security_groups
}

# NSG IDs
output "nsg_ids" {
  description = "Map of NSG names to their IDs"
  value       = module.vnet.nsg_ids
}

# Route Tables created
output "route_tables" {
  description = "Map of route table resources"
  value       = module.vnet.route_tables
}

# Route Table IDs
output "route_table_ids" {
  description = "Map of route table names to their IDs"
  value       = module.vnet.route_table_ids
}

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0, < 5.0.0"
    }
  }
  required_version = ">= 1.9, < 2.0"

  # During Infra Provisioning in Myridius, the backend will be configured to use TFC
  # This is to ensure that the state file is stored in TFC and not on the local machine
  # cloud {
  #   organization = "Myridius"

  #   workspaces {
  #     name = "your-workspace-name"
  #   }
  # }

  # If you want to use a azure storage account as the backend, you can do so by uncommenting the following block
  # backend "azurerm" {
  #   resource_group_name = "your-resource-group-name"
  #   storage_account_name = "your-storage-account-name"
  #   container_name = "your-container-name"
  #   key = "your-key"
  # }

}

provider "azurerm" {
  features {}
}
```

#VNET Peering

```hcl
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



# Virtual Network full object
output "vnet" {
  description = "The full Azure Virtual Network resource"
  value       = module.vnet-1.vnet
}

# Virtual Network ID
output "vnet_id" {
  description = "The ID of the Azure Virtual Network"
  value       = module.vnet-1.vnet_id
}

# Virtual Network name
output "vnet_name" {
  description = "The name of the Azure Virtual Network"
  value       = module.vnet-1.vnet_name
}

# Subnet map
output "subnets" {
  description = "Map of subnets created in the VNet"
  value       = module.vnet-1.subnets
}

# Subnet IDs
output "subnet_ids" {
  description = "Map of subnet names to their IDs"
  value       = module.vnet-1.subnet_ids
}

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0, < 5.0.0"
    }
  }
  required_version = ">= 1.9, < 2.0"

  # During Infra Provisioning in Myridius, the backend will be configured to use TFC
  # This is to ensure that the state file is stored in TFC and not on the local machine
  # cloud {
  #   organization = "Myridius"

  #   workspaces {
  #     name = "your-workspace-name"
  #   }
  # }

  # If you want to use a azure storage account as the backend, you can do so by uncommenting the following block
  # backend "azurerm" {
  #   resource_group_name = "your-resource-group-name"
  #   storage_account_name = "your-storage-account-name"
  #   container_name = "your-container-name"
  #   key = "your-key"
  # }

}

provider "azurerm" {
  features {}
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.8 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 3.71, < 5.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 3.71, < 5.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_network_security_group.network_security_group](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_route_table.route_table](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/route_table) | resource |
| [azurerm_subnet.subnet](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_network_security_group_association.subnet_network_security_group_association](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_subnet_route_table_association.subnet_route_table_association](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_route_table_association) | resource |
| [azurerm_virtual_network.vnet](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |
| [azurerm_virtual_network_dns_servers.dns_servers](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network_dns_servers) | resource |
| [azurerm_virtual_network_peering.virtual_network_peering](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network_peering) | resource |

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| <a name="input_address_space"></a> [address\_space](#input\_address\_space) | Address space for the Virtual Network | `list(string)` | n/a |
| <a name="input_ddos_protection_plan"></a> [ddos\_protection\_plan](#input\_ddos\_protection\_plan) | The set of DDoS protection plan configuration | <pre>object({<br/>    enable = bool<br/>    id     = string<br/>  })</pre> | `null` |
| <a name="input_dns_servers"></a> [dns\_servers](#input\_dns\_servers) | List of DNS servers to associate with the virtual network | `list(string)` | `[]` |
| <a name="input_location"></a> [location](#input\_location) | Azure region where the resource group will be created | `string` | `"eastus2"` |
| <a name="input_name"></a> [name](#input\_name) | Name of the virtual network | `string` | `null` |
| <a name="input_network_security_groups"></a> [network\_security\_groups](#input\_network\_security\_groups) | List of NSGs and their rules | <pre>list(object({<br/>    name = string<br/>    security_rules = list(object({<br/>      name                       = string<br/>      priority                   = number<br/>      direction                  = string<br/>      access                     = string<br/>      protocol                   = string<br/>      source_port_range          = optional(string)<br/>      destination_port_range     = optional(string)<br/>      source_address_prefix      = optional(string)<br/>      destination_address_prefix = optional(string)<br/><br/>      source_port_ranges           = optional(list(string)) # List of source port ranges - Required if source_port_range is not specified<br/>      destination_port_ranges      = optional(list(string)) # List of destination port ranges - Required if destination_port_range is not specified<br/>      source_address_prefixes      = optional(list(string)) # List of source address prefixes - Required if source_address_prefix is not specified<br/>      destination_address_prefixes = optional(list(string)) # List of destination address prefixes - Required if destination_address_prefix is not specified<br/>    }))<br/>  }))</pre> | `[]` |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group where resources will be created | `string` | n/a |
| <a name="input_route_tables"></a> [route\_tables](#input\_route\_tables) | Map of route table keys to their definitions | <pre>map(object({<br/>    name = string<br/>    routes = list(object({<br/>      name                   = optional(string)<br/>      address_prefix         = optional(string)<br/>      next_hop_type          = optional(string)<br/>      next_hop_in_ip_address = optional(string)<br/>    }))<br/>  }))</pre> | `{}` |
| <a name="input_subnet_nsg_map"></a> [subnet\_nsg\_map](#input\_subnet\_nsg\_map) | Map of subnet name to NSG name for association | `map(string)` | `{}` |
| <a name="input_subnet_route_table_map"></a> [subnet\_route\_table\_map](#input\_subnet\_route\_table\_map) | Map of subnet name to RT names for association | `map(string)` | `{}` |
| <a name="input_subnets"></a> [subnets](#input\_subnets) | List of subnet definitions | <pre>list(object({<br/>    name              = string<br/>    address_prefixes  = list(string)<br/>    service_endpoints = optional(list(string))<br/>    delegation = optional(object({<br/>      name = string<br/>      service_delegation = object({<br/>        name    = string<br/>        actions = optional(list(string), [])<br/>      })<br/>    }))<br/>  }))</pre> | `[]` |
| <a name="input_tags"></a> [tags](#input\_tags) | Map of tags to be applied to all resources | `map(string)` | <pre>{<br/>  "business_unit": "banking",<br/>  "customer": "myridius",<br/>  "environment": "dev",<br/>  "owner": "devops",<br/>  "product": "gh",<br/>  "region": "eastus2"<br/>}</pre> |
| <a name="input_vnet_peerings"></a> [vnet\_peerings](#input\_vnet\_peerings) | Map of VNet peering configurations | <pre>map(object({<br/>    name_local              = string<br/>    rg_local                = string<br/>    vnet_name_local         = string<br/>    remote_vnet_id          = string<br/>    allow_vnet_access       = optional(bool, true)<br/>    allow_forwarded_traffic = optional(bool, true)<br/>    allow_gateway_transit   = optional(bool, false)<br/>    use_remote_gateways     = optional(bool, false)<br/>  }))</pre> | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_dns_servers"></a> [dns\_servers](#output\_dns\_servers) | List of DNS servers configured for the VNet |
| <a name="output_network_security_groups"></a> [network\_security\_groups](#output\_network\_security\_groups) | Map of Network Security Group resources |
| <a name="output_nsg_ids"></a> [nsg\_ids](#output\_nsg\_ids) | Map of NSG names to their IDs |
| <a name="output_route_table_ids"></a> [route\_table\_ids](#output\_route\_table\_ids) | Map of route table names to their IDs |
| <a name="output_route_tables"></a> [route\_tables](#output\_route\_tables) | Map of route table resources |
| <a name="output_subnet_ids"></a> [subnet\_ids](#output\_subnet\_ids) | Map of subnet names to their IDs |
| <a name="output_subnets"></a> [subnets](#output\_subnets) | Map of subnets created in the VNet |
| <a name="output_vnet"></a> [vnet](#output\_vnet) | The full Azure Virtual Network resource |
| <a name="output_vnet_id"></a> [vnet\_id](#output\_vnet\_id) | The ID of the Azure Virtual Network |
| <a name="output_vnet_name"></a> [vnet\_name](#output\_vnet\_name) | The name of the Azure Virtual Network |

# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v1.0.0] - 2026-06-11
### Added
- Initial release of the module to create:
  - Azure Virtual Network with address space
  - Optional integration with DDoS Protection Plan
  - DNS servers association to VNet
  - Subnets with optional delegation and address prefixes
  - Network Security Groups (NSGs) with support for dynamic security rules
  - Subnet-to-NSG associations
  - Support for `service_endpoints` in subnet definition.
  - Support for additional NSG rule fields:
    - `source_port_ranges`
    - `destination_port_ranges`
    - `source_address_prefixes`
    - `destination_address_prefixes`
  - Route tables with configurable routes
  - Subnet-to-route table associations
  - Optional Virtual Network (VNet) peering support

<!-- END_TF_DOCS -->