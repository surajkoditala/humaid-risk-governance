<!-- BEGIN_TF_DOCS -->


## Introduction

This Terraform module provisions an **Azure Container App** in a flexible, and secure manner.

## 📘 Overview

This module enables:

- Deployment of an Azure Container App with revision support
- Fine-grained control over container templates, init containers, scale rules, and probes
- Support for both **System Assigned** and **User Assigned** managed identities
- Ingress configuration with HTTPS, transport modes, and traffic splitting
- Optional private container registry integration (ACR) with identity support
- Volume and volume mount support for persistent data use cases

#Examples

#Basic Example
```hcl
#CAE
module "container_app_env" {
  source = "../../../terraform-azure-containerappsenvironment"

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

#ACR
resource "azurerm_private_dns_zone" "this" {
  name                = "privatelink.azurecr.io"
  resource_group_name = "rg-gh-dev-sandbox"
}

resource "azurerm_private_dns_zone_virtual_network_link" "example" {
  name                  = "dns-zone-vnet-link"
  resource_group_name   = "rg-gh-dev-sandbox"
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox"
}

module "containerregistry" {
  source = "../../../terraform-azure-containerregistry"

  location                      = "eastus2"
  resource_group_name           = "rg-gh-dev-sandbox"
  public_network_access_enabled = true
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

resource "azurerm_user_assigned_identity" "this" {
  location            = "eastus2"
  name                = "id-acr-gh-dev-sandbox"
  resource_group_name = "rg-gh-dev-sandbox"
}

resource "azurerm_role_assignment" "example_pull" {
  scope                = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452"
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

resource "azurerm_role_assignment" "example_push" {
  scope                = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452"
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

#Containerapp
module "container_app" {
  source = "../.."

  # Can be used for Prod resource
  # lock = {
  #   name = "lock-ca-oscarr-dev-sandbox" # optional
  #   kind = "CanNotDelete"
  # }

  container_app_service_name   = "gh-integration"
  container_app_environment_id = module.container_app_env.container_app_environment_id
  resource_group_name          = "rg-gh-dev-sandbox"
  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }

  template = {
    container = [
      {
        name   = "ca-gh-integration-service-dev-sandbox"
        memory = "0.5"
        cpu    = 0.25
        image  = "crghdev01.azurecr.io/hello-dotnet-http:v1"
      }
    ]
  }

  ingress = {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = 8080
    cors = {
      allowed_origins = ["*"]
      allowed_methods = ["*"]
      allowed_headers = ["*"]
      exposed_headers = ["*"]
    }

    traffic_weight = [
      {
        latest_revision = true
        percentage      = 100
      }
    ]
  }

  managed_identities = {
    user_assigned_resource_ids = toset([azurerm_user_assigned_identity.this.id])
  }

  registry = [
    {
      server   = "crghdev01.azurecr.io"
      identity = azurerm_user_assigned_identity.this.id
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

#Environment variables Example
```hcl
#CAE
module "container_app_env" {
  source = "../../../terraform-azure-containerappsenvironment"

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

#ACR
resource "azurerm_private_dns_zone" "this" {
  name                = "privatelink.azurecr.io"
  resource_group_name = "rg-gh-dev-sandbox"
}

resource "azurerm_private_dns_zone_virtual_network_link" "example" {
  name                  = "dns-zone-vnet-link"
  resource_group_name   = "rg-gh-dev-sandbox"
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox"
}

module "containerregistry" {
  source = "../../../terraform-azure-containerregistry"

  location                      = "eastus2"
  resource_group_name           = "rg-gh-dev-sandbox"
  public_network_access_enabled = true
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

resource "azurerm_user_assigned_identity" "this" {
  location            = "eastus2"
  name                = "id-acr-gh-dev-sandbox"
  resource_group_name = "rg-gh-dev-sandbox"
}

resource "azurerm_role_assignment" "example_pull" {
  scope                = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452"
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

resource "azurerm_role_assignment" "example_push" {
  scope                = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452"
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

#role assignment for system identity
resource "azurerm_role_assignment" "example_pull_sa" {
  scope                = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452"
  role_definition_name = "AcrPull"
  principal_id         = module.container_app.container_app_system_assigned_identity_principal_id
}

resource "azurerm_role_assignment" "example_push_sa" {
  scope                = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452"
  role_definition_name = "AcrPush"
  principal_id         = module.container_app.container_app_system_assigned_identity_principal_id
}

resource "azurerm_role_assignment" "example_storage_sa" {
  scope                = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.container_app.container_app_system_assigned_identity_principal_id
}

resource "azurerm_role_assignment" "example_contrib_sa" {
  scope                = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452"
  role_definition_name = "Contributor"
  principal_id         = module.container_app.container_app_system_assigned_identity_principal_id
}

#Containerapp
module "container_app" {
  source = "../.."

  # Can be used for Prod resource
  # lock = {
  #   name = "lock-ca-oscarr-dev-sandbox" # optional
  #   kind = "CanNotDelete"
  # }

  container_app_service_name   = "gh-integration"
  container_app_environment_id = module.container_app_env.container_app_environment_id
  resource_group_name          = "rg-gh-dev-sandbox"
  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }

  template = {
    container = [
      {
        name   = "ca-gh-integration-service-dev-sandbox"
        memory = "0.5"
        cpu    = 0.25
        image  = "crghdev01.azurecr.io/hello-dotnet-http:v1"
        env = [
          {
            name  = "PEP-SQL-SERVER"
            value = ""
          },
          {
            name  = "DATABASE-NAME"
            value = ""
          },
          {
            name  = "PEP-KEY-VAULT"
            value = ""
          },
          {
            name  = "PEP-STORAGE-ACCOUNT"
            value = ""
          },
          {
            name  = "AI-INSTRUMENTATION-KEY"
            value = ""
          }
        ]
      }
    ]
  }

  ingress = {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = 8080
    cors = {
      allowed_origins = ["*"]
      allowed_methods = ["*"]
      allowed_headers = ["*"]
      exposed_headers = ["*"]
    }

    traffic_weight = [
      {
        latest_revision = true
        percentage      = 100
      }
    ]
  }

  managed_identities = {
    user_assigned_resource_ids = toset([azurerm_user_assigned_identity.this.id])
  }

  registry = [
    {
      server   = "crghdev01.azurecr.io"
      identity = azurerm_user_assigned_identity.this.id
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

#System assigned identity with role assignments Example
```hcl
#CAE
module "container_app_env" {
  source = "../../../terraform-azure-containerappsenvironment"

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

#ACR
resource "azurerm_private_dns_zone" "this" {
  name                = "privatelink.azurecr.io"
  resource_group_name = "rg-gh-dev-sandbox"
}

resource "azurerm_private_dns_zone_virtual_network_link" "example" {
  name                  = "dns-zone-vnet-link"
  resource_group_name   = "rg-gh-dev-sandbox"
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox"
}

module "containerregistry" {
  source = "../../../terraform-azure-containerregistry"

  location                      = "eastus2"
  resource_group_name           = "rg-gh-dev-sandbox"
  public_network_access_enabled = true
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

resource "azurerm_user_assigned_identity" "this" {
  location            = "eastus2"
  name                = "id-acr-gh-dev-sandbox"
  resource_group_name = "rg-gh-dev-sandbox"
}

resource "azurerm_role_assignment" "example_pull" {
  scope                = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452"
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

resource "azurerm_role_assignment" "example_push" {
  scope                = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452"
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

#Containerapp
module "container_app" {
  source = "../.."

  # Can be used for Prod resource
  # lock = {
  #   name = "lock-ca-oscarr-dev-sandbox" # optional
  #   kind = "CanNotDelete"
  # }

  container_app_service_name   = "gh-integration"
  container_app_environment_id = module.container_app_env.container_app_environment_id
  resource_group_name          = "rg-gh-dev-sandbox"
  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }

  template = {
    container = [
      {
        name   = "ca-gh-integration-service-dev-sandbox"
        memory = "0.5"
        cpu    = 0.25
        image  = "crghdev01.azurecr.io/hello-dotnet-http:v1"
      }
    ]
  }

  ingress = {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = 8080
    cors = {
      allowed_origins = ["*"]
      allowed_methods = ["*"]
      allowed_headers = ["*"]
      exposed_headers = ["*"]
    }

    traffic_weight = [
      {
        latest_revision = true
        percentage      = 100
      }
    ]
  }

  managed_identities = {
    user_assigned_resource_ids = toset([azurerm_user_assigned_identity.this.id])
  }

  registry = [
    {
      server   = "crghdev01.azurecr.io"
      identity = azurerm_user_assigned_identity.this.id
    }
  ]

  role_assignments = { #Role assignments for the system identity - to access KV, Storage and PG SQL db
    "kv1" = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = module.container_app.container_app_system_assigned_identity_principal_id
      scope                      = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452" #In reality, the scope will be limited to the actual resource like kv, stoarge and sql db
    }
    "kv2" = {
      role_definition_id_or_name = "Key Vault Certificate User"
      principal_id               = module.container_app.container_app_system_assigned_identity_principal_id
      scope                      = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452" #In reality, the scope will be limited to the actual resource like kv, stoarge and sql db
    }
    "storage_reader" = {
      role_definition_id_or_name = "Storage Blob Data Reader"
      principal_id               = module.container_app.container_app_system_assigned_identity_principal_id
      scope                      = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452" #In reality, the scope will be limited to the actual resource like kv, stoarge and sql db
    }
    "storage_contributor" = {
      role_definition_id_or_name = "Storage Blob Data Contributor"
      principal_id               = module.container_app.container_app_system_assigned_identity_principal_id
      scope                      = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452" #In reality, the scope will be limited to the actual resource like kv, stoarge and sql db
    }
    "contrib" = {
      role_definition_id_or_name = "Contributor"
      principal_id               = module.container_app.container_app_system_assigned_identity_principal_id
      scope                      = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452" #In reality, the scope will be limited to the actual resource like kv, stoarge and sql db
    }
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

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9, < 2.0 |
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
| [azurerm_container_app.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app) | resource |
| [azurerm_management_lock.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_lock) | resource |
| [azurerm_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| <a name="input_container_app_environment_id"></a> [container\_app\_environment\_id](#input\_container\_app\_environment\_id) | ID of the Azure Container App Environment. | `string` | n/a |
| <a name="input_container_app_service_name"></a> [container\_app\_service\_name](#input\_container\_app\_service\_name) | Name of the Azure Container App Service. Use either this variable or the 'name' variable, not both. If this is used, it will follow the naming convention 'ca-<container\_app\_service\_name>-<environment>'. | `string` | n/a |
| <a name="input_ingress"></a> [ingress](#input\_ingress) | Optional ingress configuration. | <pre>object({<br/>    target_port = number<br/>    traffic_weight = optional(list(object({ #Only applies if revision_mode is set to multiple<br/>      percentage      = number<br/>      label           = optional(string)<br/>      latest_revision = optional(bool, true)<br/>      revision_suffix = optional(string) #If latest_revision is false, the revision_suffix shall be specified.<br/>    })), [{ percentage = 100 }])<br/>    external_enabled           = optional(bool, true)<br/>    allow_insecure_connections = optional(bool, false)<br/>    client_certificate_mode    = optional(string, "ignore") #require, accept, ignore<br/>    cors = optional(object({<br/>      allowed_origins    = list(string)<br/>      allowed_methods    = optional(list(string))<br/>      allowed_headers    = optional(list(string))<br/>      exposed_headers    = optional(list(string))<br/>      max_age_in_seconds = optional(number)<br/>    }), null)<br/>    fqdn = optional(string)<br/>    ip_security_restriction = optional(object({<br/>      ip_address_range = string<br/>      name             = string<br/>      action           = string #Allow or Deny<br/>    }))<br/>    exposed_port = optional(number)         #can only be specified if transport is set to tcp<br/>    transport    = optional(string, "auto") #auto, http, http2 and tcp. Defaults to auto.<br/>  })</pre> | <pre>{<br/>  "target_port": 443<br/>}</pre> |
| <a name="input_lock"></a> [lock](#input\_lock) | Controls the Resource Lock configuration for this resource. The following properties can be specified:<br/><br/>  - `kind` - (Required) The type of lock. Possible values are `\"CanNotDelete\"` and `\"ReadOnly\"`.<br/>  - `name` - (Optional) The name of the lock. If not specified, a name will be generated based on the `kind` value. Changing this forces the creation of a new resource. | <pre>object({<br/>    kind = string<br/>    name = optional(string, null)<br/>  })</pre> | `null` |
| <a name="input_managed_identities"></a> [managed\_identities](#input\_managed\_identities) | Controls the Managed Identity configuration on this resource. The following properties can be specified:<br/><br/>  - `system_assigned` - (Optional) Specifies if the System Assigned Managed Identity should be enabled.<br/>  - `user_assigned_resource_ids` - (Optional) Specifies a list of User Assigned Managed Identity resource IDs to be assigned to this resource. | <pre>object({<br/>    system_assigned            = optional(bool, false)<br/>    user_assigned_resource_ids = optional(set(string), [])<br/>  })</pre> | `{}` |
| <a name="input_max_inactive_revisions"></a> [max\_inactive\_revisions](#input\_max\_inactive\_revisions) | The maximum of inactive revisions allowed for this Container App. | `number` | `10` |
| <a name="input_name"></a> [name](#input\_name) | Custom name of the container app. Use either this variable or the 'container\_app\_service\_name' variable, not both. This can be used for passing a specific name to the container app. | `string` | `null` |
| <a name="input_registry"></a> [registry](#input\_registry) | Optional list of container registries. | <pre>list(object({<br/>    server               = string<br/>    username             = optional(string, "")<br/>    password_secret_name = optional(string, "")<br/>    identity             = optional(string, "")<br/>  }))</pre> | `[]` |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group where resources will be created | `string` | n/a |
| <a name="input_revision_mode"></a> [revision\_mode](#input\_revision\_mode) | Revision mode for the container app. | `string` | `"Single"` |
| <a name="input_role_assignments"></a> [role\_assignments](#input\_role\_assignments) | A map of role assignments to create on the <RESOURCE>. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/><br/>  - `role_definition_id_or_name` - The ID or name of the role definition to assign to the principal.<br/>  - `principal_id` - The ID of the principal to assign the role to.<br/>  - `description` - (Optional) The description of the role assignment.<br/>  - `skip_service_principal_aad_check` - (Optional) If set to true, skips the Azure Active Directory check for the service principal in the tenant. Defaults to false.<br/>  - `condition` - (Optional) The condition which will be used to scope the role assignment.<br/>  - `condition_version` - (Optional) The version of the condition syntax. Leave as `null` if you are not using a condition, if you are then valid values are '2.0'.<br/>  - `delegated_managed_identity_resource_id` - (Optional) The delegated Azure Resource Id which contains a Managed Identity. Changing this forces a new resource to be created. This field is only used in cross-tenant scenario.<br/>  - `principal_type` - (Optional) The type of the `principal_id`. Possible values are `User`, `Group` and `ServicePrincipal`. It is necessary to explicitly set this attribute when creating role assignments if the principal creating the assignment is constrained by ABAC rules that filters on the PrincipalType attribute.<br/><br/>  > Note: only set `skip_service_principal_aad_check` to true if you are assigning a role to a service principal. | <pre>map(object({<br/>    role_definition_id_or_name             = string<br/>    principal_id                           = string<br/>    scope                                  = string<br/>    description                            = optional(string, null)<br/>    skip_service_principal_aad_check       = optional(bool, false)<br/>    condition                              = optional(string, null)<br/>    condition_version                      = optional(string, null)<br/>    delegated_managed_identity_resource_id = optional(string, null)<br/>    principal_type                         = optional(string, null)<br/>  }))</pre> | `{}` |
| <a name="input_secret"></a> [secret](#input\_secret) | Optional secrets for the container app. | <pre>map(object({<br/>    name                = optional(string)     # Secret name<br/>    value               = optional(string, "") # Inline secret value<br/>    identity            = optional(string, "") # User Assigned Identity or "System"<br/>    key_vault_secret_id = optional(string, "") # Full Key Vault secret ID<br/>  }))</pre> | `{}` |
| <a name="input_tags"></a> [tags](#input\_tags) | Map of tags to be applied to all resources | `map(string)` | <pre>{<br/>  "business_unit": "banking",<br/>  "customer": "myridius",<br/>  "environment": "dev",<br/>  "owner": "devops",<br/>  "product": "gh",<br/>  "region": "eastus2"<br/>}</pre> |
| <a name="input_template"></a> [template](#input\_template) | - `max_replicas` - (Optional) The maximum number of replicas for this container.<br/>        - `min_replicas` - (Optional) The minimum number of replicas for this container.<br/>        - `revision_suffix` - (Optional) The suffix for the revision. This value must be unique for the lifetime of the Resource. If omitted the service will use a hash function to create one.<br/><br/>        ---<br/>        `azure_queue_scale_rule` block supports the following:<br/>        - `name` - (Required) The name of the Scaling Rule<br/>        - `queue_length` - (Required) The value of the length of the queue to trigger scaling actions.<br/>        - `queue_name` - (Required) The name of the Azure Queue<br/><br/>        ---<br/>        `authentication` block supports the following:<br/>        - `secret_name` - (Required) The name of the Container App Secret to use for this Scale Rule Authentication.<br/>        - `trigger_parameter` - (Required) The Trigger Parameter name to use the supply the value retrieved from the `secret_name`.<br/><br/>        ---<br/>        `containers` block supports the following:<br/>        - `args` - (Optional) A list of extra arguments to pass to the container.<br/>        - `command` - (Optional) A command to pass to the container to override the default. This is provided as a list of command line elements without spaces.<br/>        - `cpu` - (Required) The amount of vCPU to allocate to the container. Possible values include `0.25`, `0.5`, `0.75`, `1.0`, `1.25`, `1.5`, `1.75`, and `2.0`. When there's a workload profile specified, there's no such constraint.<br/>        - `image` - (Required) The image to use to create the container.<br/>        - `memory` - (Required) The amount of memory to allocate to the container. Possible values are `0.5Gi`, `1Gi`, `1.5Gi`, `2Gi`, `2.5Gi`, `3Gi`, `3.5Gi` and `4Gi`. When there's a workload profile specified, there's no such constraint.<br/>        - `name` - (Required) The name of the container<br/><br/>        ---<br/>        `env` block supports the following:<br/>        - `name` - (Required) The name of the environment variable for the container.<br/>        - `secret_name` - (Optional) The name of the secret that contains the value for this environment variable.<br/>        - `value` - (Optional) The value for this environment variable.<br/><br/>        ---<br/>        `liveness_probes` block supports the following:<br/>        - `failure_count_threshold` - (Optional) The number of consecutive failures required to consider this probe as failed. Possible values are between `1` and `10`. Defaults to `3`.<br/>        - `host` - (Optional) The probe hostname. Defaults to the pod IP address. Setting a value for `Host` in `headers` can be used to override this for `HTTP` and `HTTPS` type probes.<br/>        - `initial_delay` - (Optional) The time in seconds to wait after the container has started before the probe is started.<br/>        - `interval_seconds` - (Optional) How often, in seconds, the probe should run. Possible values are in the range `1`<br/>        - `path` - (Optional) The URI to use with the `host` for http type probes. Not valid for `TCP` type probes. Defaults to `/`.<br/>        - `port` - (Required) The port number on which to connect. Possible values are between `1` and `65535`.<br/>        - `timeout` - (Optional) Time in seconds after which the probe times out. Possible values are in the range `1`<br/>        - `transport` - (Required) Type of probe. Possible values are `TCP`, `HTTP`, and `HTTPS`.<br/><br/>        ---<br/>        `header` block supports the following:<br/>        - `name` - (Required) The HTTP Header Name.<br/>        - `value` - (Required) The HTTP Header value.<br/><br/>        ---<br/>        `readiness_probes` block supports the following:<br/>        - `failure_count_threshold` - (Optional) The number of consecutive failures required to consider this probe as failed. Possible values are between `1` and `10`. Defaults to `3`.<br/>        - `host` - (Optional) The probe hostname. Defaults to the pod IP address. Setting a value for `Host` in `headers` can be used to override this for `HTTP` and `HTTPS` type probes.<br/>        - `initial_delay` - (Optional) The number of seconds elapsed after the container has started before the probe is initiated. Possible values are between `0` and `60`. Defaults to `0` seconds.<br/>        - `interval_seconds` - (Optional) How often, in seconds, the probe should run. Possible values are between `1` and `240`. Defaults to `10`<br/>        - `path` - (Optional) The URI to use for http type probes. Not valid for `TCP` type probes. Defaults to `/`.<br/>        - `port` - (Required) The port number on which to connect. Possible values are between `1` and `65535`.<br/>        - `success_count_threshold` - (Optional) The number of consecutive successful responses required to consider this probe as successful. Possible values are between `1` and `10`. Defaults to `3`.<br/>        - `timeout` - (Optional) Time in seconds after which the probe times out. Possible values are in the range `1`<br/>        - `transport` - (Required) Type of probe. Possible values are `TCP`, `HTTP`, and `HTTPS`.<br/><br/>        ---<br/>        `header` block supports the following:<br/>        - `name` - (Required) The HTTP Header Name.<br/>        - `value` - (Required) The HTTP Header value.<br/><br/>        ---<br/>        `startup_probes` block supports the following:<br/>        - `failure_count_threshold` - (Optional) The number of consecutive failures required to consider this probe as failed. Possible values are between `1` and `10`. Defaults to `3`.<br/>        - `host` - (Optional) The value for the host header which should be sent with this probe. If unspecified, the IP Address of the Pod is used as the host header. Setting a value for `Host` in `headers` can be used to override this for `HTTP` and `HTTPS` type probes.<br/>        - `initial_delay` - (Optional) The number of seconds elapsed after the container has started before the probe is initiated. Possible values are between `0` and `60`. Defaults to `0` seconds.<br/>        - `interval_seconds` - (Optional) How often, in seconds, the probe should run. Possible values are between `1` and `240`. Defaults to `10`<br/>        - `path` - (Optional) The URI to use with the `host` for http type probes. Not valid for `TCP` type probes. Defaults to `/`.<br/>        - `port` - (Required) The port number on which to connect. Possible values are between `1` and `65535`.<br/>        - `timeout` - (Optional) Time in seconds after which the probe times out. Possible values are in the range `1`<br/>        - `transport` - (Required) Type of probe. Possible values are `TCP`, `HTTP`, and `HTTPS`.<br/><br/>        ---<br/>        `header` block supports the following:<br/>        - `name` - (Required) The HTTP Header Name.<br/>        - `value` - (Required) The HTTP Header value.<br/><br/>        ---<br/>        `volume_mounts` block supports the following:<br/>        - `name` - (Required) The name of the Volume to be mounted in the container.<br/>        - `path` - (Required) The path in the container at which to mount this volume.<br/><br/>        ---<br/>        `custom_scale_rule` block supports the following:<br/>        - `custom_rule_type` - (Required) The Custom rule type. Possible values include: `activemq`, `artemis-queue`, `kafka`, `pulsar`, `aws-cloudwatch`, `aws-dynamodb`, `aws-dynamodb-streams`, `aws-kinesis-stream`, `aws-sqs-queue`, `azure-app-insights`, `azure-blob`, `azure-data-explorer`, `azure-eventhub`, `azure-log-analytics`, `azure-monitor`, `azure-pipelines`, `azure-servicebus`, `azure-queue`, `cassandra`, `cpu`, `cron`, `datadog`, `elasticsearch`, `external`, `external-push`, `gcp-stackdriver`, `gcp-storage`, `gcp-pubsub`, `graphite`, `http`, `huawei-cloudeye`, `ibmmq`, `influxdb`, `kubernetes-workload`, `liiklus`, `memory`, `metrics-api`, `mongodb`, `mssql`, `mysql`, `nats-jetstream`, `stan`, `tcp`, `new-relic`, `openstack-metric`, `openstack-swift`, `postgresql`, `predictkube`, `prometheus`, `rabbitmq`, `redis`, `redis-cluster`, `redis-sentinel`, `redis-streams`, `redis-cluster-streams`, `redis-sentinel-streams`, `selenium-grid`,`solace-event-queue`, and `github-runner`.<br/>        - `metadata` - (Required)<br/>        - `name` - (Required) The name of the Scaling Rule<br/><br/>        ---<br/>        `authentication` block supports the following:<br/>        - `secret_name` - (Required) The name of the Container App Secret to use for this Scale Rule Authentication.<br/>        - `trigger_parameter` - (Required) The Trigger Parameter name to use the supply the value retrieved from the `secret_name`.<br/><br/>        ---<br/>        `http_scale_rule` block supports the following:<br/>        - `concurrent_requests` - (Required)<br/>        - `name` - (Required) The name of the Scaling Rule<br/><br/>        ---<br/>        `authentication` block supports the following:<br/>        - `secret_name` - (Required) The name of the Container App Secret to use for this Scale Rule Authentication.<br/>        - `trigger_parameter` - (Required) The Trigger Parameter name to use the supply the value retrieved from the `secret_name`.<br/><br/>        ---<br/>        `init_container` block supports the following:<br/>        - `args` - (Optional) A list of extra arguments to pass to the container.<br/>        - `command` - (Optional) A command to pass to the container to override the default. This is provided as a list of command line elements without spaces.<br/>        - `cpu` - (Optional) The amount of vCPU to allocate to the container. Possible values include `0.25`, `0.5`, `0.75`, `1.0`, `1.25`, `1.5`, `1.75`, and `2.0`. When there's a workload profile specified, there's no such constraint.<br/>        - `image` - (Required) The image to use to create the container.<br/>        - `memory` - (Optional) The amount of memory to allocate to the container. Possible values are `0.5Gi`, `1Gi`, `1.5Gi`, `2Gi`, `2.5Gi`, `3Gi`, `3.5Gi` and `4Gi`. When there's a workload profile specified, there's no such constraint.<br/>        - `name` - (Required) The name of the container<br/><br/>        ---<br/>        `env` block supports the following:<br/>        - `name` - (Required) The name of the environment variable for the container.<br/>        - `secret_name` - (Optional) The name of the secret that contains the value for this environment variable.<br/>        - `value` - (Optional) The value for this environment variable.<br/><br/>        ---<br/>        `volume_mounts` block supports the following:<br/>        - `name` - (Required) The name of the Volume to be mounted in the container.<br/>        - `path` - (Required) The path in the container at which to mount this volume.<br/><br/>        ---<br/>        `tcp_scale_rule` block supports the following:<br/>        - `concurrent_requests` - (Required)<br/>        - `name` - (Required) The name of the Scaling Rule<br/><br/>        ---<br/>        `authentication` block supports the following:<br/>        - `secret_name` - (Required) The name of the Container App Secret to use for this Scale Rule Authentication.<br/>        - `trigger_parameter` - (Required) The Trigger Parameter name to use the supply the value retrieved from the `secret_name`.<br/><br/>        ---<br/>        `volume` block supports the following:<br/>        - `name` - (Required) The name of the volume.<br/>        - `storage_name` - (Optional) The name of the `AzureFile` storage.<br/>        - `storage_type` - (Optional) The type of storage volume. Possible values are `AzureFile`, `EmptyDir` and `Secret`. Defaults to `EmptyDir`. | <pre>object({<br/>    max_replicas                     = optional(number, 2) #for dev, we will keep at 2<br/>    min_replicas                     = optional(number, 0)<br/>    revision_suffix                  = optional(string, "")<br/>    termination_grace_period_seconds = optional(number, 0)<br/><br/>    container = list(object({<br/>      args    = optional(list(string))<br/>      command = optional(list(string))<br/>      cpu     = number<br/>      image   = string<br/>      memory  = string<br/>      name    = string<br/>      env = optional(list(object({<br/>        name        = string<br/>        secret_name = optional(string)<br/>        value       = optional(string)<br/>      })), [])<br/>      liveness_probe = optional(list(object({<br/>        failure_count_threshold          = optional(number)<br/>        host                             = optional(string)<br/>        initial_delay                    = optional(number)<br/>        interval_seconds                 = optional(number)<br/>        path                             = optional(string)<br/>        port                             = number<br/>        termination_grace_period_seconds = optional(number)<br/>        timeout                          = optional(number)<br/>        transport                        = string<br/>        header = optional(object({<br/>          name  = string<br/>          value = string<br/>        }))<br/>      })), [])<br/>      startup_probe = optional(list(object({<br/>        failure_count_threshold          = optional(number)<br/>        host                             = optional(string)<br/>        initial_delay                    = optional(number)<br/>        interval_seconds                 = optional(number)<br/>        path                             = optional(string)<br/>        port                             = number<br/>        termination_grace_period_seconds = optional(number)<br/>        timeout                          = optional(number)<br/>        transport                        = string<br/>        header = optional(object({<br/>          name  = string<br/>          value = string<br/>        }))<br/>      })), [])<br/>      volume_mounts = optional(list(object({<br/>        name     = string<br/>        path     = string<br/>        sub_path = optional(string)<br/>      })), [])<br/>    }))<br/><br/>    init_container = optional(list(object({<br/>      args    = optional(list(string))<br/>      command = optional(list(string))<br/>      cpu     = optional(number)<br/>      image   = string<br/>      memory  = optional(string)<br/>      name    = string<br/>      env = optional(list(object({<br/>        name        = string<br/>        secret_name = optional(string)<br/>        value       = optional(string)<br/>      })), [])<br/>      volume_mounts = optional(list(object({<br/>        name     = string<br/>        path     = string<br/>        sub_path = optional(string)<br/>      })), [])<br/>    })), [])<br/><br/>    tcp_scale_rule = optional(list(object({<br/>      concurrent_requests = string<br/>      name                = string<br/>      identity            = optional(string)<br/>      metadata            = optional(map(string))<br/>      authentication = optional(object({<br/>        secret_name       = string<br/>        trigger_parameter = optional(string)<br/>      }))<br/>    })), [])<br/><br/>    http_scale_rule = optional(list(object({<br/>      concurrent_requests = string<br/>      name                = string<br/>      identity            = optional(string)<br/>      metadata            = optional(map(string))<br/>      authentication = optional(object({<br/>        secret_name       = string<br/>        trigger_parameter = optional(string)<br/>      }))<br/>    })), [])<br/><br/>    custom_scale_rule = optional(list(object({<br/>      custom_rule_type = string<br/>      metadata         = map(string)<br/>      name             = string<br/>      identity         = optional(string)<br/>      authentication = optional(object({<br/>        secret_name       = string<br/>        trigger_parameter = string<br/>      }))<br/>    })), [])<br/><br/>    volume = optional(list(object({<br/>      mount_options = optional(string)<br/>      name          = string<br/>      secrets = optional(object({<br/>        path        = string<br/>        secret_name = string<br/>      }))<br/>      storage_name = optional(string)<br/>      storage_type = optional(string)<br/>    })), [])<br/>  })</pre> | n/a |
| <a name="input_user_preferred_index"></a> [user\_preferred\_index](#input\_user\_preferred\_index) | A value to append at the end of the name | `number` | `1` |
| <a name="input_workload_profile_name"></a> [workload\_profile\_name](#input\_workload\_profile\_name) | Workload profile for the container app. | `string` | `"Consumption"` |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_container_app_fqdn"></a> [container\_app\_fqdn](#output\_container\_app\_fqdn) | The FQDN of the container app |
| <a name="output_container_app_id"></a> [container\_app\_id](#output\_container\_app\_id) | The ID of the Azure Container App. |
| <a name="output_container_app_name"></a> [container\_app\_name](#output\_container\_app\_name) | The name of the Azure Container App. |
| <a name="output_container_app_registry"></a> [container\_app\_registry](#output\_container\_app\_registry) | The container registry block used in the Azure Container App. |
| <a name="output_container_app_system_assigned_identity_principal_id"></a> [container\_app\_system\_assigned\_identity\_principal\_id](#output\_container\_app\_system\_assigned\_identity\_principal\_id) | Principal ID of the System Assigned Managed Identity for the Container App |

# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v1.0.0] - 2027-07-09
### Added
- Initial release of the module to create:
  - Azure Container App resource with:
    - Container and Init container templates
    - Liveness and Startup probes
    - Volume and Volume Mount configuration
    - Custom, HTTP, and TCP scale rules
    - Secure secret injection via Key Vault or inline values
    - Registry integration using system or user-assigned identities
    - Ingress block with transport, port, HTTPS, client cert, and traffic weights
  - Support for:
    - System-assigned managed identity
    - User-assigned managed identities
    - Dynamic identity type selection via locals
  - Output for:
    - Fully qualified container app name
    - System assigned principal ID (for role assignments)
  - Optional lock support for resources
  - Optional role assignments for system-assigned identity
  - Optional CORS policy
  - Maximum inactive revisions for a container app
  - Added `ignore_changes` to prevent Terraform from updating the container app on image version changes

<!-- END_TF_DOCS -->
