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