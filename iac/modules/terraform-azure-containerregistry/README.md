<!-- BEGIN_TF_DOCS -->


## Introduction

This module provisions an **Azure Container Registry (ACR)** with support for private networking, geo-replication, customer-managed encryption, network access controls, and observability.

---

## 📘 Overview

This module enables:

- **Azure Container Registry** deployment with configurable SKU (`Basic`, `Standard`, `Premium`) and admin access controls
- **Premium SKU features** — zone redundancy, untagged image retention policy, and data endpoint support
- **Geo-replication** across multiple Azure regions with per-replica zone redundancy and regional endpoint configuration
- **Customer-managed key (CMK)** encryption via Azure Key Vault, requiring a user-assigned managed identity
- **Managed identity** support for both system-assigned and user-assigned identities
- **Network rule set** for IP-based access restrictions with configurable default action (requires Premium SKU)
- **Private endpoints** for secure, private network access to the registry; supports managed and unmanaged DNS zone group modes
- **Private DNS zone integration** for name resolution of private endpoints
- **Application Security Group (ASG) associations** on private endpoints
- **Anonymous pull** and **export policy** controls for registry access governance
- **Quarantine policy** and **content trust (trust policy)** for image security
- **Diagnostic settings** to route registry logs and metrics to Log Analytics, Storage Account, or Event Hub
- **Role assignments (RBAC)** for fine-grained access control on the registry; supports role name or full definition ID, conditions, and delegated managed identity
- **Resource locks** to protect against accidental deletion or modification
- **Standard naming convention** (`cr<product><env><index>`) with optional custom name override; name validated to 5–50 lowercase alphanumeric characters
- **Required tag enforcement** via input validation for `business_unit`, `customer`, `environment`, `product`, `owner`, and `region`

#Examples

```hcl
module "containerregistry" {
  source = "../../"

  location                 = "eastus2"
  resource_group_name      = "rg-erc-dev-sandbox"
  sku                      = "Standard"
  retention_policy_in_days = null #ACR retention policy can only be applied when using the Premium Sku.
  zone_redundancy_enabled  = false

  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }
}



output "name" {
  description = "The name of the parent resource."
  value       = module.containerregistry.name
}

output "resource_id" {
  description = "The resource id for the parent resource."
  value       = module.containerregistry.resource_id
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

#cmk-encryption

```hcl
resource "azurerm_user_assigned_identity" "this" {
  name                = "id-cr-erc-dev-sandbox"
  location            = "eastus2"
  resource_group_name = "rg-erc-dev-sandbox"
}

data "azurerm_client_config" "this" {}

resource "azurerm_key_vault" "this" {
  location            = "eastus2"
  resource_group_name = "rg-erc-dev-sandbox"

  name = "kvacr-erc-dev-sandbox-01"

  sku_name                   = "premium"
  tenant_id                  = data.azurerm_client_config.this.tenant_id
  purge_protection_enabled   = true
  soft_delete_retention_days = 7

  access_policy {
    key_permissions = [
      "Create",
      "Delete",
      "Get",
      "Purge",
      "List",
      "Recover",
      "Update",
      "GetRotationPolicy",
      "SetRotationPolicy"
    ]
    object_id = data.azurerm_client_config.this.object_id
    tenant_id = data.azurerm_client_config.this.tenant_id
  }
  access_policy {
    key_permissions = [
      "Get",
      "Create",
      "List",
      "Restore",
      "Recover",
      "UnwrapKey",
      "WrapKey",
      "Purge",
      "Encrypt",
      "Decrypt",
      "Sign",
      "Verify",
    ]
    object_id = azurerm_user_assigned_identity.this.principal_id
    secret_permissions = [
      "Get",
    ]
    tenant_id = data.azurerm_client_config.this.tenant_id
  }
}

resource "azurerm_key_vault_key" "key" {
  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]
  key_type     = "RSA"
  key_vault_id = azurerm_key_vault.this.id
  name         = "generated-certificate"
  key_size     = 2048

  rotation_policy {
    expire_after         = "P90D"
    notify_before_expiry = "P29D"

    automatic {
      time_before_expiry = "P30D"
    }
  }
}

# This is the module call
module "containerregistry" {
  source = "../../"

  location            = "eastus2"
  resource_group_name = "rg-erc-dev-sandbox"

  retention_policy_in_days = null #ACR retention policy can only be applied when using the Premium Sku.
  zone_redundancy_enabled  = false

  managed_identities = {
    system_assigned            = true
    user_assigned_resource_ids = toset([azurerm_user_assigned_identity.this.id])
  }

  customer_managed_key = {
    key_vault_resource_id = azurerm_key_vault.this.id
    key_name              = azurerm_key_vault_key.key.name
    user_assigned_identity = {
      resource_id = azurerm_user_assigned_identity.this.id
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



output "name" {
  description = "The name of the parent resource."
  value       = module.containerregistry.name
}

output "resource_id" {
  description = "The resource id for the parent resource."
  value       = module.containerregistry.resource_id
}

output "system_assigned_mi_principal_id" {
  description = "The system assigned managed identity principal ID of the parent resource."
  value       = module.containerregistry.system_assigned_mi_principal_id
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

#geo-replication

```hcl
module "containerregistry" {
  source = "../../"

  location                = "eastus2"
  resource_group_name     = "rg-erc-dev-sandbox"
  zone_redundancy_enabled = true

  georeplications = [
    {
      location                = "centralus"
      zone_redundancy_enabled = true
      tags = {
        "product"       = "gh"
        "environment"   = "dev"
        "customer"      = "myridius"
        "business_unit" = "banking"
        "owner"         = "devops"
        "region"        = "eastus2"
      }
    }
  ]

  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }
}



output "name" {
  description = "The name of the parent resource."
  value       = module.containerregistry.name
}

output "resource_id" {
  description = "The resource id for the parent resource."
  value       = module.containerregistry.resource_id
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

#private-endpoint-and-dns

```hcl
# Private DNS zone for ACR
resource "azurerm_private_dns_zone" "this" {
  name                = "privatelink.azurecr.io"
  resource_group_name = "rg-erc-dev-sandbox"
}

# This is the module call
# To have this working, ensure the networking from ADO or other external services are configured
module "containerregistry" {
  source = "../../"

  location                      = "eastus2"
  resource_group_name           = "rg-erc-dev-sandbox"
  public_network_access_enabled = false
  private_endpoints = {
    primary = {
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.this.id]
      subnet_resource_id            = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-erc-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-erc-dev-sandbox/subnets/snet-pep-dev-sandbox-01" #PEP subnet ID
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



output "name" {
  description = "The name of the parent resource."
  value       = module.containerregistry.name
}

output "resource_id" {
  description = "The resource id for the parent resource."
  value       = module.containerregistry.resource_id
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
| [azurerm_container_registry.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_registry) | resource |
| [azurerm_management_lock.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_lock) | resource |
| [azurerm_monitor_diagnostic_setting.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_private_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_private_endpoint.this_unmanaged_dns_zone_groups](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_private_endpoint_application_security_group_association.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint_application_security_group_association) | resource |
| [azurerm_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_key_vault_key.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/key_vault_key) | data source |
| [azurerm_user_assigned_identity.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/user_assigned_identity) | data source |

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| <a name="input_admin_enabled"></a> [admin\_enabled](#input\_admin\_enabled) | Specifies whether the admin user is enabled. Defaults to `false`. | `bool` | `false` |
| <a name="input_anonymous_pull_enabled"></a> [anonymous\_pull\_enabled](#input\_anonymous\_pull\_enabled) | Specifies whether anonymous (unauthenticated) pull access to this Container Registry is allowed.  Requries Standard or Premium SKU. | `bool` | `false` |
| <a name="input_customer_managed_key"></a> [customer\_managed\_key](#input\_customer\_managed\_key) | A map of diagnostic settings to create on the Key Vault. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/>Controls the Customer managed key configuration on this resource. The following properties can be specified:<br/>- `key_vault_resource_id` - (Required) Resource ID of the Key Vault that the customer managed key belongs to.<br/>- `key_name` - (Required) Specifies the name of the Customer Managed Key Vault Key.<br/>- `key_version` - (Optional) The version of the Customer Managed Key Vault Key.<br/>- `user_assigned_identity` - (Optional) The User Assigned Identity that has access to the key.<br/>  - `resource_id` - (Required) The resource ID of the User Assigned Identity that has access to the key. | <pre>object({<br/>    key_vault_resource_id = string<br/>    key_name              = string<br/>    key_version           = optional(string, null)<br/>    user_assigned_identity = optional(object({<br/>      resource_id = string<br/>    }), null)<br/>  })</pre> | `null` |
| <a name="input_data_endpoint_enabled"></a> [data\_endpoint\_enabled](#input\_data\_endpoint\_enabled) | Specifies whether to enable dedicated data endpoints for this Container Registry.  Requires Premium SKU. | `bool` | `false` |
| <a name="input_diagnostic_settings"></a> [diagnostic\_settings](#input\_diagnostic\_settings) | A map of diagnostic settings to create on the ddos protection plan. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/><br/>- `name` - (Optional) The name of the diagnostic setting. One will be generated if not set, however this will not be unique if you want to create multiple diagnostic setting resources.<br/>- `log_categories` - (Optional) A set of log categories to send to the log analytics workspace. Defaults to `[]`.<br/>- `log_groups` - (Optional) A set of log groups to send to the log analytics workspace. Defaults to `["allLogs"]`.<br/>- `metric_categories` - (Optional) A set of metric categories to send to the log analytics workspace. Defaults to `["AllMetrics"]`.<br/>- `log_analytics_destination_type` - (Optional) The destination type for the diagnostic setting. Possible values are `Dedicated` and `AzureDiagnostics`. Defaults to `Dedicated`.<br/>- `workspace_resource_id` - (Optional) The resource ID of the log analytics workspace to send logs and metrics to.<br/>- `storage_account_resource_id` - (Optional) The resource ID of the storage account to send logs and metrics to.<br/>- `event_hub_authorization_rule_resource_id` - (Optional) The resource ID of the event hub authorization rule to send logs and metrics to.<br/>- `event_hub_name` - (Optional) The name of the event hub. If none is specified, the default event hub will be selected.<br/>- `marketplace_partner_resource_id` - (Optional) The full ARM resource ID of the Marketplace resource to which you would like to send Diagnostic LogsLogs. | <pre>map(object({<br/>    name                                     = optional(string, null)<br/>    log_categories                           = optional(set(string), [])<br/>    log_groups                               = optional(set(string), ["allLogs"])<br/>    metric_categories                        = optional(set(string), ["AllMetrics"])<br/>    log_analytics_destination_type           = optional(string, "Dedicated")<br/>    workspace_resource_id                    = optional(string, null)<br/>    storage_account_resource_id              = optional(string, null)<br/>    event_hub_authorization_rule_resource_id = optional(string, null)<br/>    event_hub_name                           = optional(string, null)<br/>    marketplace_partner_resource_id          = optional(string, null)<br/>  }))</pre> | `{}` |
| <a name="input_enable_trust_policy"></a> [enable\_trust\_policy](#input\_enable\_trust\_policy) | Specified whether trust policy is enabled for this Container Registry. | `bool` | `false` |
| <a name="input_export_policy_enabled"></a> [export\_policy\_enabled](#input\_export\_policy\_enabled) | Specifies whether export policy is enabled. Defaults to true. In order to set it to false, make sure the public\_network\_access\_enabled is also set to false. | `bool` | `true` |
| <a name="input_georeplications"></a> [georeplications](#input\_georeplications) | A list of geo-replication configurations for the Container Registry.<br/><br/>- `location` - (Required) The geographic location where the Container Registry should be geo-replicated.<br/>- `regional_endpoint_enabled` - (Optional) Enables or disables regional endpoint. Defaults to `true`.<br/>- `zone_redundancy_enabled` - (Optional) Enables or disables zone redundancy. Defaults to `true`.<br/>- `tags` - (Optional) A map of additional tags for the geo-replication configuration. Defaults to `null`. | <pre>list(object({<br/>    location                  = string<br/>    regional_endpoint_enabled = optional(bool, true)<br/>    zone_redundancy_enabled   = optional(bool, true)<br/>    tags                      = optional(map(any), null)<br/>  }))</pre> | `[]` |
| <a name="input_location"></a> [location](#input\_location) | Azure region where the resource group will be created | `string` | `"eastus2"` |
| <a name="input_lock"></a> [lock](#input\_lock) | Controls the Resource Lock configuration for this resource. The following properties can be specified:<br/><br/>  - `kind` - (Required) The type of lock. Possible values are `\"CanNotDelete\"` and `\"ReadOnly\"`.<br/>  - `name` - (Optional) The name of the lock. If not specified, a name will be generated based on the `kind` value. Changing this forces the creation of a new resource. | <pre>object({<br/>    kind = string<br/>    name = optional(string, null)<br/>  })</pre> | `null` |
| <a name="input_managed_identities"></a> [managed\_identities](#input\_managed\_identities) | Controls the Managed Identity configuration on this resource. The following properties can be specified:<br/><br/>  - `system_assigned` - (Optional) Specifies if the System Assigned Managed Identity should be enabled.<br/>  - `user_assigned_resource_ids` - (Optional) Specifies a list of User Assigned Managed Identity resource IDs to be assigned to this resource. | <pre>object({<br/>    system_assigned            = optional(bool, false)<br/>    user_assigned_resource_ids = optional(set(string), [])<br/>  })</pre> | `{}` |
| <a name="input_name"></a> [name](#input\_name) | Name of the container registry | `string` | `null` |
| <a name="input_network_rule_bypass_option"></a> [network\_rule\_bypass\_option](#input\_network\_rule\_bypass\_option) | Specifies whether to allow trusted Azure services access to a network restricted Container Registry.<br/>Possible values are `None` and `AzureServices`. Defaults to `AzureServices`. | `string` | `"AzureServices"` |
| <a name="input_network_rule_set"></a> [network\_rule\_set](#input\_network\_rule\_set) | The network rule set configuration for the Container Registry.<br/>Requires Premium SKU.<br/><br/>- `default_action` - (Optional) The default action when no rule matches. Possible values are `Allow` and `Deny`. Defaults to `Deny`.<br/>- `ip_rules` - (Optional) A list of IP rules in CIDR format. Defaults to `[]`.<br/>  - `action` - Only "Allow" is permitted<br/>  - `ip_range` - The CIDR block from which requests will match the rule. | <pre>object({<br/>    default_action = optional(string, "Deny")<br/>    ip_rule = optional(list(object({<br/>      # since the `action` property only permits `Allow`, this is hard-coded.<br/>      action   = optional(string, "Allow")<br/>      ip_range = string<br/>    })), [])<br/>  })</pre> | `null` |
| <a name="input_private_endpoints"></a> [private\_endpoints](#input\_private\_endpoints) | A map of private endpoints to create on the Container Registry. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/><br/>- `name` - (Optional) The name of the private endpoint. One will be generated if not set.<br/>- `role_assignments` - (Optional) A map of role assignments to create on the private endpoint. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time. See `var.role_assignments` for more information.<br/>  - `role_definition_id_or_name` - The ID or name of the role definition to assign to the principal.<br/>  - `principal_id` - The ID of the principal to assign the role to.<br/>  - `description` - (Optional) The description of the role assignment.<br/>  - `skip_service_principal_aad_check` - (Optional) If set to true, skips the Azure Active Directory check for the service principal in the tenant. Defaults to false.<br/>  - `condition` - (Optional) The condition which will be used to scope the role assignment.<br/>  - `condition_version` - (Optional) The version of the condition syntax. Leave as `null` if you are not using a condition, if you are then valid values are '2.0'.<br/>  - `delegated_managed_identity_resource_id` - (Optional) The delegated Azure Resource Id which contains a Managed Identity. Changing this forces a new resource to be created. This field is only used in cross-tenant scenario.<br/>  - `principal_type` - (Optional) The type of the `principal_id`. Possible values are `User`, `Group` and `ServicePrincipal`. It is necessary to explicitly set this attribute when creating role assignments if the principal creating the assignment is constrained by ABAC rules that filters on the PrincipalType attribute.<br/>- `lock` - (Optional) The lock level to apply to the private endpoint. Default is `None`. Possible values are `None`, `CanNotDelete`, and `ReadOnly`.<br/>  - `kind` - (Required) The type of lock. Possible values are `\"CanNotDelete\"` and `\"ReadOnly\"`.<br/>  - `name` - (Optional) The name of the lock. If not specified, a name will be generated based on the `kind` value. Changing this forces the creation of a new resource.<br/>- `tags` - (Optional) A mapping of tags to assign to the private endpoint.<br/>- `subnet_resource_id` - The resource ID of the subnet to deploy the private endpoint in.<br/>- `private_dns_zone_group_name` - (Optional) The name of the private DNS zone group. One will be generated if not set.<br/>- `private_dns_zone_resource_ids` - (Optional) A set of resource IDs of private DNS zones to associate with the private endpoint. If not set, no zone groups will be created and the private endpoint will not be associated with any private DNS zones. DNS records must be managed external to this module.<br/>- `application_security_group_resource_ids` - (Optional) A map of resource IDs of application security groups to associate with the private endpoint. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/>- `private_service_connection_name` - (Optional) The name of the private service connection. One will be generated if not set.<br/>- `network_interface_name` - (Optional) The name of the network interface. One will be generated if not set.<br/>- `location` - (Optional) The Azure location where the resources will be deployed. Defaults to the location of the resource group.<br/>- `resource_group_name` - (Optional) The resource group where the resources will be deployed. Defaults to the resource group of the Container Registry.<br/>- `ip_configurations` - (Optional) A map of IP configurations to create on the private endpoint. If not specified the platform will create one. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/>  - `name` - The name of the IP configuration.<br/>  - `private_ip_address` - The private IP address of the IP configuration. | <pre>map(object({<br/>    name = optional(string, null)<br/>    role_assignments = optional(map(object({<br/>      role_definition_id_or_name             = string<br/>      principal_id                           = string<br/>      description                            = optional(string, null)<br/>      skip_service_principal_aad_check       = optional(bool, false)<br/>      condition                              = optional(string, null)<br/>      condition_version                      = optional(string, null)<br/>      delegated_managed_identity_resource_id = optional(string, null)<br/>      principal_type                         = optional(string, null)<br/>    })), {})<br/>    lock = optional(object({<br/>      kind = string<br/>      name = optional(string, null)<br/>    }), null)<br/>    tags                                    = optional(map(string), null)<br/>    subnet_resource_id                      = string<br/>    private_dns_zone_group_name             = optional(string, "default")<br/>    private_dns_zone_resource_ids           = optional(set(string), [])<br/>    application_security_group_associations = optional(map(string), {})<br/>    private_service_connection_name         = optional(string, null)<br/>    network_interface_name                  = optional(string, null)<br/>    location                                = optional(string, null)<br/>    resource_group_name                     = optional(string, null)<br/>    ip_configurations = optional(map(object({<br/>      name               = string<br/>      private_ip_address = string<br/>    })), {})<br/>  }))</pre> | `{}` |
| <a name="input_private_endpoints_manage_dns_zone_group"></a> [private\_endpoints\_manage\_dns\_zone\_group](#input\_private\_endpoints\_manage\_dns\_zone\_group) | Whether to manage private DNS zone groups with this module. If set to false, you must manage private DNS zone groups externally, e.g. using Azure Policy. | `bool` | `true` |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Specifies whether public access is permitted. | `bool` | `true` |
| <a name="input_quarantine_policy_enabled"></a> [quarantine\_policy\_enabled](#input\_quarantine\_policy\_enabled) | Specifies whether the quarantine policy is enabled. | `bool` | `false` |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group where resources will be created | `string` | n/a |
| <a name="input_retention_policy_in_days"></a> [retention\_policy\_in\_days](#input\_retention\_policy\_in\_days) | If enabled, this retention policy will purge an untagged manifest after a specified number of days.<br/><br/>- `days` - (Optional) The number of days before the policy Defaults to 7 days. | `number` | `7` |
| <a name="input_role_assignments"></a> [role\_assignments](#input\_role\_assignments) | A map of role assignments to create on the <RESOURCE>. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/><br/>  - `role_definition_id_or_name` - The ID or name of the role definition to assign to the principal.<br/>  - `principal_id` - The ID of the principal to assign the role to.<br/>  - `description` - (Optional) The description of the role assignment.<br/>  - `skip_service_principal_aad_check` - (Optional) If set to true, skips the Azure Active Directory check for the service principal in the tenant. Defaults to false.<br/>  - `condition` - (Optional) The condition which will be used to scope the role assignment.<br/>  - `condition_version` - (Optional) The version of the condition syntax. Leave as `null` if you are not using a condition, if you are then valid values are '2.0'.<br/>  - `delegated_managed_identity_resource_id` - (Optional) The delegated Azure Resource Id which contains a Managed Identity. Changing this forces a new resource to be created. This field is only used in cross-tenant scenario.<br/>  - `principal_type` - (Optional) The type of the `principal_id`. Possible values are `User`, `Group` and `ServicePrincipal`. It is necessary to explicitly set this attribute when creating role assignments if the principal creating the assignment is constrained by ABAC rules that filters on the PrincipalType attribute.<br/><br/>  > Note: only set `skip_service_principal_aad_check` to true if you are assigning a role to a service principal. | <pre>map(object({<br/>    role_definition_id_or_name             = string<br/>    principal_id                           = string<br/>    scope                                  = string<br/>    description                            = optional(string, null)<br/>    skip_service_principal_aad_check       = optional(bool, false)<br/>    condition                              = optional(string, null)<br/>    condition_version                      = optional(string, null)<br/>    delegated_managed_identity_resource_id = optional(string, null)<br/>    principal_type                         = optional(string, null)<br/>  }))</pre> | `{}` |
| <a name="input_sku"></a> [sku](#input\_sku) | The SKU name of the Container Registry. Default is `Premium`. `Possible values are `Basic`, `Standard` and `Premium`.` | `string` | `"Premium"` |
| <a name="input_tags"></a> [tags](#input\_tags) | Map of tags to be applied to all resources | `map(string)` | <pre>{<br/>  "business_unit": "banking",<br/>  "customer": "myridius",<br/>  "environment": "dev",<br/>  "owner": "devops",<br/>  "product": "gh",<br/>  "region": "eastus2"<br/>}</pre> |
| <a name="input_user_preferred_index"></a> [user\_preferred\_index](#input\_user\_preferred\_index) | A value to append at the end of the name | `number` | `1` |
| <a name="input_zone_redundancy_enabled"></a> [zone\_redundancy\_enabled](#input\_zone\_redundancy\_enabled) | Specifies whether zone redundancy is enabled.  Modifying this forces a new resource to be created. | `bool` | `true` |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_login_server"></a> [login\_server](#output\_login\_server) | The URL that can be used to log into the container registry. |
| <a name="output_name"></a> [name](#output\_name) | The name of the parent resource. |
| <a name="output_private_endpoints"></a> [private\_endpoints](#output\_private\_endpoints) | A map of private endpoints. The map key is the supplied input to var.private\_endpoints. The map value is the entire azurerm\_private\_endpoint resource. |
| <a name="output_resource"></a> [resource](#output\_resource) | This is the full output for the resource. |
| <a name="output_resource_id"></a> [resource\_id](#output\_resource\_id) | The resource id for the parent resource. |
| <a name="output_system_assigned_mi_principal_id"></a> [system\_assigned\_mi\_principal\_id](#output\_system\_assigned\_mi\_principal\_id) | The system assigned managed identity principal ID of the parent resource. |

# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v1.0.0] - 2025-07-17
### Added
- Initial release of the module to create:
  - Azure Container Registry with configurable SKU (`Basic`, `Standard`, `Premium`), admin access, anonymous pull, export policy, quarantine policy, and content trust controls
  - Premium SKU features: zone redundancy, untagged image retention policy, and data endpoint support
  - Geo-replication across multiple Azure regions with per-replica zone redundancy and regional endpoint configuration
  - Customer-managed key (CMK) encryption via Azure Key Vault using a user-assigned managed identity
  - System-assigned and user-assigned managed identity support
  - Network rule set for IP-based access restrictions with configurable default action (Premium SKU required)
  - Private endpoints for secure, private network access with managed and unmanaged DNS zone group modes
  - Application Security Group (ASG) associations on private endpoints
  - Azure Monitor diagnostic settings with support for Log Analytics, Event Hub, and Storage
  - Role assignments (RBAC) for fine-grained access control; supports role name or full definition ID, conditions, and delegated managed identity
  - Optional resource-level lock (`CanNotDelete` or `ReadOnly`) for protection of critical environments
  - Standard naming convention (`cr<product><env><index>`) with optional custom name override; name validated to 5–50 lowercase alphanumeric characters
  - Lifecycle preconditions enforcing Premium SKU requirement for zone redundancy, network rule sets, and CMK encryption

<!-- END_TF_DOCS -->
