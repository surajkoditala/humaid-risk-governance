###NOTE: This example is when we don't have app insights and log analytics workspace are already created.
###In our environment we have log analytics workspace (app insights with workspace mode enabled) and we want to use the same shared workspace for logs destination.

module "container_app_env" {
  source = "../../"

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

  create_log_analytics_workspace = true
}