<!-- BEGIN_TF_DOCS -->


## Azure Resource Group (RG)

This Terraform module manages the creation of an Azure Resource Group.

## 📘 Overview

A **Resource Group** in Azure is a logical container that holds related resources for an Azure solution. Grouping resources allows for unified management of lifecycle, access, and policies.

This module simplifies and standardizes resource group creation across environments by enabling tagging, location control, and optional locks for protection.

#Examples

```hcl
module "rg" {
  source = "../../" # In reality, this will be like "app.terraform.io/<tfc-org-name>/<registry-name>/azure"

  name = "rg-genius-hacks-dev-sandbox" # When you want to use a custom name for the resource group, you can do so by passing the optional name variable to the module.
  tags = {
    "business_unit" = "banking"
    "customer"      = "myridius"
    "environment"   = "dev-sandbox"
    "product"       = "genius-hacks"
    "owner"         = "devops"
    "region"        = "eastus2"
  }

  # When you want to disable the management lock for the resource group, you can do so by passing the optional enable_lock variable to the module.
  # For Production environments, it is recommended to enable the management lock.
  enable_lock = false
}

variable "location" {
  description = "Azure region where the resource group will be created"
  type        = string
  nullable    = false
  default     = "eastus2"
}

variable "enable_lock" {
  description = "Enable or disable the lock on the resource group"
  type        = bool
  default     = true
}

variable "lock_level" {
  description = "Lock level for the resource group. Possible values are CanNotDelete and ReadOnly"
  type        = string
  default     = "CanNotDelete"
}

output "resource_group_id" {
  description = "The ID of the resource group"
  value       = module.rg.resource_group_id
}

output "resource_group_name" {
  description = "The name of the resource group"
  value       = module.rg.resource_group_name
}

output "resource_group_location" {
  description = "The location of the resource group"
  value       = module.rg.resource_group_location
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
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.76.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_management_lock.rg_lock](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_lock) | resource |
| [azurerm_resource_group.rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| <a name="input_enable_lock"></a> [enable\_lock](#input\_enable\_lock) | Enable or disable the lock on the resource group | `bool` | `true` |
| <a name="input_location"></a> [location](#input\_location) | Azure region where the resource group will be created | `string` | `"eastus2"` |
| <a name="input_lock_level"></a> [lock\_level](#input\_lock\_level) | Lock level for the resource group. Possible values are CanNotDelete and ReadOnly | `string` | `"CanNotDelete"` |
| <a name="input_name"></a> [name](#input\_name) | Name of the resource group | `string` | `null` |
| <a name="input_tags"></a> [tags](#input\_tags) | Map of tags to be applied to all resources | `map(string)` | <pre>{<br/>  "business_unit": "banking",<br/>  "customer": "myridius",<br/>  "environment": "dev",<br/>  "owner": "devops",<br/>  "product": "genius-hacks",<br/>  "region": "eastus2"<br/>}</pre> |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_resource_group_id"></a> [resource\_group\_id](#output\_resource\_group\_id) | The ID of the resource group |
| <a name="output_resource_group_location"></a> [resource\_group\_location](#output\_resource\_group\_location) | The location of the resource group |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | The name of the resource group |

# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v1.0.0] - 06/08/2026
### Added
- Initial release of the module to create:
  - Resource group
  - Management lock for the resource group

<!-- END_TF_DOCS -->