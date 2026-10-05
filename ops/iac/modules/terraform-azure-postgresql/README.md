<!-- BEGIN_TF_DOCS -->


## Introduction

This module provisions an **Azure PostgreSQL Flexible Server** with optional integrations for high availability, security, identity management, observability, and network isolation.

---

## 📘 Overview

This module enables:

- **Azure PostgreSQL Flexible Server** deployment with configurable SKU, version, storage, backup retention, and availability zone placement
- **High availability** support with `ZoneRedundant` or `SameZone` modes and automatic standby provisioning
- **Authentication flexibility** — password-based, Azure Active Directory, or both; supports ephemeral passwords to avoid storing credentials in state
- **Active Directory administrator** assignment for EntraID-based access control
- **Customer-managed keys (CMK)** integration via Azure Key Vault for encryption at rest, including geo-backup key support
- **Managed identity** support for both system-assigned and user-assigned identities
- **Private endpoints** for secure, private network access to the PostgreSQL server
- **Private DNS zone integration** for seamless name resolution of private endpoints
- **Firewall rules** for IP-based access control when public access is required
- **Virtual endpoints** for read/write routing across primary and replica servers
- **Server configuration** parameters for fine-grained PostgreSQL engine tuning
- **Diagnostic settings** to route logs and metrics to Log Analytics, Storage Account, or Event Hub
- **Role assignments (RBAC)** for fine-grained access control on the server and private endpoints
- **Resource locks** to protect against accidental deletion or modification
- **Maintenance window** configuration for controlled update scheduling
- **Geo-redundant backups** with configurable retention (7–35 days)
- **Storage auto-grow** to automatically expand storage as data grows

#Examples

#Basic Example
```hcl


# Random password
resource "random_password" "this" {
  length           = 10
  override_special = "!$?"
  special          = true
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

# Postgresql server
module "pgsql" {
  source = "../../"

  location               = "eastus2"
  resource_group_name    = "rg-gh-dev-sandbox"
  administrator_login    = "cloudpostgresqlghadmin"
  administrator_password = random_password.this.result
  authentication = {
    password_auth_enabled = true
  }
  high_availability             = null #For B_ prefix skus, high availability is not supported
  public_network_access_enabled = true
  sku_name                      = "B_Standard_B2s"
  server_version                = 18
  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }

  firewall_rules = {
    firewall-rule-US-VPN-IP = {
      name             = "firewall-rule-US-VPN-IP"
      start_ip_address = "208.195.3.201"
      end_ip_address   = "208.195.3.201"
    }
  }
}





terraform {

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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

#Database Example
```hcl


# Random password
resource "random_password" "this" {
  length           = 10
  override_special = "!$?"
  special          = true
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

# Create Log Analaytics workspace - Ideally, we will have only one log analytics for the whole environment; for the purpose of testing, this work space is being created.
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

# Create Application Insights (workspace-based) - Ideally we will have only one app insights for the whole environment; for the purpose of testing, this app insights is being created.
resource "azurerm_application_insights" "app_insights" {
  name                = "appi-gh-dev-sandbox"
  location            = "eastus2"
  resource_group_name = "rg-gh-dev-sandbox"
  application_type    = "other"
  workspace_id        = azurerm_log_analytics_workspace.log_analytics_workspace.id
}

# Postgresql server
module "pgsql" {
  source = "../../"

  user_preferred_index   = 2
  location               = "eastus2"
  resource_group_name    = "rg-gh-dev-sandbox"
  administrator_login    = "cloudpostgresqlghadmin"
  administrator_password = random_password.this.result
  authentication = {
    active_directory_auth_enabled = true
    password_auth_enabled         = true
    tenant_id                     = "7aa4356e-1227-4975-bb58-165bff68ff0a" #data.azurerm_client_config.this.tenant_id
  }
  geo_redundant_backup_enabled = false #Changing this will re-create the server; #For Production workloads, this can be enabled considering an additional cost based on backup storage.
  high_availability            = null  #For B_ prefix skus, high availability is not supported; If needed, use this block for Production workloads as there is cost associated to it.
  # high_availability = {
  #     mode                      = "ZoneRedundant" #Possible value are `SameZone` or `ZoneRedundant`.
  #     standby_availability_zone = 2
  #   }
  public_network_access_enabled = true
  sku_name                      = "GP_Standard_D2ds_v5"
  server_version                = 18
  storage_mb                    = 131072
  storage_tier                  = "P10"
  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }

  ad_administrator = {
    admin1 = {
      tenant_id      = "7aa4356e-1227-4975-bb58-165bff68ff0a" #data.azurerm_client_config.this.tenant_id
      object_id      = "b5b38394-a156-4df0-a7c4-441bed5e48a8" #suraj
      principal_name = "Suraj.Koditala@myridius.com"
      principal_type = "User"
    }
  }

  firewall_rules = {
    firewall-rule-US-VPN-IP = {
      name             = "firewall-rule-US-VPN-IP"
      start_ip_address = "208.195.3.201"
      end_ip_address   = "208.195.3.201"
    }
    firewall-rule-Manila-VPN-IP = {
      name             = "firewall-rule-Manila-VPN-IP"
      start_ip_address = "210.14.21.200"
      end_ip_address   = "210.14.21.200"
    }
    firewall-rule-Chennai-VPN-IP = {
      name             = "firewall-rule-Chennai-VPN-IP"
      start_ip_address = "157.66.143.200"
      end_ip_address   = "157.66.143.200"
    }
    firewall-rule-SK-IP = {
      name             = "firewall-rule-SK-IP"
      start_ip_address = "99.2.116.74"
      end_ip_address   = "99.2.116.74"
    }
  }

  databases = {
    gh_mrc_pg = {
      name = "gh_mrc_pg"
      # charset   = "UTF8"
      # collation = "en_US.utf8"
    }
  }

  # Enabling diagnostic settings
  diagnostic_settings = {
    pgsql_diag_setting = {
      name                           = "pgsql-gh-dev-sandbox-diagnostic-setting"
      workspace_resource_id          = azurerm_log_analytics_workspace.log_analytics_workspace.id
      log_analytics_destination_type = "Dedicated" # Or "AzureDiagnostics"
      log_groups                     = ["allLogs"]
      metric_categories              = ["AllMetrics"]
    }
  }

  # private end point creation
  private_endpoints = {
    pgsql_pe = {
      subnet_resource_id            = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01" #PEP subnet ID
      private_dns_zone_resource_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev01/providers/Microsoft.Network/privateDnsZones/privatelink.postgres.database.azure.com"]                 #Subscription level postgres dns zone
    }
  }
}



output "postgresql_server_fqdn" {
  value       = module.pgsql.postgresql_server_fqdn
  description = "The fully qualified domain name of the PostgreSQL Flexible Server."
}

terraform {

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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


# Random password
resource "random_password" "this" {
  length           = 10
  override_special = "!$?"
  special          = true
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

# Create Log Analaytics workspace - Ideally, we will have only one log analytics for the whole environment; for the purpose of testing, this work space is being created.
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

# Create Application Insights (workspace-based) - Ideally we will have only one app insights for the whole environment; for the purpose of testing, this app insights is being created.
resource "azurerm_application_insights" "app_insights" {
  name                = "appi-gh-dev-sandbox"
  location            = "eastus2"
  resource_group_name = "rg-gh-dev-sandbox"
  application_type    = "other"
  workspace_id        = azurerm_log_analytics_workspace.log_analytics_workspace.id
}

# Postgresql server
module "pgsql" {
  source = "../../"

  location               = "eastus2"
  resource_group_name    = "rg-gh-dev-sandbox"
  administrator_login    = "cloudpostgresqlghadmin"
  administrator_password = random_password.this.result
  authentication = {
    active_directory_auth_enabled = true
    password_auth_enabled         = true
    tenant_id                     = "7aa4356e-1227-4975-bb58-165bff68ff0a" #data.azurerm_client_config.this.tenant_id
  }
  geo_redundant_backup_enabled = false #Changing this will re-create the server; #For Production workloads, this can be enabled considering an additional cost based on backup storage.
  high_availability            = null  #For B_ prefix skus, high availability is not supported; If needed, use this block for Production workloads as there is cost associated to it.
  # high_availability = {
  #     mode                      = "ZoneRedundant" #Possible value are `SameZone` or `ZoneRedundant`.
  #     standby_availability_zone = 2
  #   }
  public_network_access_enabled = true
  sku_name                      = "GP_Standard_D2ds_v5"
  server_version                = 18
  storage_mb                    = 131072
  storage_tier                  = "P10"
  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }

  ad_administrator = {
    admin1 = {
      tenant_id      = "7aa4356e-1227-4975-bb58-165bff68ff0a" #data.azurerm_client_config.this.tenant_id
      object_id      = "b5b38394-a156-4df0-a7c4-441bed5e48a8" #suraj
      principal_name = "Suraj.Koditala@myridius.com"
      principal_type = "User"
    }
  }

  firewall_rules = {
    firewall-rule-US-VPN-IP = {
      name             = "firewall-rule-US-VPN-IP"
      start_ip_address = "208.195.3.201"
      end_ip_address   = "208.195.3.201"
    }
    firewall-rule-Manila-VPN-IP = {
      name             = "firewall-rule-Manila-VPN-IP"
      start_ip_address = "210.14.21.200"
      end_ip_address   = "210.14.21.200"
    }
    firewall-rule-Chennai-VPN-IP = {
      name             = "firewall-rule-Chennai-VPN-IP"
      start_ip_address = "157.66.143.200"
      end_ip_address   = "157.66.143.200"
    }
    firewall-rule-SK-IP = {
      name             = "firewall-rule-SK-IP"
      start_ip_address = "99.2.116.74"
      end_ip_address   = "99.2.116.74"
    }
  }

  # Enabling diagnostic settings
  diagnostic_settings = {
    pgsql_diag_setting = {
      name                           = "pgsql-gh-dev-sandbox-diagnostic-setting"
      workspace_resource_id          = azurerm_log_analytics_workspace.log_analytics_workspace.id
      log_analytics_destination_type = "Dedicated" # Or "AzureDiagnostics"
      log_groups                     = ["allLogs"]
      metric_categories              = ["AllMetrics"]
    }
  }

  # private end point creation
  private_endpoints = {
    pgsql_pe = {
      subnet_resource_id            = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01" #PEP subnet ID
      private_dns_zone_resource_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev01/providers/Microsoft.Network/privateDnsZones/privatelink.postgres.database.azure.com"]                 #Subscription level postgres dns zone
    }
  }
}



output "postgresql_server_fqdn" {
  value       = module.pgsql.postgresql_server_fqdn
  description = "The fully qualified domain name of the PostgreSQL Flexible Server."
}

terraform {

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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


# Random password
resource "random_password" "this" {
  length           = 10
  override_special = "!$?"
  special          = true
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

# Create Log Analaytics workspace - Ideally, we will have only one log analytics for the whole environment; for the purpose of testing, this work space is being created.
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

# Create Application Insights (workspace-based) - Ideally we will have only one app insights for the whole environment; for the purpose of testing, this app insights is being created.
resource "azurerm_application_insights" "app_insights" {
  name                = "appi-gh-dev-sandbox"
  location            = "eastus2"
  resource_group_name = "rg-gh-dev-sandbox"
  application_type    = "other"
  workspace_id        = azurerm_log_analytics_workspace.log_analytics_workspace.id
}

# Postgresql server
module "pgsql" {
  source = "../../"

  location               = "eastus2"
  resource_group_name    = "rg-gh-dev-sandbox"
  administrator_login    = "cloudpostgresqlghadmin"
  administrator_password = random_password.this.result
  authentication = {
    password_auth_enabled = true
  }
  high_availability             = null #For B_ prefix skus, high availability is not supported
  public_network_access_enabled = true
  sku_name                      = "B_Standard_B2s"
  server_version                = 18
  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }

  firewall_rules = {
    firewall-rule-US-VPN-IP = {
      name             = "firewall-rule-US-VPN-IP"
      start_ip_address = "208.195.3.201"
      end_ip_address   = "208.195.3.201"
    }
  }

  # Enabling diagnostic settings
  diagnostic_settings = {
    pgsql_diag_setting = {
      name                           = "pgsql-gh-dev-sandbox-diagnostic-setting"
      workspace_resource_id          = azurerm_log_analytics_workspace.log_analytics_workspace.id
      log_analytics_destination_type = "Dedicated" # Or "AzureDiagnostics"
      log_groups                     = ["allLogs"]
      metric_categories              = ["AllMetrics"]
    }
  }
}



output "postgresql_server_fqdn" {
  value       = module.pgsql.postgresql_server_fqdn
  description = "The fully qualified domain name of the PostgreSQL Flexible Server."
}

terraform {

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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

#Ephemeral Password Example
```hcl
# Generate the password EPHEMERALLY (NEVER persisted to state)
# Each plan/apply will generate a new string but wo_version of KV and pgsql manages the rotation of the password.
# For this to work where you need to write ephemeral result to KV, need to handle network access (for eg. if it's from TFC, need to use agent or else go with resource random_password and remove KV writing step)
ephemeral "random_password" "this" {
  length           = 10
  special          = true
  override_special = "!$?"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

# Retrieving Tenant id details for the key vault.
data "azurerm_client_config" "this" {}

# Assigning KV secrets permission to TFC service principal to store the secrets
resource "azurerm_role_assignment" "tfc_kv_secrets_officer" {
  scope                = module.keyvault.key_vault_resource_id
  role_definition_name = "Key Vault Secrets Officer" # Access to write secrets
  principal_id         = data.azurerm_client_config.this.object_id
}

# KV to store the secret - Will use the centralized KV resource in the environment; Creating this separately for testing
module "keyvault" {
  source  = "app.terraform.io/Myridius-Insurity-ERC/keyvault/azure" # In reality, this will be like "app.terraform.io/<tfc-org-name>/<registry-name>/azure"; version = "<version>"
  version = "1.0.0"

  location            = "eastus2"
  resource_group_name = "rg-gh-dev-sandbox"
  tags = { # keyvault module is sourced from the TFC registry (not yet migrated locally) -- still needs the old ct_ tag schema
    "ct_insurity_product" = "erc"
    "ct_environment"      = "dev-sandbox"
    "ct_customer"         = "erc-client"
    "ct_business_unit"    = "insurity-product"
    "ct_owner"            = "devops"
    "ct_region"           = "eastus2"
  }
  tenant_id = data.azurerm_client_config.this.tenant_id

  network_acls = {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = ["157.66.143.200/32", "210.14.21.200/32", "208.195.3.201/32", "99.2.116.74"]                                                                                                                                                                                                                                                                                                     #Need to add the IP from where the apply and execution is happening for the access to KV data plane.                                                                                                                                                                                                                                                                                                       #Company VPNs                                                                                                                                                                                                                                                                                                                  #VPN IPs
    virtual_network_subnet_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-cae-dev-sandbox-01", "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01"] #Subnets of the resources from which access is needed
  }

  # private end point creation
  private_endpoints = {
    kv_pe = {
      subnet_resource_id            = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01" #PEP subnet ID
      private_dns_zone_resource_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev01/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"]                         #Shared RG default KV dns zone
    }
  }

}

# Store it in Key Vault using a write-only attribute
resource "azurerm_key_vault_secret" "this" {
  name             = "cloudpostgresqlghadmin-password"
  key_vault_id     = module.keyvault.key_vault_resource_id
  value_wo         = ephemeral.random_password.this.result
  value_wo_version = 1 # To change the password, bump this number

  depends_on = [azurerm_role_assignment.tfc_kv_secrets_officer]
}

# Read the password back from Key Vault — guarantees a single source of truth
ephemeral "azurerm_key_vault_secret" "this" {
  name         = azurerm_key_vault_secret.this.name
  key_vault_id = module.keyvault.key_vault_resource_id
}

# Postgresql server
module "pgsql" {
  source = "../../"

  location                          = "eastus2"
  resource_group_name               = "rg-gh-dev-sandbox"
  administrator_login               = "cloudpostgresqlghadmin"
  administrator_password_wo         = ephemeral.azurerm_key_vault_secret.this.value
  administrator_password_wo_version = azurerm_key_vault_secret.this.value_wo_version
  authentication = {
    active_directory_auth_enabled = true
    password_auth_enabled         = true
    tenant_id                     = "7aa4356e-1227-4975-bb58-165bff68ff0a" #data.azurerm_client_config.this.tenant_id
  }
  #   geo_redundant_backup_enabled = true
  high_availability = null #For B_ prefix skus, high availability is not supported
  #   high_availability = {
  #     mode                      = "ZoneRedundant"
  #     standby_availability_zone = 2
  #   }
  public_network_access_enabled = true
  sku_name                      = "B_Standard_B2s"
  server_version                = 18
  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }
  #   zone           = 1

  ad_administrator = {
    admin1 = {
      tenant_id      = "7aa4356e-1227-4975-bb58-165bff68ff0a" #data.azurerm_client_config.this.tenant_id
      object_id      = "b5b38394-a156-4df0-a7c4-441bed5e48a8" #suraj
      principal_name = "Suraj.Koditala@myridius.com"
      principal_type = "User"
    }
  }

  firewall_rules = {
    firewall-rule-US-VPN-IP = {
      name             = "firewall-rule-US-VPN-IP"
      start_ip_address = "99.2.116.74"
      end_ip_address   = "99.2.116.74"
    }
  }
}





terraform {

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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


# Random password
resource "random_password" "this" {
  length           = 10
  override_special = "!$?"
  special          = true
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

# Postgresql server
module "pgsql" {
  source = "../../"

  location               = "eastus2"
  resource_group_name    = "rg-gh-dev-sandbox"
  administrator_login    = "cloudpostgresqlghadmin"
  administrator_password = random_password.this.result
  authentication = {
    active_directory_auth_enabled = true
    password_auth_enabled         = true
    tenant_id                     = "7aa4356e-1227-4975-bb58-165bff68ff0a" #data.azurerm_client_config.this.tenant_id
  }
  geo_redundant_backup_enabled = false #Changing this will re-create the server; #For Production workloads, this can be enabled considering an additional cost based on backup storage.
  high_availability            = null  #For B_ prefix skus, high availability is not supported; If needed, use this block for Production workloads as there is cost associated to it.
  # high_availability = {
  #     mode                      = "ZoneRedundant" #Possible value are `SameZone` or `ZoneRedundant`.
  #     standby_availability_zone = 2
  #   }
  public_network_access_enabled = true
  sku_name                      = "GP_Standard_D2ds_v5"
  server_version                = 18
  storage_mb                    = 131072
  storage_tier                  = "P10"
  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }

  ad_administrator = {
    admin1 = {
      tenant_id      = "7aa4356e-1227-4975-bb58-165bff68ff0a" #data.azurerm_client_config.this.tenant_id
      object_id      = "b5b38394-a156-4df0-a7c4-441bed5e48a8" #suraj
      principal_name = "Suraj.Koditala@myridius.com"
      principal_type = "User"
    }
  }

  firewall_rules = {
    firewall-rule-US-VPN-IP = {
      name             = "firewall-rule-US-VPN-IP"
      start_ip_address = "208.195.3.201"
      end_ip_address   = "208.195.3.201"
    }
    firewall-rule-Manila-VPN-IP = {
      name             = "firewall-rule-Manila-VPN-IP"
      start_ip_address = "210.14.21.200"
      end_ip_address   = "210.14.21.200"
    }
    firewall-rule-Chennai-VPN-IP = {
      name             = "firewall-rule-Chennai-VPN-IP"
      start_ip_address = "157.66.143.200"
      end_ip_address   = "157.66.143.200"
    }
    firewall-rule-SK-IP = {
      name             = "firewall-rule-SK-IP"
      start_ip_address = "99.2.116.74"
      end_ip_address   = "99.2.116.74"
    }
  }

  # private end point creation
  private_endpoints = {
    pgsql_pe = {
      subnet_resource_id            = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01" #PEP subnet ID
      private_dns_zone_resource_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev01/providers/Microsoft.Network/privateDnsZones/privatelink.postgres.database.azure.com"]                 #Subscription level postgres dns zone
    }
  }
}



output "postgresql_server_fqdn" {
  value       = module.pgsql.postgresql_server_fqdn
  description = "The fully qualified domain name of the PostgreSQL Flexible Server."
}

terraform {

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.12 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.81.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_databases"></a> [databases](#module\_databases) | ./modules/database | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_management_lock.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_lock) | resource |
| [azurerm_monitor_diagnostic_setting.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_postgresql_flexible_server.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server) | resource |
| [azurerm_postgresql_flexible_server_active_directory_administrator.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server_active_directory_administrator) | resource |
| [azurerm_postgresql_flexible_server_configuration.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server_configuration) | resource |
| [azurerm_postgresql_flexible_server_firewall_rule.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server_firewall_rule) | resource |
| [azurerm_postgresql_flexible_server_virtual_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server_virtual_endpoint) | resource |
| [azurerm_private_endpoint.this_managed_dns_zone_groups](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_private_endpoint.this_unmanaged_dns_zone_groups](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_private_endpoint_application_security_group_association.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint_application_security_group_association) | resource |
| [azurerm_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| <a name="input_ad_administrator"></a> [ad\_administrator](#input\_ad\_administrator) | A map to allow you to set a user or group as the AD administrator for a PostgreSQL Flexible Server.<br/><br/>- `tenant_id` - The Azure Tenant ID. Changing this forces a new resource to be created.<br/>- `object_id` - The object ID of a user, service principal or security group in the Azure Active Directory tenant set as the Flexible Server Admin. Changing this forces a new resource to be created.<br/>- `principal_name` - The name of Azure Active Directory principal. Changing this forces a new resource to be created.<br/>- `principal_type` - The type of Azure Active Directory principal. Possible values are Group, ServicePrincipal and User. Changing this forces a new resource to be created. | <pre>map(object({<br/>    tenant_id      = string<br/>    object_id      = string<br/>    principal_name = string<br/>    principal_type = string<br/>  }))</pre> | `{}` |
| <a name="input_administrator_login"></a> [administrator\_login](#input\_administrator\_login) | (Optional) The Administrator login for the PostgreSQL Flexible Server. Required when `create_mode` is `Default` and `authentication.password_auth_enabled` is `true`. | `string` | `null` |
| <a name="input_administrator_password"></a> [administrator\_password](#input\_administrator\_password) | (Optional) The Password associated with the `administrator_login` for the PostgreSQL Flexible Server. Required when `create_mode` is `Default` and `authentication.password_auth_enabled` is `true`. | `string` | `null` |
| <a name="input_administrator_password_wo"></a> [administrator\_password\_wo](#input\_administrator\_password\_wo) | (Optional) The Password associated with the administrator\_login for the PostgreSQL Flexible Server. This can be used to avoid storing the password in state. | `string` | `null` |
| <a name="input_administrator_password_wo_version"></a> [administrator\_password\_wo\_version](#input\_administrator\_password\_wo\_version) | (Optional) An integer value used to trigger an update for `administrator_password_wo`. This property should be incremented when updating `administrator_password_wo`. | `string` | `null` |
| <a name="input_authentication"></a> [authentication](#input\_authentication) | - `active_directory_auth_enabled` - (Optional)  Whether or not Active Directory authentication is allowed to access the PostgreSQL Flexible Server. Defaults to `false`.<br/>- `password_auth_enabled` - (Optional) Whether or not password authentication is allowed to access the PostgreSQL Flexible Server. Defaults to `true`.<br/>- `tenant_id` - (Optional) The Tenant ID of the Azure Active Directory which is used by the Active Directory authentication. `active_directory_auth_enabled` must be set to `true`. | <pre>object({<br/>    active_directory_auth_enabled = optional(bool)<br/>    password_auth_enabled         = optional(bool)<br/>    tenant_id                     = optional(string)<br/>  })</pre> | `null` |
| <a name="input_auto_grow_enabled"></a> [auto\_grow\_enabled](#input\_auto\_grow\_enabled) | (Optional) Is the storage auto grow for PostgreSQL Flexible Server enabled? Defaults to `false`. | `bool` | `null` |
| <a name="input_backup_retention_days"></a> [backup\_retention\_days](#input\_backup\_retention\_days) | (Optional) The backup retention days for the PostgreSQL Flexible Server. Possible values are between `7` and `35` days. | `number` | `null` |
| <a name="input_create_mode"></a> [create\_mode](#input\_create\_mode) | (Optional) The creation mode which can be used to restore or replicate existing servers. Possible values are `Default`, `GeoRestore`, `PointInTimeRestore`, `Replica` and `Update`. | `string` | `null` |
| <a name="input_customer_managed_key"></a> [customer\_managed\_key](#input\_customer\_managed\_key) | A map describing customer-managed keys to associate with the resource. This includes the following properties:<br/>- `key_vault_key_id` - (Required) The ID of the Key Vault Key..<br/>- `geo_backup_key_vault_key_id` - (Optional) The ID of the geo backup Key Vault Key<br/>- `geo_backup_user_assigned_identity_id` - (Optional) The geo backup user managed identity id for a Customer Managed Key. Should be added with identity\_ids<br/>- `primary_user_assigned_identity` - (Optional) Specifies the primary user managed identity id for a Customer Managed Key. Should be added with identity\_ids | <pre>object({<br/>    key_vault_key_id                     = string<br/>    geo_backup_key_vault_key_id          = optional(string)<br/>    geo_backup_user_assigned_identity_id = optional(string)<br/>    primary_user_assigned_identity_id    = optional(string)<br/>  })</pre> | `null` |
| <a name="input_databases"></a> [databases](#input\_databases) | A map of PostgreSQL databases to create via the `database` submodule.<br/><br/> - `name` - (Required) Specifies the name of the PostgreSQL Database, which needs [to be a valid PostgreSQL identifier](https://www.postgresql.org/docs/current/static/sql-syntax-lexical.html#SQL-SYNTAX-IDENTIFIERS). Changing this forces a new resource to be created.<br/> - `charset` - (Optional)  Specifies the Charset for the PostgreSQL Database, which needs [to be a valid PostgreSQL Charset](https://www.postgresql.org/docs/current/static/multibyte.html). Changing this forces a new resource to be created.<br/> - `collation` - (Optional) Specifies the Collation for the PostgreSQL Database, which needs [to be a valid PostgreSQL Collation](https://www.postgresql.org/docs/current/static/collation.html). Note that Microsoft uses different [notation](https://msdn.microsoft.com/library/windows/desktop/dd373814.aspx)<br/><br/><br/> ---<br/> `timeouts` block supports the following:<br/> - `create` - (Defaults to 60 minutes) Used when creating the PostgreSQL Database.<br/> - `delete` - (Defaults to 60 minutes) Used when deleting the PostgreSQL Database.<br/> - `read` - (Defaults to 5 minutes) Used when retrieving the PostgreSQL Database. | <pre>map(object({<br/>    name      = string<br/>    charset   = optional(string)<br/>    collation = optional(string)<br/>    timeouts = optional(object({<br/>      create = optional(string)<br/>      delete = optional(string)<br/>      read   = optional(string)<br/>    }))<br/>  }))</pre> | `{}` |
| <a name="input_delegated_subnet_id"></a> [delegated\_subnet\_id](#input\_delegated\_subnet\_id) | (Optional) The ID of the virtual network subnet to create the PostgreSQL Flexible Server. The provided subnet should not have any other resource deployed in it and this subnet will be delegated to the PostgreSQL Flexible Server, if not already delegated. Changing this forces a new PostgreSQL Flexible Server to be created. | `string` | `null` |
| <a name="input_diagnostic_settings"></a> [diagnostic\_settings](#input\_diagnostic\_settings) | A map of diagnostic settings to create on the ddos protection plan. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/><br/>- `name` - (Optional) The name of the diagnostic setting. One will be generated if not set, however this will not be unique if you want to create multiple diagnostic setting resources.<br/>- `log_categories` - (Optional) A set of log categories to send to the log analytics workspace. Defaults to `[]`.<br/>- `log_groups` - (Optional) A set of log groups to send to the log analytics workspace. Defaults to `["allLogs"]`.<br/>- `metric_categories` - (Optional) A set of metric categories to send to the log analytics workspace. Defaults to `["AllMetrics"]`.<br/>- `log_analytics_destination_type` - (Optional) The destination type for the diagnostic setting. Possible values are `Dedicated` and `AzureDiagnostics`. Defaults to `Dedicated`.<br/>- `workspace_resource_id` - (Optional) The resource ID of the log analytics workspace to send logs and metrics to.<br/>- `storage_account_resource_id` - (Optional) The resource ID of the storage account to send logs and metrics to.<br/>- `event_hub_authorization_rule_resource_id` - (Optional) The resource ID of the event hub authorization rule to send logs and metrics to.<br/>- `event_hub_name` - (Optional) The name of the event hub. If none is specified, the default event hub will be selected.<br/>- `marketplace_partner_resource_id` - (Optional) The full ARM resource ID of the Marketplace resource to which you would like to send Diagnostic LogsLogs. | <pre>map(object({<br/>    name                                     = optional(string, null)<br/>    log_categories                           = optional(set(string), [])<br/>    log_groups                               = optional(set(string), ["allLogs"])<br/>    metric_categories                        = optional(set(string), ["AllMetrics"])<br/>    log_analytics_destination_type           = optional(string, "Dedicated")<br/>    workspace_resource_id                    = optional(string, null)<br/>    storage_account_resource_id              = optional(string, null)<br/>    event_hub_authorization_rule_resource_id = optional(string, null)<br/>    event_hub_name                           = optional(string, null)<br/>    marketplace_partner_resource_id          = optional(string, null)<br/>  }))</pre> | `{}` |
| <a name="input_firewall_rules"></a> [firewall\_rules](#input\_firewall\_rules) | - `name` - (Optional) The name which should be used for this PostgreSQL Flexible Server Firewall Rule.<br/>- `start_ip_address` - (Optional) The Start IP Address associated with this PostgreSQL Flexible Server Firewall Rule.<br/>- `end_ip_address` - (Optional) The End IP Address associated with this PostgreSQL Flexible Server Firewall Rule. <br/><br/>`eg.`<br/>  firewall\_rules = {<br/>   rule1 = {<br/>     name             = "AllowAllFireWallRule"<br/>     start\_ip\_address = "0.0.0.0"<br/>     end\_ip\_address   = "255.255.255.255"<br/>   }<br/> } | <pre>map(object({<br/>    name             = optional(string)<br/>    start_ip_address = optional(string)<br/>    end_ip_address   = optional(string)<br/>  }))</pre> | `{}` |
| <a name="input_geo_redundant_backup_enabled"></a> [geo\_redundant\_backup\_enabled](#input\_geo\_redundant\_backup\_enabled) | (Optional) Is Geo-Redundant backup enabled on the PostgreSQL Flexible Server. Defaults to `false`. Changing this forces a new PostgreSQL Flexible Server to be created. | `bool` | `null` |
| <a name="input_high_availability"></a> [high\_availability](#input\_high\_availability) | - `mode` - (Required) The high availability mode for the PostgreSQL Flexible Server. Possible value are `SameZone` or `ZoneRedundant`.<br/>- `standby_availability_zone` - (Optional) Specifies the Availability Zone in which the standby Flexible Server should be located. Drift on this field is ignored after deployment to accommodate Azure-assigned values and failover events.<br/><br/>> Note: High availability is not supported for all regions and SKUs. Burstable SKUs (those with the `B_` prefix, e.g. `B_Standard_B1ms`) do not support high availability. Set this variable to `null` to deploy without high availability. | <pre>object({<br/>    mode                      = string<br/>    standby_availability_zone = optional(string)<br/>  })</pre> | <pre>{<br/>  "mode": "ZoneRedundant"<br/>}</pre> |
| <a name="input_location"></a> [location](#input\_location) | Azure region where the resource group will be created | `string` | `"eastus2"` |
| <a name="input_lock"></a> [lock](#input\_lock) | Controls the Resource Lock configuration for this resource. The following properties can be specified:<br/><br/>  - `kind` - (Required) The type of lock. Possible values are `\"CanNotDelete\"` and `\"ReadOnly\"`.<br/>  - `name` - (Optional) The name of the lock. If not specified, a name will be generated based on the `kind` value. Changing this forces the creation of a new resource. | <pre>object({<br/>    kind = string<br/>    name = optional(string, null)<br/>  })</pre> | `null` |
| <a name="input_maintenance_window"></a> [maintenance\_window](#input\_maintenance\_window) | - `day_of_week` - (Optional) The day of week for maintenance window, where the week starts on a Sunday, i.e. Sunday = `0`, Monday = `1`. Defaults to `0`.<br/>- `start_hour` - (Optional) The start hour for maintenance window. Defaults to `0`.<br/>- `start_minute` - (Optional) The start minute for maintenance window. Defaults to `0`. | <pre>object({<br/>    day_of_week  = optional(string)<br/>    start_hour   = optional(number)<br/>    start_minute = optional(number)<br/>  })</pre> | <pre>{<br/>  "day_of_week": "0",<br/>  "start_hour": 0,<br/>  "start_minute": 0<br/>}</pre> |
| <a name="input_managed_identities"></a> [managed\_identities](#input\_managed\_identities) | Controls the Managed Identity configuration on this resource. The following properties can be specified:<br/><br/>  - `system_assigned` - (Optional) Specifies if the System Assigned Managed Identity should be enabled.<br/>  - `user_assigned_resource_ids` - (Optional) Specifies a list of User Assigned Managed Identity resource IDs to be assigned to this resource. | <pre>object({<br/>    system_assigned            = optional(bool, false)<br/>    user_assigned_resource_ids = optional(set(string), [])<br/>  })</pre> | `{}` |
| <a name="input_name"></a> [name](#input\_name) | Name of the postgresql server | `string` | `null` |
| <a name="input_point_in_time_restore_time_in_utc"></a> [point\_in\_time\_restore\_time\_in\_utc](#input\_point\_in\_time\_restore\_time\_in\_utc) | (Optional) The point in time to restore from `source_server_id` when `create_mode` is `GeoRestore`, `PointInTimeRestore`. Changing this forces a new PostgreSQL Flexible Server to be created. | `string` | `null` |
| <a name="input_private_dns_zone_id"></a> [private\_dns\_zone\_id](#input\_private\_dns\_zone\_id) | (Optional) The ID of the private DNS zone to create the PostgreSQL Flexible Server. | `string` | `null` |
| <a name="input_private_endpoints"></a> [private\_endpoints](#input\_private\_endpoints) | A map of private endpoints to create on this resource. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/><br/>- `name` - (Optional) The name of the private endpoint. One will be generated if not set.<br/>- `role_assignments` - (Optional) A map of role assignments to create on the private endpoint. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time. See `var.role_assignments` for more information.<br/>- `lock` - (Optional) The lock level to apply to the private endpoint. Default is `None`. Possible values are `None`, `CanNotDelete`, and `ReadOnly`.<br/>- `tags` - (Optional) A mapping of tags to assign to the private endpoint.<br/>- `subnet_resource_id` - The resource ID of the subnet to deploy the private endpoint in.<br/>- `private_dns_zone_group_name` - (Optional) The name of the private DNS zone group. One will be generated if not set.<br/>- `private_dns_zone_resource_ids` - (Optional) A set of resource IDs of private DNS zones to associate with the private endpoint. If not set, no zone groups will be created and the private endpoint will not be associated with any private DNS zones. DNS records must be managed external to this module.<br/>- `application_security_group_resource_ids` - (Optional) A map of resource IDs of application security groups to associate with the private endpoint. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/>- `private_service_connection_name` - (Optional) The name of the private service connection. One will be generated if not set.<br/>- `network_interface_name` - (Optional) The name of the network interface. One will be generated if not set.<br/>- `location` - (Optional) The Azure location where the resources will be deployed. Defaults to the location of the resource group.<br/>- `resource_group_name` - (Optional) The resource group where the resources will be deployed. Defaults to the resource group of this resource.<br/>- `ip_configurations` - (Optional) A map of IP configurations to create on the private endpoint. If not specified the platform will create one. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/>  - `name` - The name of the IP configuration.<br/>  - `private_ip_address` - The private IP address of the IP configuration. | <pre>map(object({<br/>    name = optional(string, null)<br/>    role_assignments = optional(map(object({<br/>      role_definition_id_or_name             = string<br/>      principal_id                           = string<br/>      description                            = optional(string, null)<br/>      skip_service_principal_aad_check       = optional(bool, false)<br/>      condition                              = optional(string, null)<br/>      condition_version                      = optional(string, null)<br/>      delegated_managed_identity_resource_id = optional(string, null)<br/>      principal_type                         = optional(string, null)<br/>    })), {})<br/>    lock = optional(object({<br/>      kind = string<br/>      name = optional(string, null)<br/>    }), null)<br/>    tags                                    = optional(map(string), null)<br/>    subnet_resource_id                      = string<br/>    subresource_name                        = optional(string, "postgresqlServer") # By default, postgresqlServer is declared in the PE resource<br/>    private_dns_zone_group_name             = optional(string, "default")<br/>    private_dns_zone_resource_ids           = optional(set(string), [])<br/>    application_security_group_associations = optional(map(string), {})<br/>    private_service_connection_name         = optional(string, null)<br/>    network_interface_name                  = optional(string, null)<br/>    location                                = optional(string, null)<br/>    resource_group_name                     = optional(string, null)<br/>    ip_configurations = optional(map(object({<br/>      name               = string<br/>      private_ip_address = string<br/>    })), {})<br/>  }))</pre> | `{}` |
| <a name="input_private_endpoints_manage_dns_zone_group"></a> [private\_endpoints\_manage\_dns\_zone\_group](#input\_private\_endpoints\_manage\_dns\_zone\_group) | Whether to manage private DNS zone groups with this module. If set to false, you must manage private DNS zone groups externally, e.g. using Azure Policy. | `bool` | `true` |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | (Optional) Whether the server is publicly accessible.  Defaults to `false`. | `bool` | `false` |
| <a name="input_replication_role"></a> [replication\_role](#input\_replication\_role) | (Optional) The replication role for the PostgreSQL Flexible Server. Possible value is `None`. | `string` | `null` |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group where resources will be created | `string` | n/a |
| <a name="input_role_assignments"></a> [role\_assignments](#input\_role\_assignments) | A map of role assignments to create on the <RESOURCE>. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/><br/>  - `role_definition_id_or_name` - The ID or name of the role definition to assign to the principal.<br/>  - `principal_id` - The ID of the principal to assign the role to.<br/>  - `description` - (Optional) The description of the role assignment.<br/>  - `skip_service_principal_aad_check` - (Optional) If set to true, skips the Azure Active Directory check for the service principal in the tenant. Defaults to false.<br/>  - `condition` - (Optional) The condition which will be used to scope the role assignment.<br/>  - `condition_version` - (Optional) The version of the condition syntax. Leave as `null` if you are not using a condition, if you are then valid values are '2.0'.<br/>  - `delegated_managed_identity_resource_id` - (Optional) The delegated Azure Resource Id which contains a Managed Identity. Changing this forces a new resource to be created. This field is only used in cross-tenant scenario.<br/>  - `principal_type` - (Optional) The type of the `principal_id`. Possible values are `User`, `Group` and `ServicePrincipal`. It is necessary to explicitly set this attribute when creating role assignments if the principal creating the assignment is constrained by ABAC rules that filters on the PrincipalType attribute.<br/><br/>  > Note: only set `skip_service_principal_aad_check` to true if you are assigning a role to a service principal. | <pre>map(object({<br/>    role_definition_id_or_name             = string<br/>    principal_id                           = string<br/>    scope                                  = string<br/>    description                            = optional(string, null)<br/>    skip_service_principal_aad_check       = optional(bool, false)<br/>    condition                              = optional(string, null)<br/>    condition_version                      = optional(string, null)<br/>    delegated_managed_identity_resource_id = optional(string, null)<br/>    principal_type                         = optional(string, null)<br/>  }))</pre> | `{}` |
| <a name="input_server_configuration"></a> [server\_configuration](#input\_server\_configuration) | A map to set a PostgreSQL Configuration value on a Azure PostgreSQL Flexible Server.<br/><br/>- `name` - Specifies the name of the PostgreSQL Configuration, which needs to be a valid PostgreSQL configuration name. Changing this forces a new resource to be created.<br/>- `config` - Specifies the value of the PostgreSQL Configuration. See the PostgreSQL documentation for valid values. | <pre>map(object({<br/>    name   = string<br/>    config = string<br/>  }))</pre> | `{}` |
| <a name="input_server_version"></a> [server\_version](#input\_server\_version) | (Optional) The version of PostgreSQL Flexible Server to use. Possible values are `11`,`12`, `13`, `14`, `15`, `16`, `17`, and `18`. Required when `create_mode` is `Default`. | `string` | `null` |
| <a name="input_sku_name"></a> [sku\_name](#input\_sku\_name) | (Optional) The SKU Name for the PostgreSQL Flexible Server. The name of the SKU, follows the `tier` + `name` pattern (e.g. `B_Standard_B1ms`, `GP_Standard_D2s_v3`, `MO_Standard_E4s_v3`). Note: High availability is not supported for Burstable SKUs (those with the `B_` prefix). When using a Burstable SKU, set `high_availability` to `null`. | `string` | `null` |
| <a name="input_source_server_id"></a> [source\_server\_id](#input\_source\_server\_id) | (Optional) The resource ID of the source PostgreSQL Flexible Server to be restored. Required when `create_mode` is `GeoRestore`, `PointInTimeRestore` or `Replica`. Changing this forces a new PostgreSQL Flexible Server to be created. | `string` | `null` |
| <a name="input_storage_mb"></a> [storage\_mb](#input\_storage\_mb) | (Optional) The max storage allowed for the PostgreSQL Flexible Server. Possible values are `32768`, `65536`, `131072`, `262144`, `524288`, `1048576`, `2097152`, `4193280`, `4194304`, `8388608`, `16777216` and `33553408`. | `number` | `null` |
| <a name="input_storage_tier"></a> [storage\_tier](#input\_storage\_tier) | (Optional) The storage tier for the PostgreSQL Flexible Server. Possible values are `P4`, `P6`, `P10`, `P15`, `P20`, `P30`, `P40`, `P50`, `P60`, `P70` or `P80`. | `string` | `null` |
| <a name="input_tags"></a> [tags](#input\_tags) | Map of tags to be applied to all resources | `map(string)` | <pre>{<br/>  "business_unit": "banking",<br/>  "customer": "myridius",<br/>  "environment": "dev",<br/>  "owner": "devops",<br/>  "product": "gh",<br/>  "region": "eastus2"<br/>}</pre> |
| <a name="input_timeouts"></a> [timeouts](#input\_timeouts) | - `create` - (Defaults to 1 hour) Used when creating the PostgreSQL Flexible Server.<br/>- `delete` - (Defaults to 1 hour) Used when deleting the PostgreSQL Flexible Server.<br/>- `read` - (Defaults to 5 minutes) Used when retrieving the PostgreSQL Flexible Server.<br/>- `update` - (Defaults to 1 hour) Used when updating the PostgreSQL Flexible Server. | <pre>object({<br/>    create = optional(string)<br/>    delete = optional(string)<br/>    read   = optional(string)<br/>    update = optional(string)<br/>  })</pre> | `null` |
| <a name="input_user_preferred_index"></a> [user\_preferred\_index](#input\_user\_preferred\_index) | A value to append at the end of the name | `number` | `1` |
| <a name="input_virtual_endpoint"></a> [virtual\_endpoint](#input\_virtual\_endpoint) | A map to allow you to create a Virtual Endpoint associated with a Postgres Flexible Replica.<br/><br/>- `name` - (Required) The name of the Virtual Endpoint.<br/>- `replica_server_id` - (Required) The Resource ID of the Replica Postgres Flexible Server this should be associated with.<br/>- `type` - (Required) The type of Virtual Endpoint. Currently only ReadWrite is supported. | <pre>map(object({<br/>    name              = string<br/>    replica_server_id = string<br/>    type              = string<br/>  }))</pre> | `{}` |
| <a name="input_zone"></a> [zone](#input\_zone) | (Optional) Specifies the Availability Zone in which the PostgreSQL Flexible Server should be located. Drift on this field is ignored after deployment to accommodate Azure-assigned values and failover events. | `string` | `null` |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_postgresql_server_database_name"></a> [postgresql\_server\_database\_name](#output\_postgresql\_server\_database\_name) | A map of database keys to database name. |
| <a name="output_postgresql_server_database_resource_ids"></a> [postgresql\_server\_database\_resource\_ids](#output\_postgresql\_server\_database\_resource\_ids) | A map of database keys to resource ids. |
| <a name="output_postgresql_server_fqdn"></a> [postgresql\_server\_fqdn](#output\_postgresql\_server\_fqdn) | The fully qualified domain name of the PostgreSQL Flexible Server. |
| <a name="output_postgresql_server_name"></a> [postgresql\_server\_name](#output\_postgresql\_server\_name) | The resource ID for the resource. |
| <a name="output_postgresql_server_private_endpoints"></a> [postgresql\_server\_private\_endpoints](#output\_postgresql\_server\_private\_endpoints) | A map of the private endpoints created. |
| <a name="output_postgresql_server_resource_id"></a> [postgresql\_server\_resource\_id](#output\_postgresql\_server\_resource\_id) | The resource ID for the resource. |

# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v1.0.0] - 2026-06-29
### Added
- Initial release of the module to create:
  - Azure PostgreSQL Flexible Server with configurable SKU, version, storage, backup retention, and availability zone placement
  - High availability with `ZoneRedundant` or `SameZone` modes and standby provisioning
  - Password-based and Azure Active Directory authentication, including ephemeral password support to avoid state exposure
  - Active Directory administrator assignment for EntraID-based access control
  - Customer-managed keys (CMK) integration via Azure Key Vault, including geo-backup key support
  - System-assigned and user-assigned managed identity support
  - Private Endpoint for secure, private network access to the PostgreSQL server
  - Private DNS zone integration for name resolution of private endpoints
  - Firewall rules for IP-based access control
  - Virtual endpoints for read/write routing across primary and replica servers
  - Server configuration parameters for PostgreSQL engine tuning
  - Azure Monitor diagnostic settings with support for Log Analytics, Event Hub, and Storage
  - Role assignments (RBAC) for fine-grained access control on the server and private endpoints
  - Optional resource-level lock for protection of critical environments
  - Maintenance window configuration for controlled update scheduling
  - Geo-redundant backup with configurable retention (7–35 days)
  - Storage auto-grow support

<!-- END_TF_DOCS -->