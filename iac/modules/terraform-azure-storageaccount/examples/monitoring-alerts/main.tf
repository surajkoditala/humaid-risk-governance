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
