module "storage" {
  source = "../../modules/terraform-azure-storageaccount"

  location            = var.location
  resource_group_name = module.rg.resource_group_name
  tags                = var.tags

  # Public network access
  public_network_access_enabled = var.storage_public_network_access_enabled

  # Blob properties (CORS rules)
  blob_properties = {
    cors_rule = [
      {
        allowed_headers    = ["*"]
        allowed_methods    = ["GET", "OPTIONS"]
        allowed_origins    = var.blob_allowed_origins
        exposed_headers    = ["*"]
        max_age_in_seconds = var.blob_max_age_in_seconds
      }
    ]
  }

  # Network rules
  network_rules = {
    bypass         = ["AzureServices"]
    default_action = "Deny"
    ip_rules       = var.storage_ip_rules
    virtual_network_subnet_ids = [
      module.vnet.subnet_ids["snet-pep-${var.tags.environment}-01"],
      module.vnet.subnet_ids["snet-cae-${var.tags.environment}-01"],
    ]
  }

  # Metrics only (aggregated counts, cheap) -- no request-level logs at the account level.
  diagnostic_settings_storage_account = {
    st_diag_setting = {
      name                           = "st-${var.tags.product}-${var.tags.environment}-diagnostic-setting"
      workspace_resource_id          = module.log_analytics_workspace.log_analytics_workspace_resource_id
      log_analytics_destination_type = "Dedicated"
      metric_categories              = ["Capacity", "Transaction"]
    }
  }

  # audit only -- "allLogs" would log every single blob read/write (document uploads), skip that.
  diagnostic_settings_blob = {
    st_blob_diag_setting = {
      name                           = "st-blob-${var.tags.product}-${var.tags.environment}-diagnostic-setting"
      workspace_resource_id          = module.log_analytics_workspace.log_analytics_workspace_resource_id
      log_analytics_destination_type = "Dedicated"
      log_groups                     = ["audit"]
      metric_categories              = ["Capacity", "Transaction"]
    }
  }

  # Private Endpoints -- referencing the private DNS zone modules already
  # created in main.pdns.tf (not a data lookup -- those zones are managed here)
  private_endpoints = {
    st_pe_blob = {
      name               = "pep-stblob-${var.tags.product}-${var.tags.environment}-01"
      subnet_resource_id = module.vnet.subnet_ids["snet-pep-${var.tags.environment}-01"]
      private_dns_zone_resource_ids = [
        module.private_dns_storage_blob.private_dns_zone_resource_id
      ]
    }
    st_pe_file = {
      name               = "pep-stfile-${var.tags.product}-${var.tags.environment}-01"
      subnet_resource_id = module.vnet.subnet_ids["snet-pep-${var.tags.environment}-01"]
      subresource_name   = "file"
      private_dns_zone_resource_ids = [
        module.private_dns_storage_file.private_dns_zone_resource_id
      ]
    }
    st_pe_queue = {
      name               = "pep-stqueue-${var.tags.product}-${var.tags.environment}-01"
      subnet_resource_id = module.vnet.subnet_ids["snet-pep-${var.tags.environment}-01"]
      subresource_name   = "queue"
      private_dns_zone_resource_ids = [
        module.private_dns_storage_queue.private_dns_zone_resource_id
      ]
    }
    st_pe_table = {
      name               = "pep-sttable-${var.tags.product}-${var.tags.environment}-01"
      subnet_resource_id = module.vnet.subnet_ids["snet-pep-${var.tags.environment}-01"]
      subresource_name   = "table"
      private_dns_zone_resource_ids = [
        module.private_dns_storage_table.private_dns_zone_resource_id
      ]
    }
  }
}