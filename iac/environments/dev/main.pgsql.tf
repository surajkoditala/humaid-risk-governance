# Random password
resource "random_password" "this" {
  length           = 16
  override_special = "!$?"
  special          = true
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

# Postgresql server
module "pgsql" {
  source = "../../modules/terraform-azure-postgresql"

  location               = var.location_cus #"centralus"
  resource_group_name    = module.rg.resource_group_name
  administrator_login    = "cloudpostgresqladmin"
  administrator_password = random_password.this.result
  authentication = {
    active_directory_auth_enabled = true
    password_auth_enabled         = true
    tenant_id                     = data.azurerm_client_config.this.tenant_id
  }
  geo_redundant_backup_enabled = false #Changing this will re-create the server; #For Production workloads, this can be enabled considering an additional cost based on backup storage.
  high_availability            = null  #If needed, use the below block for Production workloads as there is a cost associated to it.
  # high_availability = {
  #     mode                      = "ZoneRedundant" #Possible value are `SameZone` or `ZoneRedundant`.
  #     standby_availability_zone = 2
  #   }
  public_network_access_enabled = var.pgsql_public_network_access_enabled
  sku_name                      = var.sku_name
  server_version                = var.server_version
  storage_mb                    = var.storage_mb
  storage_tier                  = var.storage_tier
  tags                          = var.tags

  databases = {
    gh_hrg_db = {
      name = "gh_hrg_db"
      # charset   = "UTF8"
      # collation = "en_US.utf8"
    }
  }

  ad_administrator = {
    admin1 = {
      tenant_id      = data.azurerm_client_config.this.tenant_id
      object_id      = "9154b57b-036d-4e00-bcdf-b412d4e5d73b"
      principal_name = "Francis.Daray@myridius.com"
      principal_type = "User"
    }
    admin2 = {
      tenant_id      = data.azurerm_client_config.this.tenant_id
      object_id      = "7a749552-c684-4bdb-bdfa-4d913640613d"
      principal_name = "skoditala@gmail.com"
      principal_type = "User"
    }
    admin3 = {
      tenant_id      = data.azurerm_client_config.this.tenant_id
      object_id      = "e2259fdf-187c-4a3f-9a56-950b4743d16c"
      principal_name = "Mohd.Suleman@myridius.com"
      principal_type = "User"
    }
    admin4 = {
      tenant_id      = data.azurerm_client_config.this.tenant_id
      object_id      = "ed8c0213-7dad-490f-9d6d-de96d0e4911c"
      principal_name = "Shanthi.Subramanian@myridius.com"
      principal_type = "User"
    }
    admin5 = {
      tenant_id      = data.azurerm_client_config.this.tenant_id
      object_id      = module.container_app_gh_riskgovernance_ui.container_app_system_assigned_identity_principal_id
      principal_name = "ca-${var.container_app_service_name}-${var.tags.environment}"
      principal_type = "ServicePrincipal"
    }
    admin6 = {
      tenant_id      = data.azurerm_client_config.this.tenant_id
      object_id      = module.container_app_gh_riskgovernance_backend_app.container_app_system_assigned_identity_principal_id
      principal_name = "ca-${var.container_app_backend_app_name}-${var.tags.environment}"
      principal_type = "ServicePrincipal"
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

  #   # Enabling diagnostic settings - cost control
  #   diagnostic_settings = {
  #     pgsql_diag_setting = {
  #       event_hub_authorization_rule_resource_id = module.evhns.eventhub_namespace_authorization_rule_id["evhns-auth-rule"]
  #       workspace_resource_id                    = module.log_analytics_workspace.log_analytics_workspace_resource_id
  #       log_analytics_destination_type           = "Dedicated" # Or "AzureDiagnostics"
  #       log_groups                               = ["allLogs"]
  #       metric_categories                        = ["AllMetrics"]
  #     }
  #   }

  # private end point creation
  private_endpoints = {
    pgsql_pe = {
      # Must match the VNet's region (eastus2), not the postgres server's region
      # (var.location_cus) -- private endpoints live in a subnet and are pinned to
      # that subnet's VNet region regardless of where the target PaaS resource is.
      location           = var.location
      subnet_resource_id = module.vnet.subnet_ids["snet-pep-${var.tags.environment}-01"] #PEP subnet ID

      private_dns_zone_resource_ids = [ #Subscription level postgres dns zone
        module.private_dns_postgres.private_dns_zone_resource_id
      ]
    }
  }
}