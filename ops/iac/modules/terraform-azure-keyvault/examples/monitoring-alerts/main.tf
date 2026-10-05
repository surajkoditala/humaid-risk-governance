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
