<!-- BEGIN_TF_DOCS -->


# Introduction

This module provisions an **Azure Storage Account** with flexible configuration and optional integrations for enhanced security, governance, and observability.  

---

## 📘 Overview

This module enables:

- **Azure Storage Account** deployment with configurable replication, tier, kind, networking, and encryption options   
- **Identity support** for system-assigned and/or user-assigned managed identities  
- **Network security rules** with IP filtering and VNet-based access control  
- **Private endpoints** for secure, private access to the Storage Account  
- **Private DNS zone integration** for seamless name resolution of private endpoints  
- **Diagnostic settings** to send metrics and logs to Log Analytics, Storage, or Event Hub  
- **Metric alerts** for Storage Account availability and used capacity
- **Role assignments (RBAC)** for fine-grained access control
- **Customer-managed keys (CMK)** integration using Azure Key Vault 
- **Resource locks (optional)** to protect against accidental deletion or modification    

#Examples

#Basic Example
```hcl
module "storage" {
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

  public_network_access_enabled = true #for staging and prod, this value will be false

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
# Create Log analytics workspace (workspace-based) - Ideally we will have only one log analytics for all the shared environments 
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

# Create Application Insights (workspace-based) - Ideally we will have only one app insights for all the shared environments; don't need this block in each environment.
resource "azurerm_application_insights" "app_insights" {
  name                = "appi-gh-dev-sandbox"
  location            = "eastus2"
  resource_group_name = "rg-gh-dev-sandbox"
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.log_analytics_workspace.id
}

module "storage" {
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
  public_network_access_enabled = true #for staging and prod, this value will be false

  blob_properties = {
    cors_rule = [
      {
        allowed_headers    = ["*"]
        allowed_methods    = ["GET", "OPTIONS"]
        allowed_origins    = ["http://localhost:4200"]
        exposed_headers    = ["*"]
        max_age_in_seconds = 3600
      }
    ]
  }

  network_rules = {
    ip_rules = ["157.66.143.200", "210.14.21.200", "208.195.3.201"] #VPN IPs
    virtual_network_subnet_ids = [                                  #Subnets of the resources from which access is needed
      "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-cae-dev-sandbox-01",
      "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01"
    ]
  }

  # Diagnostic settings on the storage account
  diagnostic_settings_storage_account = {
    st_diag_setting = {
      name                           = "st-gh-dev-sandbox-diagnostic-setting"
      workspace_resource_id          = azurerm_log_analytics_workspace.log_analytics_workspace.id
      log_analytics_destination_type = "Dedicated"                 # Or "AzureDiagnostics"
      metric_categories              = ["Capacity", "Transaction"] #Only metrics available on storage account diagnostic settings, no logs.
    }
  }

  # Diagnostic settings on the storage blob
  diagnostic_settings_blob = {
    st_blob_diag_setting = {
      name                           = "st-blob-gh-dev-sandbox-diagnostic-setting"
      workspace_resource_id          = azurerm_log_analytics_workspace.log_analytics_workspace.id
      log_analytics_destination_type = "Dedicated" # Or "AzureDiagnostics"
      #log_categories                           = ["audit", "alllogs"]
      log_groups        = ["audit", "allLogs"]
      metric_categories = ["Capacity", "Transaction"]
    }
  }

  # private end point creation
  private_endpoints = {
    st_pe = {
      subnet_resource_id            = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01" #PEP subnet ID
      private_dns_zone_resource_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev01/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"]                       #Private DNS zone at subscription level
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

#Diagnostic Settings Example
```hcl
# Create Log analytics workspace (workspace-based) - Ideally we will have only one log analytics for all the shared environments 
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

# Create Application Insights (workspace-based) - Ideally we will have only one app insights for all the shared environments; don't need this block in each environment.
resource "azurerm_application_insights" "app_insights" {
  name                = "appi-gh-dev-sandbox"
  location            = "eastus2"
  resource_group_name = "rg-gh-dev-sandbox"
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.log_analytics_workspace.id
}

module "storage" {
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

  public_network_access_enabled = true #for staging and prod, this value will be false

  blob_properties = {
    cors_rule = [
      {
        allowed_headers    = ["*"]
        allowed_methods    = ["GET", "OPTIONS"]
        allowed_origins    = ["http://localhost:4200"]
        exposed_headers    = ["*"]
        max_age_in_seconds = 3600
      }
    ]
  }

  network_rules = {
    ip_rules = ["157.66.143.200", "210.14.21.200", "208.195.3.201"] #VPN IPs
    virtual_network_subnet_ids = [                                  #Subnets of the resources from which access is needed
      "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-cae-dev-sandbox-01",
      "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01"
    ]
  }

  # Diagnostic settings on the storage account
  diagnostic_settings_storage_account = {
    st_diag_setting = {
      name                           = "st-gh-dev-sandbox-diagnostic-setting"
      workspace_resource_id          = azurerm_log_analytics_workspace.log_analytics_workspace.id
      log_analytics_destination_type = "Dedicated"                 # Or "AzureDiagnostics"
      metric_categories              = ["Capacity", "Transaction"] #Only metrics available on storage account diagnostic settings, no logs.
    }
  }

  # Diagnostic settings on the storage blob
  diagnostic_settings_blob = {
    st_blob_diag_setting = {
      name                           = "st-blob-gh-dev-sandbox-diagnostic-setting"
      workspace_resource_id          = azurerm_log_analytics_workspace.log_analytics_workspace.id
      log_analytics_destination_type = "Dedicated" # Or "AzureDiagnostics"
      #log_categories                           = ["audit", "alllogs"]
      log_groups        = ["audit", "allLogs"]
      metric_categories = ["Capacity", "Transaction"]
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

#Private Endpoint and DNS Example
```hcl
module "storage" {
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
  public_network_access_enabled = true #for staging and prod, this value will be false

  blob_properties = {
    cors_rule = [
      {
        allowed_headers    = ["*"]
        allowed_methods    = ["GET", "OPTIONS"]
        allowed_origins    = ["http://localhost:4200"]
        exposed_headers    = ["*"]
        max_age_in_seconds = 3600
      }
    ]
  }

  network_rules = {
    ip_rules = ["157.66.143.200", "210.14.21.200", "208.195.3.201"] #VPN IPs
    virtual_network_subnet_ids = [                                  #Subnets of the resources from which access is needed
      "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-cae-dev-sandbox-01",
      "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01"
    ]
  }

  # private end point creation
  private_endpoints = {
    st_pe_blob = {
      name                          = "pep-stblob-gh-dev-sandbox"
      subnet_resource_id            = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01" #PEP subnet ID
      private_dns_zone_resource_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev01/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"]                       #Private DNS zone at subscription level
    }
    # Optional endpoints based on the requirement (like logic apps). Ideally only blob endpoint is enough for the storage accounts.
    st_pe_file = {
      name                          = "pep-stfile-gh-dev-sandbox"
      subnet_resource_id            = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01" #PEP subnet ID
      subresource_name              = "file"
      private_dns_zone_resource_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev01/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"] #Private DNS zone at subscription level
    }
    st_pe_queue = {
      name                          = "pep-stqueue-gh-dev-sandbox"
      subnet_resource_id            = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01" #PEP subnet ID
      subresource_name              = "queue"
      private_dns_zone_resource_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev01/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"] #Private DNS zone at subscription level
    }
    st_pe_table = {
      name                          = "pep-sttable-gh-dev-sandbox"
      subnet_resource_id            = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01" #PEP subnet ID
      subresource_name              = "table"
      private_dns_zone_resource_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev01/providers/Microsoft.Network/privateDnsZones/privatelink.table.core.windows.net"] #Private DNS zone at subscription level
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

module "storage" {
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

  public_network_access_enabled = true
  enable_monitoring_alerts      = true
  action_group_id               = azurerm_monitor_action_group.ops.id

  storage_account_alerts = {
    availability = {
      metric_name   = "Availability"
      aggregation   = "Average"
      operator      = "LessThan"
      threshold     = 100
      severity      = 1
      frequency     = "PT1M"
      window        = "PT1M"
      auto_mitigate = false
    }

    used_capacity = {
      metric_name = "UsedCapacity"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = 500000000000000
      severity    = 3
      frequency   = "PT1H"
      window      = "PT1H"
    }
  }
}

output "action_group_id" {
  value = azurerm_monitor_action_group.ops.id
}

output "storage_account_name" {
  value = module.storage.storage_account_name
}

output "storage_account_resource_id" {
  value = module.storage.storage_account_resource_id
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
| [azurerm_management_lock.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_lock) | resource |
| [azurerm_monitor_diagnostic_setting.blob](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_monitor_diagnostic_setting.storage_account](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_monitor_metric_alert.storage_account](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_metric_alert) | resource |
| [azurerm_private_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_role_assignment.storage_account](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_storage_account.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_account_customer_managed_key.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account_customer_managed_key) | resource |

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| <a name="input_access_tier"></a> [access\_tier](#input\_access\_tier) | (Optional) Defines the access tier for BlobStorage, FileStorage and StorageV2 accounts. Valid options are Hot, Cool, Cold and Premium. Defaults to Hot. | `string` | `"Hot"` |
| <a name="input_account_kind"></a> [account\_kind](#input\_account\_kind) | (Optional) Defines the Kind of account. Valid options are `BlobStorage`, `BlockBlobStorage`, `FileStorage`, `Storage` and `StorageV2`. Defaults to `StorageV2`. | `string` | `"StorageV2"` |
| <a name="input_account_replication_type"></a> [account\_replication\_type](#input\_account\_replication\_type) | (Required) Defines the type of replication to use for this storage account. Valid options are `LRS`, `GRS`, `RAGRS`, `ZRS`, `GZRS` and `RAGZRS`.  Defaults to `ZRS` | `string` | `"LRS"` |
| <a name="input_account_tier"></a> [account\_tier](#input\_account\_tier) | (Required) Defines the Tier to use for this storage account. Valid options are `Standard` and `Premium`. For `BlockBlobStorage` and `FileStorage` accounts only `Premium` is valid. Changing this forces a new resource to be created. | `string` | `"Standard"` |
| <a name="input_action_group_id"></a> [action\_group\_id](#input\_action\_group\_id) | Azure Monitor Action Group ID used by alert rules for severity 0 and 1 alerts. | `string` | `null` |
| <a name="input_allow_nested_items_to_be_public"></a> [allow\_nested\_items\_to\_be\_public](#input\_allow\_nested\_items\_to\_be\_public) | (Optional) Allow or disallow nested items within this Account to opt into being public. Defaults to `false`. | `bool` | `false` |
| <a name="input_allowed_copy_scope"></a> [allowed\_copy\_scope](#input\_allowed\_copy\_scope) | (Optional) Restrict copy to and from Storage Accounts within an AAD tenant or with Private Links to the same VNet. Possible values are `AAD` and `PrivateLink`. | `string` | `null` |
| <a name="input_azure_files_authentication"></a> [azure\_files\_authentication](#input\_azure\_files\_authentication) | - `directory_type` - (Required) Specifies the directory service used. Possible values are `AADDS`, `AD` and `AADKERB`.<br/>- `default_share_level_permission` - (Optional) Specifies the default share level permissions applied to all users. Possible values are StorageFileDataSmbShareReader, StorageFileDataSmbShareContributor, StorageFileDataSmbShareElevatedContributor, or None.<br/><br/>---<br/>`active_directory` block supports the following:<br/>- `domain_guid` - (Required) Specifies the domain GUID.<br/>- `domain_name` - (Required) Specifies the primary domain that the AD DNS server is authoritative for.<br/>- `domain_sid` - (Required) Specifies the security identifier (SID).<br/>- `forest_name` - (Required) Specifies the Active Directory forest.<br/>- `netbios_domain_name` - (Required) Specifies the NetBIOS domain name.<br/>- `storage_sid` - (Required) Specifies the security identifier (SID) for Azure Storage. | <pre>object({<br/>    directory_type                 = optional(string, "AADKERB")<br/>    default_share_level_permission = optional(string)<br/><br/>    active_directory = optional(object({<br/>      domain_guid         = string<br/>      domain_name         = string<br/>      domain_sid          = string<br/>      forest_name         = string<br/>      netbios_domain_name = string<br/>      storage_sid         = string<br/>    }))<br/>  })</pre> | `null` |
| <a name="input_blob_properties"></a> [blob\_properties](#input\_blob\_properties) | - `change_feed_enabled` - (Optional) Is the blob service properties for change feed events enabled? Default to `false`.<br/>- `change_feed_retention_in_days` - (Optional) The duration of change feed events retention in days. The possible values are between 1 and 146000 days (400 years). Setting this to null (or omit this in the configuration file) indicates an infinite retention of the change feed.<br/>- `default_service_version` - (Optional) The API Version which should be used by default for requests to the Data Plane API if an incoming request doesn't specify an API Version.<br/>- `last_access_time_enabled` - (Optional) Is the last access time based tracking enabled? Default to `false`.<br/>- `versioning_enabled` - (Optional) Is versioning enabled? Default to `false`.<br/><br/>---<br/>`container_delete_retention_policy` block supports the following:<br/>- `days` - (Optional) Specifies the number of days that the container should be retained, between `1` and `365` days. Defaults to `7`.<br/><br/>---<br/>`cors_rule` block supports the following:<br/>- `allowed_headers` - (Required) A list of headers that are allowed to be a part of the cross-origin request.<br/>- `allowed_methods` - (Required) A list of HTTP methods that are allowed to be executed by the origin. Valid options are `DELETE`, `GET`, `HEAD`, `MERGE`, `POST`, `OPTIONS`, `PUT` or `PATCH`.<br/>- `allowed_origins` - (Required) A list of origin domains that will be allowed by CORS.<br/>- `exposed_headers` - (Required) A list of response headers that are exposed to CORS clients.<br/>- `max_age_in_seconds` - (Required) The number of seconds the client should cache a preflight response.<br/><br/>---<br/>`delete_retention_policy` block supports the following:<br/>- `days` - (Optional) Specifies the number of days that the blob should be retained, between `1` and `365` days. Defaults to `7`.<br/><br/>---<br/>`diagnostic_settings` block supports the following:<br/>- `name` - (Optional) The name of the diagnostic setting. Defaults to `null`.<br/>- `log_categories` - (Optional) A set of log categories to enable. Defaults to an empty set.<br/>- `log_groups` - (Optional) A set of log groups to enable. Defaults to `["allLogs"]`.<br/>- `metric_categories` - (Optional) A set of metric categories to enable. Defaults to `["AllMetrics"]`.<br/>- `log_analytics_destination_type` - (Optional) The destination type for log analytics. Defaults to `"Dedicated"`.<br/>- `workspace_resource_id` - (Optional) The resource ID of the Log Analytics workspace. Defaults to `null`.<br/>- `resource_id` - (Optional) The resource ID of the target resource for diagnostics. Defaults to `null`.<br/>- `event_hub_authorization_rule_resource_id` - (Optional) The resource ID of the Event Hub authorization rule. Defaults to `null`.<br/>- `event_hub_name` - (Optional) The name of the Event Hub. Defaults to `null`.<br/>- `marketplace_partner_resource_id` - (Optional) The resource ID of the marketplace partner. Defaults to `null`.<br/><br/>---<br/>`restore_policy` block supports the following:<br/>- `days` - (Required) Specifies the number of days that the blob can be restored, between `1` and `365` days. This must be less than the `days` specified for `delete_retention_policy`. | <pre>object({<br/>    change_feed_enabled           = optional(bool)<br/>    change_feed_retention_in_days = optional(number)<br/>    default_service_version       = optional(string)<br/>    last_access_time_enabled      = optional(bool)<br/>    versioning_enabled            = optional(bool, false)<br/>    container_delete_retention_policy = optional(object({<br/>      days = optional(number, 7)<br/>    }))<br/><br/>    cors_rule = optional(list(object({<br/>      allowed_headers    = list(string)<br/>      allowed_methods    = list(string)<br/>      allowed_origins    = list(string)<br/>      exposed_headers    = list(string)<br/>      max_age_in_seconds = number<br/>    })))<br/>    delete_retention_policy = optional(object({<br/>      days = optional(number, 7)<br/>    }))<br/>    diagnostic_settings = optional(map(object({<br/>      name                                     = optional(string, null)<br/>      log_categories                           = optional(set(string), [])<br/>      log_groups                               = optional(set(string), ["allLogs"])<br/>      metric_categories                        = optional(set(string), ["AllMetrics"])<br/>      log_analytics_destination_type           = optional(string, "Dedicated")<br/>      workspace_resource_id                    = optional(string, null)<br/>      resource_id                              = optional(string, null)<br/>      event_hub_authorization_rule_resource_id = optional(string, null)<br/>      event_hub_name                           = optional(string, null)<br/>      marketplace_partner_resource_id          = optional(string, null)<br/>    })), {})<br/>    restore_policy = optional(object({<br/>      days = number<br/>    }))<br/>  })</pre> | `null` |
| <a name="input_cross_tenant_replication_enabled"></a> [cross\_tenant\_replication\_enabled](#input\_cross\_tenant\_replication\_enabled) | (Optional) Should cross Tenant replication be enabled? Defaults to `false`. | `bool` | `false` |
| <a name="input_custom_domain"></a> [custom\_domain](#input\_custom\_domain) | - `name` - (Required) The Custom Domain Name to use for the Storage Account, which will be validated by Azure.<br/>- `use_subdomain` - (Optional) Should the Custom Domain Name be validated by using indirect CNAME validation? | <pre>object({<br/>    name          = string<br/>    use_subdomain = optional(bool)<br/>  })</pre> | `null` |
| <a name="input_customer_managed_key"></a> [customer\_managed\_key](#input\_customer\_managed\_key) | Defines a customer managed key to use for encryption.<br/><br/>    object({<br/>      key\_vault\_resource\_id              = (Required) - The full Azure Resource ID of the key\_vault where the customer managed key will be referenced from.<br/>      user\_assigned\_identity\_resource\_id = (Optional) - The user assigned identity to use when access the key vault<br/>    })<br/><br/>    Example Inputs:<pre>terraform<br/>    customer_managed_key = {<br/>      key_vault_resource_id = "/subscriptions/0000000-0000-0000-0000-000000000000/resourceGroups/test-resource-group/providers/Microsoft.KeyVault/vaults/example-key-vault"<br/>    }</pre> | <pre>object({<br/>    key_vault_resource_id = string<br/>    user_assigned_identity = optional(object({<br/>      resource_id = string<br/>    }), null)<br/>  })</pre> | `null` |
| <a name="input_default_to_oauth_authentication"></a> [default\_to\_oauth\_authentication](#input\_default\_to\_oauth\_authentication) | (Optional) Default to Azure Active Directory authorization in the Azure portal when accessing the Storage Account. The default value is `false` | `bool` | `null` |
| <a name="input_diagnostic_settings_blob"></a> [diagnostic\_settings\_blob](#input\_diagnostic\_settings\_blob) | A map of diagnostic settings to create on the Blob Storage within Storage Account. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/><br/>- `name` - (Optional) The name of the diagnostic setting. One will be generated if not set, however this will not be unique if you want to create multiple diagnostic setting resources.<br/>- `log_categories` - (Optional) A set of log categories to send to the log analytics workspace. Defaults to `[]`.<br/>- `log_groups` - (Optional) A set of log groups to send to the log analytics workspace. Defaults to `["allLogs"]`.<br/>- `metric_categories` - (Optional) A set of metric categories to send to the log analytics workspace. Defaults to `["AllMetrics"]`.<br/>- `log_analytics_destination_type` - (Optional) The destination type for the diagnostic setting. Possible values are `Dedicated` and `AzureDiagnostics`. Defaults to `Dedicated`.<br/>- `workspace_resource_id` - (Optional) The resource ID of the log analytics workspace to send logs and metrics to.<br/>- `storage_account_resource_id` - (Optional) The resource ID of the storage account to send logs and metrics to.<br/>- `event_hub_authorization_rule_resource_id` - (Optional) The resource ID of the event hub authorization rule to send logs and metrics to.<br/>- `event_hub_name` - (Optional) The name of the event hub. If none is specified, the default event hub will be selected.<br/>- `marketplace_partner_resource_id` - (Optional) The full ARM resource ID of the Marketplace resource to which you would like to send Diagnostic LogsLogs. | <pre>map(object({<br/>    name                                     = optional(string, null)<br/>    log_categories                           = optional(set(string), [])<br/>    log_groups                               = optional(set(string), ["allLogs"])<br/>    metric_categories                        = optional(set(string), ["AllMetrics"])<br/>    log_analytics_destination_type           = optional(string, "Dedicated")<br/>    workspace_resource_id                    = optional(string, null)<br/>    storage_account_resource_id              = optional(string, null)<br/>    event_hub_authorization_rule_resource_id = optional(string, null)<br/>    event_hub_name                           = optional(string, null)<br/>    marketplace_partner_resource_id          = optional(string, null)<br/>  }))</pre> | `{}` |
| <a name="input_diagnostic_settings_storage_account"></a> [diagnostic\_settings\_storage\_account](#input\_diagnostic\_settings\_storage\_account) | A map of diagnostic settings to create on the Storage Account. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/><br/>- `name` - (Optional) The name of the diagnostic setting. One will be generated if not set, however this will not be unique if you want to create multiple diagnostic setting resources.<br/>- `log_categories` - (Optional) A set of log categories to send to the log analytics workspace. Defaults to `[]`.<br/>- `log_groups` - (Optional) A set of log groups to send to the log analytics workspace. Defaults to `["allLogs"]`.<br/>- `metric_categories` - (Optional) A set of metric categories to send to the log analytics workspace. Defaults to `["AllMetrics"]`.<br/>- `log_analytics_destination_type` - (Optional) The destination type for the diagnostic setting. Possible values are `Dedicated` and `AzureDiagnostics`. Defaults to `Dedicated`.<br/>- `workspace_resource_id` - (Optional) The resource ID of the log analytics workspace to send logs and metrics to.<br/>- `storage_account_resource_id` - (Optional) The resource ID of the storage account to send logs and metrics to.<br/>- `event_hub_authorization_rule_resource_id` - (Optional) The resource ID of the event hub authorization rule to send logs and metrics to.<br/>- `event_hub_name` - (Optional) The name of the event hub. If none is specified, the default event hub will be selected.<br/>- `marketplace_partner_resource_id` - (Optional) The full ARM resource ID of the Marketplace resource to which you would like to send Diagnostic LogsLogs. | <pre>map(object({<br/>    name                                     = optional(string, null)<br/>    log_categories                           = optional(set(string), [])<br/>    log_groups                               = optional(set(string), ["allLogs"])<br/>    metric_categories                        = optional(set(string), ["AllMetrics"])<br/>    log_analytics_destination_type           = optional(string, "Dedicated")<br/>    workspace_resource_id                    = optional(string, null)<br/>    storage_account_resource_id              = optional(string, null)<br/>    event_hub_authorization_rule_resource_id = optional(string, null)<br/>    event_hub_name                           = optional(string, null)<br/>    marketplace_partner_resource_id          = optional(string, null)<br/>  }))</pre> | `{}` |
| <a name="input_edge_zone"></a> [edge\_zone](#input\_edge\_zone) | (Optional) Specifies the Edge Zone within the Azure Region where this Storage Account should exist. Changing this forces a new Storage Account to be created. | `string` | `null` |
| <a name="input_enable_monitoring_alerts"></a> [enable\_monitoring\_alerts](#input\_enable\_monitoring\_alerts) | Enable Azure Monitor metric alerts for the Storage Account. | `bool` | `false` |
| <a name="input_https_traffic_only_enabled"></a> [https\_traffic\_only\_enabled](#input\_https\_traffic\_only\_enabled) | (Optional) Boolean flag which forces HTTPS if enabled, see [here](https://docs.microsoft.com/azure/storage/storage-require-secure-transfer/) for more information. Defaults to `true`. | `bool` | `true` |
| <a name="input_immutability_policy"></a> [immutability\_policy](#input\_immutability\_policy) | - `allow_protected_append_writes` - (Required) When enabled, new blocks can be written to an append blob while maintaining immutability protection and compliance. Only new blocks can be added and any existing blocks cannot be modified or deleted.<br/>- `period_since_creation_in_days` - (Required) The immutability period for the blobs in the container since the policy creation, in days.<br/>- `state` - (Required) Defines the mode of the policy. `Disabled` state disables the policy, `Unlocked` state allows increase and decrease of immutability retention time and also allows toggling allowProtectedAppendWrites property, `Locked` state only allows the increase of the immutability retention time. A policy can only be created in a Disabled or Unlocked state and can be toggled between the two states. Only a policy in an Unlocked state can transition to a Locked state which cannot be reverted. | <pre>object({<br/>    allow_protected_append_writes = bool<br/>    period_since_creation_in_days = number<br/>    state                         = string<br/>  })</pre> | `null` |
| <a name="input_infrastructure_encryption_enabled"></a> [infrastructure\_encryption\_enabled](#input\_infrastructure\_encryption\_enabled) | (Optional) Is infrastructure encryption enabled? Changing this forces a new resource to be created. Defaults to `false`. | `bool` | `false` |
| <a name="input_is_hns_enabled"></a> [is\_hns\_enabled](#input\_is\_hns\_enabled) | (Optional) Is Hierarchical Namespace enabled? This can be used with Azure Data Lake Storage Gen 2 ([see here for more information](https://docs.microsoft.com/azure/storage/blobs/data-lake-storage-quickstart-create-account/)). Changing this forces a new resource to be created. | `bool` | `null` |
| <a name="input_large_file_share_enabled"></a> [large\_file\_share\_enabled](#input\_large\_file\_share\_enabled) | (Optional) Is Large File Share Enabled? | `bool` | `true` |
| <a name="input_location"></a> [location](#input\_location) | Azure region where the resource group will be created | `string` | `"eastus2"` |
| <a name="input_lock"></a> [lock](#input\_lock) | Controls the Resource Lock configuration for this resource. The following properties can be specified:<br/><br/>  - `kind` - (Required) The type of lock. Possible values are `\"CanNotDelete\"` and `\"ReadOnly\"`.<br/>  - `name` - (Optional) The name of the lock. If not specified, a name will be generated based on the `kind` value. Changing this forces the creation of a new resource. | <pre>object({<br/>    kind = string<br/>    name = optional(string, null)<br/>  })</pre> | `null` |
| <a name="input_managed_identities"></a> [managed\_identities](#input\_managed\_identities) | Controls the Managed Identity configuration on this resource. The following properties can be specified:<br/><br/>  - `system_assigned` - (Optional) Specifies if the System Assigned Managed Identity should be enabled.<br/>  - `user_assigned_resource_ids` - (Optional) Specifies a list of User Assigned Managed Identity resource IDs to be assigned to this resource. | <pre>object({<br/>    system_assigned            = optional(bool, false)<br/>    user_assigned_resource_ids = optional(set(string), [])<br/>  })</pre> | `{}` |
| <a name="input_min_tls_version"></a> [min\_tls\_version](#input\_min\_tls\_version) | (Optional) The minimum supported TLS version for the storage account. Possible values are `TLS1_0`, `TLS1_1`, and `TLS1_2`. Defaults to `TLS1_2` for new storage accounts. | `string` | `"TLS1_2"` |
| <a name="input_name"></a> [name](#input\_name) | Name of the storage account | `string` | `null` |
| <a name="input_network_rules"></a> [network\_rules](#input\_network\_rules) | > Note the default value for this variable will block all public access to the storage account. If you want to disable all network rules, set this value to `null`.<br/><br/>- `bypass` - (Optional) Specifies whether traffic is bypassed for Logging/Metrics/AzureServices. Valid options are any combination of `Logging`, `Metrics`, `AzureServices`, or `None`.<br/>- `default_action` - (Required) Specifies the default action of allow or deny when no other rules match. Valid options are `Deny` or `Allow`.<br/>- `ip_rules` - (Optional) List of public IP or IP ranges in CIDR Format. Only IPv4 addresses are allowed. Private IP address ranges (as defined in [RFC 1918](https://tools.ietf.org/html/rfc1918#section-3)) are not allowed.<br/>- `storage_account_id` - (Required) Specifies the ID of the storage account. Changing this forces a new resource to be created.<br/>- `virtual_network_subnet_ids` - (Optional) A list of virtual network subnet ids to secure the storage account.<br/><br/>---<br/>`private_link_access` block supports the following:<br/>- `endpoint_resource_id` - (Required) The resource id of the resource access rule to be granted access.<br/>- `endpoint_tenant_id` - (Optional) The tenant id of the resource of the resource access rule to be granted access. Defaults to the current tenant id.<br/><br/>---<br/>`timeouts` block supports the following:<br/>- `create` - (Defaults to 60 minutes) Used when creating the  Network Rules for this Storage Account.<br/>- `delete` - (Defaults to 60 minutes) Used when deleting the Network Rules for this Storage Account.<br/>- `read` - (Defaults to 5 minutes) Used when retrieving the Network Rules for this Storage Account.<br/>- `update` - (Defaults to 60 minutes) Used when updating the Network Rules for this Storage Account. | <pre>object({<br/>    bypass                     = optional(set(string), ["AzureServices"])<br/>    default_action             = optional(string, "Deny")<br/>    ip_rules                   = optional(set(string), [])<br/>    virtual_network_subnet_ids = optional(set(string), [])<br/>    private_link_access = optional(list(object({<br/>      endpoint_resource_id = string<br/>      endpoint_tenant_id   = optional(string)<br/>    })))<br/>    timeouts = optional(object({<br/>      create = optional(string)<br/>      delete = optional(string)<br/>      read   = optional(string)<br/>      update = optional(string)<br/>    }))<br/>  })</pre> | `{}` |
| <a name="input_nfsv3_enabled"></a> [nfsv3\_enabled](#input\_nfsv3\_enabled) | (Optional) Is NFSv3 protocol enabled? Changing this forces a new resource to be created. Defaults to `false`. | `bool` | `false` |
| <a name="input_private_endpoints"></a> [private\_endpoints](#input\_private\_endpoints) | A map of private endpoints to create on the resource. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/><br/>- `name` - (Optional) The name of the private endpoint. One will be generated if not set.<br/>- `role_assignments` - (Optional) A map of role assignments to create on the private endpoint. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time. See `var.role_assignments` for more information.<br/>- `lock` - (Optional) The lock level to apply to the private endpoint. Default is `None`. Possible values are `None`, `CanNotDelete`, and `ReadOnly`.<br/>- `tags` - (Optional) A mapping of tags to assign to the private endpoint.<br/>- `subnet_resource_id` - The resource ID of the subnet to deploy the private endpoint in.<br/>- `subresource_name` - The service name of the private endpoint.  Possible value are `blob`, 'dfs', 'file', `queue`, `table`, and `web`. `blob` is being supported by this module.<br/>- `private_dns_zone_group_name` - (Optional) The name of the private DNS zone group. One will be generated if not set.<br/>- `private_dns_zone_resource_ids` - (Optional) A set of resource IDs of private DNS zones to associate with the private endpoint. If not set, no zone groups will be created and the private endpoint will not be associated with any private DNS zones. DNS records must be managed external to this module.<br/>- `application_security_group_resource_ids` - (Optional) A map of resource IDs of application security groups to associate with the private endpoint. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/>- `private_service_connection_name` - (Optional) The name of the private service connection. One will be generated if not set.<br/>- `network_interface_name` - (Optional) The name of the network interface. One will be generated if not set.<br/>- `location` - (Optional) The Azure location where the resources will be deployed. Defaults to the location of the resource group.<br/>- `resource_group_name` - (Optional) The resource group where the resources will be deployed. Defaults to the resource group of the resource.<br/>- `ip_configurations` - (Optional) A map of IP configurations to create on the private endpoint. If not specified the platform will create one. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/>  - `name` - The name of the IP configuration.<br/>  - `private_ip_address` - The private IP address of the IP configuration. | <pre>map(object({<br/>    name = optional(string, null)<br/>    role_assignments = optional(map(object({<br/>      role_definition_id_or_name             = string<br/>      principal_id                           = string<br/>      description                            = optional(string, null)<br/>      skip_service_principal_aad_check       = optional(bool, false)<br/>      condition                              = optional(string, null)<br/>      condition_version                      = optional(string, null)<br/>      delegated_managed_identity_resource_id = optional(string, null)<br/>      principal_type                         = optional(string, null)<br/>    })), {})<br/>    lock = optional(object({<br/>      kind = string<br/>      name = optional(string, null)<br/>    }), null)<br/>    tags                                    = optional(map(string), null)<br/>    subnet_resource_id                      = string<br/>    subresource_name                        = optional(string, "blob") # By default, blob is declared in the PE resource<br/>    private_dns_zone_group_name             = optional(string, "default")<br/>    private_dns_zone_resource_ids           = optional(set(string), [])<br/>    application_security_group_associations = optional(map(string), {})<br/>    private_service_connection_name         = optional(string, null)<br/>    network_interface_name                  = optional(string, null)<br/>    location                                = optional(string, null)<br/>    resource_group_name                     = optional(string, null)<br/>    ip_configurations = optional(map(object({<br/>      name               = string<br/>      private_ip_address = string<br/>    })), {})<br/>  }))</pre> | `{}` |
| <a name="input_private_endpoints_manage_dns_zone_group"></a> [private\_endpoints\_manage\_dns\_zone\_group](#input\_private\_endpoints\_manage\_dns\_zone\_group) | Whether to manage private DNS zone groups with this module. If set to false, you must manage private DNS zone groups externally, e.g. using Azure Policy. | `bool` | `true` |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | (Optional) Whether the public network access is enabled? Defaults to `false`. | `bool` | `false` |
| <a name="input_queue_encryption_key_type"></a> [queue\_encryption\_key\_type](#input\_queue\_encryption\_key\_type) | (Optional) The encryption type of the queue service. Possible values are `Service` and `Account`. Changing this forces a new resource to be created. Default value is `Service`. | `string` | `null` |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group where resources will be created | `string` | n/a |
| <a name="input_role_assignments"></a> [role\_assignments](#input\_role\_assignments) | A map of role assignments to create on the <RESOURCE>. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/><br/>  - `role_definition_id_or_name` - The ID or name of the role definition to assign to the principal.<br/>  - `principal_id` - The ID of the principal to assign the role to.<br/>  - `description` - (Optional) The description of the role assignment.<br/>  - `skip_service_principal_aad_check` - (Optional) If set to true, skips the Azure Active Directory check for the service principal in the tenant. Defaults to false.<br/>  - `condition` - (Optional) The condition which will be used to scope the role assignment.<br/>  - `condition_version` - (Optional) The version of the condition syntax. Leave as `null` if you are not using a condition, if you are then valid values are '2.0'.<br/>  - `delegated_managed_identity_resource_id` - (Optional) The delegated Azure Resource Id which contains a Managed Identity. Changing this forces a new resource to be created. This field is only used in cross-tenant scenario.<br/>  - `principal_type` - (Optional) The type of the `principal_id`. Possible values are `User`, `Group` and `ServicePrincipal`. It is necessary to explicitly set this attribute when creating role assignments if the principal creating the assignment is constrained by ABAC rules that filters on the PrincipalType attribute.<br/><br/>  > Note: only set `skip_service_principal_aad_check` to true if you are assigning a role to a service principal. | <pre>map(object({<br/>    role_definition_id_or_name             = string<br/>    principal_id                           = string<br/>    scope                                  = string<br/>    description                            = optional(string, null)<br/>    skip_service_principal_aad_check       = optional(bool, false)<br/>    condition                              = optional(string, null)<br/>    condition_version                      = optional(string, null)<br/>    delegated_managed_identity_resource_id = optional(string, null)<br/>    principal_type                         = optional(string, null)<br/>  }))</pre> | `{}` |
| <a name="input_routing"></a> [routing](#input\_routing) | - `choice` - (Optional) Specifies the kind of network routing opted by the user. Possible values are `InternetRouting` and `MicrosoftRouting`. Defaults to `MicrosoftRouting`.<br/>- `publish_internet_endpoints` - (Optional) Should internet routing storage endpoints be published? Defaults to `false`.<br/>- `publish_microsoft_endpoints` - (Optional) Should Microsoft routing storage endpoints be published? Defaults to `false`. | <pre>object({<br/>    choice                      = optional(string, "MicrosoftRouting")<br/>    publish_internet_endpoints  = optional(bool, false)<br/>    publish_microsoft_endpoints = optional(bool, false)<br/>  })</pre> | `null` |
| <a name="input_sas_policy"></a> [sas\_policy](#input\_sas\_policy) | - `expiration_action` - (Optional) The SAS expiration action. The only possible value is `Log` at this moment. Defaults to `Log`.<br/>- `expiration_period` - (Required) The SAS expiration period in format of `DD.HH:MM:SS`. | <pre>object({<br/>    expiration_action = optional(string, "Log")<br/>    expiration_period = string<br/>  })</pre> | `null` |
| <a name="input_sftp_enabled"></a> [sftp\_enabled](#input\_sftp\_enabled) | (Optional) Boolean, enable SFTP for the storage account.  Defaults to `false`. | `bool` | `false` |
| <a name="input_share_properties"></a> [share\_properties](#input\_share\_properties) | ---<br/>`cors_rule` block supports the following:<br/>- `allowed_headers` - (Required) A list of headers that are allowed to be a part of the cross-origin request.<br/>- `allowed_methods` - (Required) A list of HTTP methods that are allowed to be executed by the origin. Valid options are `DELETE`, `GET`, `HEAD`, `MERGE`, `POST`, `OPTIONS`, `PUT` or `PATCH`.<br/>- `allowed_origins` - (Required) A list of origin domains that will be allowed by CORS.<br/>- `exposed_headers` - (Required) A list of response headers that are exposed to CORS clients.<br/>- `max_age_in_seconds` - (Required) The number of seconds the client should cache a preflight response.<br/><br/>---<br/>`diagnostic_settings` block supports the following:<br/>- `name` - (Optional) The name of the diagnostic setting. Defaults to `null`.<br/>- `log_categories` - (Optional) A set of log categories to enable. Defaults to an empty set.<br/>- `log_groups` - (Optional) A set of log groups to enable. Defaults to `["allLogs"]`.<br/>- `metric_categories` - (Optional) A set of metric categories to enable. Defaults to `["AllMetrics"]`.<br/>- `log_analytics_destination_type` - (Optional) The destination type for log analytics. Defaults to `"Dedicated"`.<br/>- `workspace_resource_id` - (Optional) The resource ID of the Log Analytics workspace. Defaults to `null`.<br/>- `resource_id` - (Optional) The resource ID of the target resource for diagnostics. Defaults to `null`.<br/>- `event_hub_authorization_rule_resource_id` - (Optional) The resource ID of the Event Hub authorization rule. Defaults to `null`.<br/>- `event_hub_name` - (Optional) The name of the Event Hub. Defaults to `null`.<br/>- `marketplace_partner_resource_id` - (Optional) The resource ID of the marketplace partner. Defaults to `null`.<br/><br/>---<br/>`retention_policy` block supports the following:<br/>- `days` - (Optional) Specifies the number of days that the `azurerm_shares` should be retained, between `1` and `365` days. Defaults to `7`.<br/><br/>---<br/>`smb` block supports the following:<br/>- `authentication_types` - (Optional) A set of SMB authentication methods. Possible values are `NTLMv2`, and `Kerberos`.<br/>- `channel_encryption_type` - (Optional) A set of SMB channel encryption. Possible values are `AES-128-CCM`, `AES-128-GCM`, and `AES-256-GCM`.<br/>- `kerberos_ticket_encryption_type` - (Optional) A set of Kerberos ticket encryption. Possible values are `RC4-HMAC`, and `AES-256`.<br/>- `multichannel_enabled` - (Optional) Indicates whether multichannel is enabled. Defaults to `false`. This is only supported on Premium storage accounts.<br/>- `versions` - (Optional) A set of SMB protocol versions. Possible values are `SMB2.1`, `SMB3.0`, and `SMB3.1.1`. | <pre>object({<br/>    cors_rule = optional(list(object({<br/>      allowed_headers    = list(string)<br/>      allowed_methods    = list(string)<br/>      allowed_origins    = list(string)<br/>      exposed_headers    = list(string)<br/>      max_age_in_seconds = number<br/>    })))<br/>    diagnostic_settings = optional(map(object({<br/>      name                                     = optional(string, null)<br/>      log_categories                           = optional(set(string), [])<br/>      log_groups                               = optional(set(string), ["allLogs"])<br/>      metric_categories                        = optional(set(string), ["AllMetrics"])<br/>      log_analytics_destination_type           = optional(string, "Dedicated")<br/>      workspace_resource_id                    = optional(string, null)<br/>      resource_id                              = optional(string, null)<br/>      event_hub_authorization_rule_resource_id = optional(string, null)<br/>      event_hub_name                           = optional(string, null)<br/>      marketplace_partner_resource_id          = optional(string, null)<br/>    })), {})<br/>    retention_policy = optional(object({<br/>      days = optional(number)<br/>    }))<br/>    smb = optional(object({<br/>      authentication_types            = optional(set(string))<br/>      channel_encryption_type         = optional(set(string))<br/>      kerberos_ticket_encryption_type = optional(set(string))<br/>      multichannel_enabled            = optional(bool)<br/>      versions                        = optional(set(string))<br/>    }))<br/>  })</pre> | `null` |
| <a name="input_shared_access_key_enabled"></a> [shared\_access\_key\_enabled](#input\_shared\_access\_key\_enabled) | (Optional) Indicates whether the storage account permits requests to be authorized with the account access key via Shared Key. If false, then all requests, including shared access signatures, must be authorized with Azure Active Directory (Azure AD). The default value is `true`. | `bool` | `true` |
| <a name="input_storage_account_alerts"></a> [storage\_account\_alerts](#input\_storage\_account\_alerts) | Configuration for Storage Account monitoring alerts. Define each alert explicitly with metric\_name, aggregation, operator, threshold, and dimensions as required by the Azure metric you are targeting. | <pre>map(object({<br/>    name              = optional(string, null)<br/>    enabled           = optional(bool, true)<br/>    description       = optional(string)<br/>    metric_name       = string<br/>    criterion_type    = optional(string, "StaticThresholdCriterion")<br/>    aggregation       = optional(string, "Average")<br/>    operator          = optional(string, "GreaterThan")<br/>    threshold         = optional(number)<br/>    severity          = optional(number, 3)<br/>    frequency         = optional(string, "PT1M")<br/>    window            = optional(string, "PT1M")<br/>    auto_mitigate     = optional(bool, true)<br/>    alert_sensitivity = optional(string)<br/>    failing_periods = optional(object({<br/>      min_failing_periods_to_alert = number<br/>      number_of_evaluation_periods = number<br/>    }))<br/>    dimensions = optional(list(object({<br/>      name     = string<br/>      operator = optional(string, "Include")<br/>      values   = list(string)<br/>    })), [])<br/>  }))</pre> | `{}` |
| <a name="input_table_encryption_key_type"></a> [table\_encryption\_key\_type](#input\_table\_encryption\_key\_type) | (Optional) The encryption type of the table service. Possible values are `Service` and `Account`. Changing this forces a new resource to be created. Default value is `Service`. | `string` | `null` |
| <a name="input_tags"></a> [tags](#input\_tags) | Map of tags to be applied to all resources | `map(string)` | <pre>{<br/>  "business_unit": "banking",<br/>  "customer": "myridius",<br/>  "environment": "dev",<br/>  "owner": "devops",<br/>  "product": "gh",<br/>  "region": "eastus2"<br/>}</pre> |
| <a name="input_timeouts"></a> [timeouts](#input\_timeouts) | - `create` - (Defaults to 60 minutes) Used when creating the Storage Account.<br/>- `delete` - (Defaults to 60 minutes) Used when deleting the Storage Account.<br/>- `read` - (Defaults to 5 minutes) Used when retrieving the Storage Account.<br/>- `update` - (Defaults to 60 minutes) Used when updating the Storage Account. | <pre>object({<br/>    create = optional(string)<br/>    delete = optional(string)<br/>    read   = optional(string)<br/>    update = optional(string)<br/>  })</pre> | `null` |
| <a name="input_user_preferred_index"></a> [user\_preferred\_index](#input\_user\_preferred\_index) | A value to append at the end of the name | `number` | `1` |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_storage_account_access_key"></a> [storage\_account\_access\_key](#output\_storage\_account\_access\_key) | The access key for the storage account |
| <a name="output_storage_account_blob_private_fqdn"></a> [storage\_account\_blob\_private\_fqdn](#output\_storage\_account\_blob\_private\_fqdn) | The private endpoint of the blob service |
| <a name="output_storage_account_blob_public_fqdn"></a> [storage\_account\_blob\_public\_fqdn](#output\_storage\_account\_blob\_public\_fqdn) | The public endpoint of the blob service |
| <a name="output_storage_account_file_private_fqdn"></a> [storage\_account\_file\_private\_fqdn](#output\_storage\_account\_file\_private\_fqdn) | The private endpoint of the file service |
| <a name="output_storage_account_file_public_fqdn"></a> [storage\_account\_file\_public\_fqdn](#output\_storage\_account\_file\_public\_fqdn) | The public endpoint of the file service |
| <a name="output_storage_account_name"></a> [storage\_account\_name](#output\_storage\_account\_name) | The name of the storage account |
| <a name="output_storage_account_private_end_point_id"></a> [storage\_account\_private\_end\_point\_id](#output\_storage\_account\_private\_end\_point\_id) | The name of the storage account private endpoint |
| <a name="output_storage_account_private_end_point_name"></a> [storage\_account\_private\_end\_point\_name](#output\_storage\_account\_private\_end\_point\_name) | The name of the storage account private endpoint |
| <a name="output_storage_account_private_endpoints"></a> [storage\_account\_private\_endpoints](#output\_storage\_account\_private\_endpoints) | A map of private endpoints. The map key is the supplied input to var.private\_endpoints. The map value is the entire azurerm\_private\_endpoint resource. |
| <a name="output_storage_account_queue_private_fqdn"></a> [storage\_account\_queue\_private\_fqdn](#output\_storage\_account\_queue\_private\_fqdn) | The private endpoint of the queue service |
| <a name="output_storage_account_queue_public_fqdn"></a> [storage\_account\_queue\_public\_fqdn](#output\_storage\_account\_queue\_public\_fqdn) | The public endpoint of the queue service |
| <a name="output_storage_account_resource_id"></a> [storage\_account\_resource\_id](#output\_storage\_account\_resource\_id) | The ID of the Storage Account. |
| <a name="output_storage_account_table_private_fqdn"></a> [storage\_account\_table\_private\_fqdn](#output\_storage\_account\_table\_private\_fqdn) | The private endpoint of the table service |
| <a name="output_storage_account_table_public_fqdn"></a> [storage\_account\_table\_public\_fqdn](#output\_storage\_account\_table\_public\_fqdn) | The public endpoint of the table service |

# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v1.0.0] - 2026-06-18
### Added
- Initial release of the module to create:
  - Azure Storage Account with configurable replication, tier, kind, networking, and encryption
  - Optional resource-level lock for protection of critical environments
  - Role assignments (RBAC) for fine-grained access control
  - Customer-managed keys (CMK) integration with Azure Key Vault
  - Private Endpoint for secure, private access to Storage Account with managing the private DNS zone option
  - Azure Monitor diagnostic settings with support for Log Analytics, Event Hub, and Storage
  - Network rules with IP restrictions and VNet-based access
  - Private Endpoints for multiple subresource names based on the input
  - Storage Account metric alerts with static and dynamic criteria support.

<!-- END_TF_DOCS -->
