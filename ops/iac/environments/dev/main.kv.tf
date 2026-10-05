# Need the tenant id for the key vault. Being declared in main.tf
module "keyvault" {
  source = "../../modules/terraform-azure-keyvault"

  location            = var.location #"eastus2"
  resource_group_name = module.rg.resource_group_name
  tenant_id           = data.azurerm_client_config.this.tenant_id
  tags                = var.tags

  network_acls = {
    bypass         = "AzureServices"
    default_action = "Deny"
    ip_rules       = ["208.195.3.201/32", "157.66.143.200/32", "210.14.21.200/32", "99.2.116.74/32"] #VPN IPs
    virtual_network_subnet_ids = [
      module.vnet.subnet_ids["snet-pep-${var.tags.environment}-01"],
      module.vnet.subnet_ids["snet-cae-${var.tags.environment}-01"]
    ]
  }

  diagnostic_settings = {
    kv_diag_setting = {
      name                           = "kv-${var.tags.product}-${var.tags.environment}-diagnostic-setting"
      workspace_resource_id          = module.log_analytics_workspace.log_analytics_workspace_resource_id
      log_analytics_destination_type = "Dedicated"
      log_groups                     = ["audit"] # secret/access events only, not every read
      metric_categories              = ["AllMetrics"]
    }
  }

  private_endpoints = {
    kv_pe = {
      subnet_resource_id = module.vnet.subnet_ids["snet-pep-${var.tags.environment}-01"]
      private_dns_zone_resource_ids = [
        module.private_dns_key_vault.private_dns_zone_resource_id
      ]
    }
  }
}