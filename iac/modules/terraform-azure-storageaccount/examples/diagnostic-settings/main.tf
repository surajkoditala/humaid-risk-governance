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