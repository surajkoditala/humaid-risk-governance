

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