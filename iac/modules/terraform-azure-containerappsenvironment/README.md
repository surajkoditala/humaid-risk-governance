<!-- BEGIN_TF_DOCS -->


## Introduction

This Terraform module provisions an Azure Container App Environment (CAE) in a secure and modular manner. 

## 📘 Overview

This module enables:
- Provisioning of an Azure Container App Environment
- Optional creation of a Log Analytics Workspace for observability
- Configurable workload profiles using `for_each`
- Support for optional Dapr Application Insights connection, mutual TLS
- Optional integration with a delegated subnet (VNet), Internal Load Balancer and Zone Redundancy

#Basic Example

```hcl
module "container_app_env" {
  source = "../../"

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
  internal_load_balancer_enabled = true
  zone_redundancy_enabled        = true
  infrastructure_subnet_id       = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-cae-dev-sandbox-01"
  workload_profiles = [
    {
      name                  = "General-D4"
      workload_profile_type = "D4"
      maximum_count         = 1
      minimum_count         = 0
    }
  ]
  managed_identities = {
    system_assigned = true
  }
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

#Default Example (CAE with DNS and Log Analytics ID)

```hcl
### NOTE: This example is when we don't have app insights and log analytics workspace are already created.
### In our environment we have log analytics workspace (app insights with workspace mode enabled) and we want to use the same shared workspace for routing the logs.
### This example is for dns zone and log analytics workspace

# Log analytics workspace - Ideally we will have only one workspace in the shared environment; for the purpose of testing, am creating a new workspace
resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "log-gh-dev-sandbox-01"
  location            = "eastus2"
  resource_group_name = "rg-gh-dev-sandbox"
  sku                 = "PerGB2018"

  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }
}

# Create Application Insights (workspace-based) - Ideally we will have only one app insights in the shared environment; for the purpose of testing, am creating a new app sights
resource "azurerm_application_insights" "app_insights" {
  name                = "appi-gh-dev-sandbox"
  location            = "eastus2"
  resource_group_name = "rg-gh-dev-sandbox"
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.log_analytics_workspace.id
}

module "container_app_env" {
  source = "../../"

  user_preferred_index = 1

  # Can be used for Prod resource
  # lock = {
  #   name = "lock-agw-oscarr-dev-sandbox" # optional
  #   kind = "CanNotDelete"
  # }

  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace.id

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
  internal_load_balancer_enabled = true
  zone_redundancy_enabled        = true
  infrastructure_subnet_id       = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-cae-dev-sandbox-01"
  workload_profiles = [
    {
      name                  = "General-D4"
      workload_profile_type = "D4"
      maximum_count         = 1
      minimum_count         = 0
    }
  ]

  vnets_to_link = [
    {
      name = "vnet-gh-dev-sandbox"
      id   = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox" #Current environment VNet
    }
  ]
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

#CAE with log analytics

```hcl
###NOTE: This example is when we don't have app insights and log analytics workspace are already created.
###In our environment we have log analytics workspace (app insights with workspace mode enabled) and we want to use the same shared workspace for logs destination.

module "container_app_env" {
  source = "../../"

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
  internal_load_balancer_enabled = true
  zone_redundancy_enabled        = true
  infrastructure_subnet_id       = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-cae-dev-sandbox-01"
  workload_profiles = [
    {
      name                  = "General-D4"
      workload_profile_type = "D4"
      maximum_count         = 1
      minimum_count         = 0
    }
  ]

  create_log_analytics_workspace = true
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
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0.0, < 5.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.81.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_container_app_environment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app_environment) | resource |
| [azurerm_log_analytics_workspace.log_analytics_workspace](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_workspace) | resource |
| [azurerm_management_lock.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_lock) | resource |
| [azurerm_private_dns_a_record.cae_wildcard_record](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_a_record) | resource |
| [azurerm_private_dns_zone.cae_dns_zone](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone_virtual_network_link.cae_dns_vnet_links](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| <a name="input_create_log_analytics_workspace"></a> [create\_log\_analytics\_workspace](#input\_create\_log\_analytics\_workspace) | Whether to create a Log Analytics Workspace. | `bool` | `false` |
| <a name="input_dapr_application_insights_connection_string"></a> [dapr\_application\_insights\_connection\_string](#input\_dapr\_application\_insights\_connection\_string) | Optional Dapr Application Insights connection string. | `string` | `null` |
| <a name="input_infrastructure_resource_group_name"></a> [infrastructure\_resource\_group\_name](#input\_infrastructure\_resource\_group\_name) | Resource group for infrastructure resources. Only valid if workload\_profile is specified. | `string` | `null` |
| <a name="input_infrastructure_subnet_id"></a> [infrastructure\_subnet\_id](#input\_infrastructure\_subnet\_id) | Subnet ID to use for internal networking. | `string` | `null` |
| <a name="input_internal_load_balancer_enabled"></a> [internal\_load\_balancer\_enabled](#input\_internal\_load\_balancer\_enabled) | Use internal load balancer. Requires subnet. | `bool` | `false` |
| <a name="input_location"></a> [location](#input\_location) | Azure region where the resource group will be created | `string` | `"eastus2"` |
| <a name="input_lock"></a> [lock](#input\_lock) | Controls the Resource Lock configuration for this resource. The following properties can be specified:<br/><br/>  - `kind` - (Required) The type of lock. Possible values are `\"CanNotDelete\"` and `\"ReadOnly\"`.<br/>  - `name` - (Optional) The name of the lock. If not specified, a name will be generated based on the `kind` value. Changing this forces the creation of a new resource. | <pre>object({<br/>    kind = string<br/>    name = optional(string, null)<br/>  })</pre> | `null` |
| <a name="input_log_analytics_workspace_id"></a> [log\_analytics\_workspace\_id](#input\_log\_analytics\_workspace\_id) | Log Analytics workspace ID. Required if logs\_destination is log-analytics. | `string` | `null` |
| <a name="input_logs_destination"></a> [logs\_destination](#input\_logs\_destination) | Destination for logs: 'log-analytics' or 'azure-monitor', default is 'log-analytics'. Don’t need to set logs\_destination when you’re already using log\_analytics\_workspace\_id | `string` | `null` |
| <a name="input_managed_identities"></a> [managed\_identities](#input\_managed\_identities) | Controls the Managed Identity configuration on this resource. The following properties can be specified:<br/><br/>  - `system_assigned` - (Optional) Specifies if the System Assigned Managed Identity should be enabled.<br/>  - `user_assigned_resource_ids` - (Optional) Specifies a list of User Assigned Managed Identity resource IDs to be assigned to this resource. | <pre>object({<br/>    system_assigned            = optional(bool, false)<br/>    user_assigned_resource_ids = optional(set(string), [])<br/>  })</pre> | `{}` |
| <a name="input_mutual_tls_enabled"></a> [mutual\_tls\_enabled](#input\_mutual\_tls\_enabled) | Enable mutual TLS for container apps. | `bool` | `false` |
| <a name="input_name"></a> [name](#input\_name) | Name of the container app environment | `string` | `null` |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group where resources will be created | `string` | n/a |
| <a name="input_role_assignments"></a> [role\_assignments](#input\_role\_assignments) | A map of role assignments to create on the <RESOURCE>. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/><br/>  - `role_definition_id_or_name` - The ID or name of the role definition to assign to the principal.<br/>  - `principal_id` - The ID of the principal to assign the role to.<br/>  - `description` - (Optional) The description of the role assignment.<br/>  - `skip_service_principal_aad_check` - (Optional) If set to true, skips the Azure Active Directory check for the service principal in the tenant. Defaults to false.<br/>  - `condition` - (Optional) The condition which will be used to scope the role assignment.<br/>  - `condition_version` - (Optional) The version of the condition syntax. Leave as `null` if you are not using a condition, if you are then valid values are '2.0'.<br/>  - `delegated_managed_identity_resource_id` - (Optional) The delegated Azure Resource Id which contains a Managed Identity. Changing this forces a new resource to be created. This field is only used in cross-tenant scenario.<br/>  - `principal_type` - (Optional) The type of the `principal_id`. Possible values are `User`, `Group` and `ServicePrincipal`. It is necessary to explicitly set this attribute when creating role assignments if the principal creating the assignment is constrained by ABAC rules that filters on the PrincipalType attribute.<br/><br/>  > Note: only set `skip_service_principal_aad_check` to true if you are assigning a role to a service principal. | <pre>map(object({<br/>    role_definition_id_or_name             = string<br/>    principal_id                           = string<br/>    scope                                  = string<br/>    description                            = optional(string, null)<br/>    skip_service_principal_aad_check       = optional(bool, false)<br/>    condition                              = optional(string, null)<br/>    condition_version                      = optional(string, null)<br/>    delegated_managed_identity_resource_id = optional(string, null)<br/>    principal_type                         = optional(string, null)<br/>  }))</pre> | `{}` |
| <a name="input_tags"></a> [tags](#input\_tags) | Map of tags to be applied to all resources | `map(string)` | <pre>{<br/>  "business_unit": "banking",<br/>  "customer": "myridius",<br/>  "environment": "dev",<br/>  "owner": "devops",<br/>  "product": "gh",<br/>  "region": "eastus2"<br/>}</pre> |
| <a name="input_user_preferred_index"></a> [user\_preferred\_index](#input\_user\_preferred\_index) | A value to append at the end of the name | `number` | `1` |
| <a name="input_vnets_to_link"></a> [vnets\_to\_link](#input\_vnets\_to\_link) | List of VNets to link with the CAE private DNS zone | <pre>list(object({<br/>    name = string<br/>    id   = string<br/>  }))</pre> | `[]` |
| <a name="input_workload_profiles"></a> [workload\_profiles](#input\_workload\_profiles) | List of workload profiles. | <pre>list(object({<br/>    name                  = string #must be less than 16 characters<br/>    workload_profile_type = string #Possible values include Consumption, D4, D8, D16, D32, E4, E8, E16 and E32<br/>    maximum_count         = number<br/>    minimum_count         = number<br/>  }))</pre> | `[]` |
| <a name="input_zone_redundancy_enabled"></a> [zone\_redundancy\_enabled](#input\_zone\_redundancy\_enabled) | Enable zone redundancy. Requires subnet. | `bool` | `false` |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_container_app_environment_default_domain"></a> [container\_app\_environment\_default\_domain](#output\_container\_app\_environment\_default\_domain) | Default domain of the Azure Container App Environment. |
| <a name="output_container_app_environment_id"></a> [container\_app\_environment\_id](#output\_container\_app\_environment\_id) | ID of the Azure Container App Environment. |
| <a name="output_container_app_environment_log_analytics_workspace_id"></a> [container\_app\_environment\_log\_analytics\_workspace\_id](#output\_container\_app\_environment\_log\_analytics\_workspace\_id) | ID of the Log Analytics Workspace if created. |
| <a name="output_container_app_environment_name"></a> [container\_app\_environment\_name](#output\_container\_app\_environment\_name) | Name of the Azure Container App Environment. |
| <a name="output_container_app_environment_static_ip_address"></a> [container\_app\_environment\_static\_ip\_address](#output\_container\_app\_environment\_static\_ip\_address) | Static IP address of the Azure Container App Environment. |

# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v1.0.0] - 2026-07-06
### Added
- Initial release of the module to create:
  - Azure Container App Environment with configurable tags and naming
  - Optional Log Analytics Workspace creation
  - Support for Dapr Application Insights integration
  - Infrastructure subnet integration for VNet scenarios
  - Internal Load Balancer and Zone Redundancy options
  - Dynamic workload profiles using `for_each`
  - Mutual TLS support for secure app communication
  - Private DNS Zone creation for internal name resolution.
  - Virtual Network linking for DNS integration.
  - DNS record sets creation within the private DNS zone.
  - Optional resource lock to prevent accidental deletion or modification.
  - Logs routing to Log Analytics Workspace for centralized monitoring.
  - Virtual Network linking for DNS integration can be done for multiple VNets by passing in a list

<!-- END_TF_DOCS -->