

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
}