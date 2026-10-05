

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