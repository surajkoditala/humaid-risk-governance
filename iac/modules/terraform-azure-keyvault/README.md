<!-- BEGIN_TF_DOCS -->


## Introduction

This module provisions an **Azure Key Vault** along with optional integrations such as private endpoints, private DNS zones, virtual network linking, diagnostic settings, role assignments, and resource locks.

---

## 📘 Overview

This module enables:

- **Azure Key Vault** deployment with configurable SKU, purge protection, soft delete, and RBAC authorization
- **Private endpoints** for secure, private access to Key Vault
- **Private DNS zone integration** for automatic name resolution
- **Virtual network linking** to associate DNS zones with VNets
- **Resource locks** to protect against accidental deletion or modification
- **Diagnostic settings** integration with Log Analytics, Storage, or Event Hub
- **Network ACLs** for IP restrictions and VNet-based access

#Examples

#Basic Example
```hcl
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

#Default Example
```hcl
# We need the tenant id for the key vault.
data "azurerm_client_config" "this" {}

resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "log-gh-dev-sandbox-01" # In reality, we will have only one log analytics for the whole environment; for the purpose of testing, this work space is being created.
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

# Create Application Insights (workspace-based) - Ideally we will have only one app insights for the whole environment; for the purpose of testing, this app insights is being created.
resource "azurerm_application_insights" "app_insights" {
  name                = "appi-gh-dev-sandbox"
  location            = "eastus2"
  resource_group_name = "rg-gh-dev-sandbox"
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.log_analytics_workspace.id
}

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
    ip_rules                   = ["157.66.143.200/32", "210.14.21.200/32", "208.195.3.201/32"]                                                                                                                                                                                                                                                                                                                    #Company VPNs                                                                                                                                                                                                                                                                                                                  #VPN IPs
    virtual_network_subnet_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-cae-dev-sandbox-01", "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01"] #Subnets of the resources from which access is needed
  }

  # Enabling diagnostic settings
  diagnostic_settings = {
    kv_diag_setting = {
      name                           = "kv-gh-dev-sandbox-diagnostic-setting"
      workspace_resource_id          = azurerm_log_analytics_workspace.log_analytics_workspace.id
      log_analytics_destination_type = "Dedicated" # Or "AzureDiagnostics"
      # log_categories                 = ["AuditEvent","AzurePolicyEvaluationDetails"]
      log_groups        = ["allLogs"]
      metric_categories = ["AllMetrics"]
    }
  }

  # private end point creation
  private_endpoints = {
    kv_pe = {
      subnet_resource_id            = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01" #PEP subnet ID
      private_dns_zone_resource_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"]                   #Shared RG default KV dns zone
    }
  }

}



# These are only examples to showcase how to refer the outputs; not needed to declare in the resource provisioning module; will be used for CAs env values
output "PE_Name" {
  value = module.keyvault.key_vault_private_end_point_name["kv_pe_name"]
}

output "PE_ID" {
  value = module.keyvault.key_vault_private_end_point_id["kv_pe_id"]
}

output "PEs" {
  value = module.keyvault.key_vault_private_endpoints
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

#Diagnostic Settings Example
```hcl
# We need the tenant id for the key vault.
data "azurerm_client_config" "this" {}

resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "log-gh-dev-sandbox-01" # In reality, we will have only one log analytics for the whole environment; for the purpose of testing, this work space is being created.
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

# Create Application Insights (workspace-based) - Ideally we will have only one app insights for the whole environment; for the purpose of testing, this app insights is being created.
resource "azurerm_application_insights" "app_insights" {
  name                = "appi-gh-dev-sandbox"
  location            = "eastus2"
  resource_group_name = "rg-gh-dev-sandbox"
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.log_analytics_workspace.id
}

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
    ip_rules                   = ["157.66.143.200/32", "210.14.21.200/32", "208.195.3.201/32"]                                                                                                                                                                                                                                                                                                                    #Company VPNs                                                                                                                                                                                                                                                                                                                         #VPN IPs
    virtual_network_subnet_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-cae-dev-sandbox-01", "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01"] #Subnets of the resources from which access is needed
  }

  # Enabling diagnostic settings
  diagnostic_settings = {
    kv_diag_setting = {
      name                           = "kv-gh-dev-sandbox-diagnostic-setting"
      workspace_resource_id          = azurerm_log_analytics_workspace.log_analytics_workspace.id
      log_analytics_destination_type = "Dedicated" # Or "AzureDiagnostics"
      # log_categories                 = ["AuditEvent","AzurePolicyEvaluationDetails"]
      log_groups        = ["allLogs"]
      metric_categories = ["AllMetrics"]
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

#Monitoring Alerts Example
```hcl
# We need the tenant id for the key vault.
data "azurerm_client_config" "this" {}

resource "azurerm_monitor_action_group" "ops" {
  name                = "ag-gh-dev-sandbox"
  resource_group_name = "rg-gh-dev-sandbox"
  short_name          = "opsalert"

  email_receiver {
    name                    = "devops"
    email_address           = "myridiusprojectteam@myridius.com"
    use_common_alert_schema = true
  }
}

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
    ip_rules                   = ["157.66.143.200/32", "210.14.21.200/32", "208.195.3.201/32"]
    virtual_network_subnet_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-cae-dev-sandbox-01", "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01"]
  }

  enable_monitoring_alerts     = true
  enable_keyvault_delete_alert = true
  action_group_id              = azurerm_monitor_action_group.ops.id

  keyvault_alerts = {
    availability = {
      metric_name    = "Availability"
      criterion_type = "StaticThresholdCriterion"
      aggregation    = "Average"
      operator       = "LessThan"
      threshold      = 90
      severity       = 1
      frequency      = "PT1M"
      window         = "PT5M"
    }
    saturation_shoebox = {
      metric_name    = "SaturationShoebox"
      criterion_type = "StaticThresholdCriterion"
      aggregation    = "Average"
      operator       = "GreaterThan"
      threshold      = 75
      severity       = 1
      frequency      = "PT1M"
      window         = "PT5M"
    }
    service_api_latency = {
      metric_name    = "ServiceApiLatency"
      criterion_type = "StaticThresholdCriterion"
      aggregation    = "Average"
      operator       = "GreaterThan"
      threshold      = 1000
      severity       = 2
      frequency      = "PT1M"
      window         = "PT5M"
    }
    service_api_result = {
      metric_name       = "ServiceApiResult"
      criterion_type    = "DynamicThresholdCriterion"
      aggregation       = "Average"
      operator          = "GreaterThan"
      severity          = 2
      frequency         = "PT5M"
      window            = "PT5M"
      alert_sensitivity = "Medium"

      failing_periods = {
        min_failing_periods_to_alert = 4
        number_of_evaluation_periods = 4
      }
    }
  }
}

 

output "key_vault_name" {
  value = module.keyvault.key_vault_name
}

output "key_vault_metric_alert_ids" {
  value = module.keyvault.key_vault_metric_alert_ids
}

output "key_vault_delete_activity_log_alert_id" {
  value = module.keyvault.key_vault_delete_activity_log_alert_id
}

output "key_vault_action_group_id" {
  value = azurerm_monitor_action_group.ops.id
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

#Private Endpoint and DNS Example
```hcl
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

  # private end point creation
  private_endpoints = {
    kv_pe = {
      subnet_resource_id            = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01" #PEP subnet ID
      private_dns_zone_resource_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"]                   #Shared RG default KV dns zone
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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.8 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 3.71, < 5.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.81.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_key_vault.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault) | resource |
| [azurerm_management_lock.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_lock) | resource |
| [azurerm_monitor_activity_log_alert.keyvault_delete](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_activity_log_alert) | resource |
| [azurerm_monitor_diagnostic_setting.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_monitor_metric_alert.keyvault](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_metric_alert) | resource |
| [azurerm_private_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_private_endpoint.this_unmanaged_dns_zone_groups](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_private_endpoint_application_security_group_association.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint_application_security_group_association) | resource |
| [azurerm_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| <a name="input_action_group_id"></a> [action\_group\_id](#input\_action\_group\_id) | The Azure Monitor action group resource ID used by Key Vault monitoring alerts. | `string` | `null` |
| <a name="input_diagnostic_settings"></a> [diagnostic\_settings](#input\_diagnostic\_settings) | A map of diagnostic settings to create on the ddos protection plan. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/><br/>- `name` - (Optional) The name of the diagnostic setting. One will be generated if not set, however this will not be unique if you want to create multiple diagnostic setting resources.<br/>- `log_categories` - (Optional) A set of log categories to send to the log analytics workspace. Defaults to `[]`.<br/>- `log_groups` - (Optional) A set of log groups to send to the log analytics workspace. Defaults to `["allLogs"]`.<br/>- `metric_categories` - (Optional) A set of metric categories to send to the log analytics workspace. Defaults to `["AllMetrics"]`.<br/>- `log_analytics_destination_type` - (Optional) The destination type for the diagnostic setting. Possible values are `Dedicated` and `AzureDiagnostics`. Defaults to `Dedicated`.<br/>- `workspace_resource_id` - (Optional) The resource ID of the log analytics workspace to send logs and metrics to.<br/>- `storage_account_resource_id` - (Optional) The resource ID of the storage account to send logs and metrics to.<br/>- `event_hub_authorization_rule_resource_id` - (Optional) The resource ID of the event hub authorization rule to send logs and metrics to.<br/>- `event_hub_name` - (Optional) The name of the event hub. If none is specified, the default event hub will be selected.<br/>- `marketplace_partner_resource_id` - (Optional) The full ARM resource ID of the Marketplace resource to which you would like to send Diagnostic LogsLogs. | <pre>map(object({<br/>    name                                     = optional(string, null)<br/>    log_categories                           = optional(set(string), [])<br/>    log_groups                               = optional(set(string), ["allLogs"])<br/>    metric_categories                        = optional(set(string), ["AllMetrics"])<br/>    log_analytics_destination_type           = optional(string, "Dedicated")<br/>    workspace_resource_id                    = optional(string, null)<br/>    storage_account_resource_id              = optional(string, null)<br/>    event_hub_authorization_rule_resource_id = optional(string, null)<br/>    event_hub_name                           = optional(string, null)<br/>    marketplace_partner_resource_id          = optional(string, null)<br/>  }))</pre> | `{}` |
| <a name="input_enable_keyvault_delete_alert"></a> [enable\_keyvault\_delete\_alert](#input\_enable\_keyvault\_delete\_alert) | Controls whether an activity log alert is created for successful Key Vault delete operations. | `bool` | `true` |
| <a name="input_enable_monitoring_alerts"></a> [enable\_monitoring\_alerts](#input\_enable\_monitoring\_alerts) | Controls whether Azure Monitor metric and activity log alerts are created for the Key Vault. | `bool` | `false` |
| <a name="input_enabled_for_deployment"></a> [enabled\_for\_deployment](#input\_enabled\_for\_deployment) | Specifies whether Azure Virtual Machines are permitted to retrieve certificates stored as secrets from the vault. | `bool` | `false` |
| <a name="input_enabled_for_disk_encryption"></a> [enabled\_for\_disk\_encryption](#input\_enabled\_for\_disk\_encryption) | Specifies whether Azure Disk Encryption is permitted to retrieve secrets from the vault and unwrap keys. | `bool` | `false` |
| <a name="input_enabled_for_template_deployment"></a> [enabled\_for\_template\_deployment](#input\_enabled\_for\_template\_deployment) | Specifies whether Azure Resource Manager is permitted to retrieve secrets from the vault. | `bool` | `false` |
| <a name="input_keyvault_alerts"></a> [keyvault\_alerts](#input\_keyvault\_alerts) | A map of Azure Monitor metric alerts to create for the Key Vault. | <pre>map(object({<br/>    enabled                = optional(bool, true)<br/>    name                   = optional(string, null)<br/>    description            = optional(string, null)<br/>    criterion_type         = optional(string, "StaticThresholdCriterion")<br/>    severity               = optional(number, 3)<br/>    frequency              = optional(string, "PT5M")<br/>    window                 = optional(string, "PT5M")<br/>    auto_mitigate          = optional(bool, true)<br/>    metric_namespace       = optional(string, "Microsoft.KeyVault/vaults")<br/>    metric_name            = string<br/>    aggregation            = string<br/>    operator               = string<br/>    threshold              = optional(number)<br/>    skip_metric_validation = optional(bool, false)<br/>    alert_sensitivity      = optional(string)<br/>    failing_periods = optional(object({<br/>      min_failing_periods_to_alert = number<br/>      number_of_evaluation_periods = number<br/>    }))<br/>    dimensions = optional(list(object({<br/>      name     = string<br/>      operator = optional(string, "Include")<br/>      values   = list(string)<br/>    })), [])<br/>  }))</pre> | `{}` |
| <a name="input_legacy_access_policies_enabled"></a> [legacy\_access\_policies\_enabled](#input\_legacy\_access\_policies\_enabled) | Specifies whether legacy access policies are enabled for this Key Vault. Prevents use of Azure RBAC for data plane. | `bool` | `false` |
| <a name="input_location"></a> [location](#input\_location) | Azure region where the resource group will be created | `string` | `"eastus2"` |
| <a name="input_lock"></a> [lock](#input\_lock) | Controls the Resource Lock configuration for this resource. The following properties can be specified:<br/><br/>  - `kind` - (Required) The type of lock. Possible values are `\"CanNotDelete\"` and `\"ReadOnly\"`.<br/>  - `name` - (Optional) The name of the lock. If not specified, a name will be generated based on the `kind` value. Changing this forces the creation of a new resource. | <pre>object({<br/>    kind = string<br/>    name = optional(string, null)<br/>  })</pre> | `null` |
| <a name="input_name"></a> [name](#input\_name) | Name of the key vault | `string` | `null` |
| <a name="input_network_acls"></a> [network\_acls](#input\_network\_acls) | The network ACL configuration for the Key Vault.<br/>If not specified then the Key Vault will be created with a firewall that blocks access.<br/>Specify `null` to create the Key Vault with no firewall.<br/><br/>- `bypass` - (Optional) Should Azure Services bypass the ACL. Possible values are `AzureServices` and `None`. Defaults to `None`.<br/>- `default_action` - (Optional) The default action when no rule matches. Possible values are `Allow` and `Deny`. Defaults to `Deny`.<br/>- `ip_rules` - (Optional) A list of IP rules in CIDR format. Defaults to `[]`.<br/>- `virtual_network_subnet_ids` - (Optional) When using with Service Endpoints, a list of subnet IDs to associate with the Key Vault. Defaults to `[]`. | <pre>object({<br/>    bypass                     = optional(string, "None")<br/>    default_action             = optional(string, "Deny")<br/>    ip_rules                   = optional(list(string), [])<br/>    virtual_network_subnet_ids = optional(list(string), [])<br/>  })</pre> | `{}` |
| <a name="input_private_endpoints"></a> [private\_endpoints](#input\_private\_endpoints) | A map of private endpoints to create on the Key Vault. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/><br/>- `name` - (Optional) The name of the private endpoint. One will be generated if not set.<br/>- `role_assignments` - (Optional) A map of role assignments to create on the private endpoint. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time. See `var.role_assignments` for more information.<br/>- `lock` - (Optional) The lock level to apply to the private endpoint. Default is `None`. Possible values are `None`, `CanNotDelete`, and `ReadOnly`.<br/>- `tags` - (Optional) A mapping of tags to assign to the private endpoint.<br/>- `subnet_resource_id` - The resource ID of the subnet to deploy the private endpoint in.<br/>- `private_dns_zone_group_name` - (Optional) The name of the private DNS zone group. One will be generated if not set.<br/>- `private_dns_zone_resource_ids` - (Optional) A set of resource IDs of private DNS zones to associate with the private endpoint. If not set, no zone groups will be created and the private endpoint will not be associated with any private DNS zones. DNS records must be managed external to this module.<br/>- `application_security_group_resource_ids` - (Optional) A map of resource IDs of application security groups to associate with the private endpoint. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/>- `private_service_connection_name` - (Optional) The name of the private service connection. One will be generated if not set.<br/>- `network_interface_name` - (Optional) The name of the network interface. One will be generated if not set.<br/>- `location` - (Optional) The Azure location where the resources will be deployed. Defaults to the location of the resource group.<br/>- `resource_group_name` - (Optional) The resource group where the resources will be deployed. Defaults to the resource group of the Key Vault.<br/>- `ip_configurations` - (Optional) A map of IP configurations to create on the private endpoint. If not specified the platform will create one. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/>  - `name` - The name of the IP configuration.<br/>  - `private_ip_address` - The private IP address of the IP configuration. | <pre>map(object({<br/>    name = optional(string, null)<br/>    role_assignments = optional(map(object({<br/>      role_definition_id_or_name             = string<br/>      principal_id                           = string<br/>      description                            = optional(string, null)<br/>      skip_service_principal_aad_check       = optional(bool, false)<br/>      condition                              = optional(string, null)<br/>      condition_version                      = optional(string, null)<br/>      delegated_managed_identity_resource_id = optional(string, null)<br/>      principal_type                         = optional(string, null)<br/>    })), {})<br/>    lock = optional(object({<br/>      kind = string<br/>      name = optional(string, null)<br/>    }), null)<br/>    tags                                    = optional(map(string), null)<br/>    subnet_resource_id                      = string<br/>    subresource_name                        = optional(string, "vault")<br/>    private_dns_zone_group_name             = optional(string, "default") #not needed<br/>    private_dns_zone_resource_ids           = optional(set(string), [])   #not needed<br/>    application_security_group_associations = optional(map(string), {})<br/>    private_service_connection_name         = optional(string, null)<br/>    network_interface_name                  = optional(string, null)<br/>    location                                = optional(string, null)<br/>    resource_group_name                     = optional(string, null)<br/>    ip_configurations = optional(map(object({<br/>      name               = string<br/>      private_ip_address = string<br/>    })), {})<br/>  }))</pre> | `{}` |
| <a name="input_private_endpoints_manage_dns_zone_group"></a> [private\_endpoints\_manage\_dns\_zone\_group](#input\_private\_endpoints\_manage\_dns\_zone\_group) | Whether to manage private DNS zone groups with this module. If set to false, you must manage private DNS zone groups externally, e.g. using Azure Policy. | `bool` | `true` |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Specifies whether public access is permitted. | `bool` | `true` |
| <a name="input_purge_protection_enabled"></a> [purge\_protection\_enabled](#input\_purge\_protection\_enabled) | Specifies whether protection against purge is enabled for this Key Vault. Note once enabled this cannot be disabled. | `bool` | `true` |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group where resources will be created | `string` | n/a |
| <a name="input_role_assignments"></a> [role\_assignments](#input\_role\_assignments) | A map of role assignments to create on the <RESOURCE>. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/><br/>  - `role_definition_id_or_name` - The ID or name of the role definition to assign to the principal.<br/>  - `principal_id` - The ID of the principal to assign the role to.<br/>  - `description` - (Optional) The description of the role assignment.<br/>  - `skip_service_principal_aad_check` - (Optional) If set to true, skips the Azure Active Directory check for the service principal in the tenant. Defaults to false.<br/>  - `condition` - (Optional) The condition which will be used to scope the role assignment.<br/>  - `condition_version` - (Optional) The version of the condition syntax. Leave as `null` if you are not using a condition, if you are then valid values are '2.0'.<br/>  - `delegated_managed_identity_resource_id` - (Optional) The delegated Azure Resource Id which contains a Managed Identity. Changing this forces a new resource to be created. This field is only used in cross-tenant scenario.<br/>  - `principal_type` - (Optional) The type of the `principal_id`. Possible values are `User`, `Group` and `ServicePrincipal`. It is necessary to explicitly set this attribute when creating role assignments if the principal creating the assignment is constrained by ABAC rules that filters on the PrincipalType attribute.<br/><br/>  > Note: only set `skip_service_principal_aad_check` to true if you are assigning a role to a service principal. | <pre>map(object({<br/>    role_definition_id_or_name             = string<br/>    principal_id                           = string<br/>    scope                                  = string<br/>    description                            = optional(string, null)<br/>    skip_service_principal_aad_check       = optional(bool, false)<br/>    condition                              = optional(string, null)<br/>    condition_version                      = optional(string, null)<br/>    delegated_managed_identity_resource_id = optional(string, null)<br/>    principal_type                         = optional(string, null)<br/>  }))</pre> | `{}` |
| <a name="input_sku_name"></a> [sku\_name](#input\_sku\_name) | The SKU name of the Key Vault. Default is `premium`. Possible values are `standard` and `premium`. | `string` | `"standard"` |
| <a name="input_soft_delete_retention_days"></a> [soft\_delete\_retention\_days](#input\_soft\_delete\_retention\_days) | The number of days that items should be retained for once soft-deleted. This value can be between 7 and 90 (the default) days. | `number` | `null` |
| <a name="input_tags"></a> [tags](#input\_tags) | Map of tags to be applied to all resources | `map(string)` | <pre>{<br/>  "business_unit": "banking",<br/>  "customer": "myridius",<br/>  "environment": "dev",<br/>  "owner": "devops",<br/>  "product": "gh",<br/>  "region": "eastus2"<br/>}</pre> |
| <a name="input_tenant_id"></a> [tenant\_id](#input\_tenant\_id) | The Azure tenant ID used for authenticating requests to Key Vault. You can use the `azurerm_client_config` data source to retrieve it. | `string` | n/a |
| <a name="input_user_preferred_index"></a> [user\_preferred\_index](#input\_user\_preferred\_index) | A value to append at the end of the name | `number` | `1` |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_key_vault_delete_activity_log_alert_id"></a> [key\_vault\_delete\_activity\_log\_alert\_id](#output\_key\_vault\_delete\_activity\_log\_alert\_id) | The resource ID of the Key Vault delete activity log alert. |
| <a name="output_key_vault_metric_alert_ids"></a> [key\_vault\_metric\_alert\_ids](#output\_key\_vault\_metric\_alert\_ids) | A map of Key Vault metric alert resource IDs. |
| <a name="output_key_vault_name"></a> [key\_vault\_name](#output\_key\_vault\_name) | The name of the key vault. |
| <a name="output_key_vault_private_end_point_id"></a> [key\_vault\_private\_end\_point\_id](#output\_key\_vault\_private\_end\_point\_id) | The name of the KV private endpoint |
| <a name="output_key_vault_private_end_point_name"></a> [key\_vault\_private\_end\_point\_name](#output\_key\_vault\_private\_end\_point\_name) | The name of the KV private endpoint |
| <a name="output_key_vault_private_endpoints"></a> [key\_vault\_private\_endpoints](#output\_key\_vault\_private\_endpoints) | A map of private endpoints. The map key is the supplied input to var.private\_endpoints. The map value is the entire azurerm\_private\_endpoint resource. |
| <a name="output_key_vault_private_fqdn"></a> [key\_vault\_private\_fqdn](#output\_key\_vault\_private\_fqdn) | The private fqdn of the key vault |
| <a name="output_key_vault_resource_id"></a> [key\_vault\_resource\_id](#output\_key\_vault\_resource\_id) | The Azure resource id of the key vault. |
| <a name="output_key_vault_uri"></a> [key\_vault\_uri](#output\_key\_vault\_uri) | The URI of the vault for performing operations on keys and secrets |

# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v1.0.0] - 2026-06-16
### Added
- Initial release of the module to create:
  - Azure Key Vault with configurable SKU, purge protection, soft delete, and RBAC authorization
  - Optional resource-level lock for protection of critical environments
  - Private Endpoint for secure, private access to Key Vault
  - Private DNS Zone creation with automatic record set management
  - Virtual Network linking for DNS zone resolution
  - Azure Monitor diagnostic settings with support for Log Analytics, Event Hub, and Storage
  - Network ACL configuration with IP rules and VNet-based access
  - Azure Monitor metric alerts for Key Vault with support for static and dynamic threshold criteria.
  - Key Vault delete activity log alert for successful delete operations.
  - Optional action group integration for critical metric alerts and delete activity alerts.
  - Monitoring alerts example with action group, availability, capacity, latency, and service API result alerts.
  - Outputs for Key Vault metric alert IDs and delete activity log alert ID.

<!-- END_TF_DOCS -->
