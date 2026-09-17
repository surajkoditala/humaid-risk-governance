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