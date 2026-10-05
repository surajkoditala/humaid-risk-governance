# Generate the password EPHEMERALLY (NEVER persisted to state)
# Each plan/apply will generate a new string but wo_version of KV and pgsql manages the rotation of the password.
# For this to work where you need to write ephemeral result to KV, need to handle network access (for eg. if it's from TFC, need to use agent or else go with resource random_password and remove KV writing step)
ephemeral "random_password" "this" {
  length           = 10
  special          = true
  override_special = "!$?"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

# Retrieving Tenant id details for the key vault.
data "azurerm_client_config" "this" {}

# Assigning KV secrets permission to TFC service principal to store the secrets
resource "azurerm_role_assignment" "tfc_kv_secrets_officer" {
  scope                = module.keyvault.key_vault_resource_id
  role_definition_name = "Key Vault Secrets Officer" # Access to write secrets
  principal_id         = data.azurerm_client_config.this.object_id
}

# KV to store the secret - Will use the centralized KV resource in the environment; Creating this separately for testing
module "keyvault" {
  source  = "app.terraform.io/Myridius-Insurity-ERC/keyvault/azure" # In reality, this will be like "app.terraform.io/<tfc-org-name>/<registry-name>/azure"; version = "<version>"
  version = "1.0.0"

  location            = "eastus2"
  resource_group_name = "rg-gh-dev-sandbox"
  tags = { # keyvault module is sourced from the TFC registry (not yet migrated locally) -- still needs the old ct_ tag schema
    "ct_insurity_product" = "erc"
    "ct_environment"      = "dev-sandbox"
    "ct_customer"         = "erc-client"
    "ct_business_unit"    = "insurity-product"
    "ct_owner"            = "devops"
    "ct_region"           = "eastus2"
  }
  tenant_id = data.azurerm_client_config.this.tenant_id

  network_acls = {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = ["157.66.143.200/32", "210.14.21.200/32", "208.195.3.201/32", "99.2.116.74"]                                                                                                                                                                                                                                                                                                     #Need to add the IP from where the apply and execution is happening for the access to KV data plane.                                                                                                                                                                                                                                                                                                       #Company VPNs                                                                                                                                                                                                                                                                                                                  #VPN IPs
    virtual_network_subnet_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-cae-dev-sandbox-01", "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01"] #Subnets of the resources from which access is needed
  }

  # private end point creation
  private_endpoints = {
    kv_pe = {
      subnet_resource_id            = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01" #PEP subnet ID
      private_dns_zone_resource_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev01/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"]                         #Shared RG default KV dns zone
    }
  }

}

# Store it in Key Vault using a write-only attribute
resource "azurerm_key_vault_secret" "this" {
  name             = "cloudpostgresqlghadmin-password"
  key_vault_id     = module.keyvault.key_vault_resource_id
  value_wo         = ephemeral.random_password.this.result
  value_wo_version = 1 # To change the password, bump this number

  depends_on = [azurerm_role_assignment.tfc_kv_secrets_officer]
}

# Read the password back from Key Vault — guarantees a single source of truth
ephemeral "azurerm_key_vault_secret" "this" {
  name         = azurerm_key_vault_secret.this.name
  key_vault_id = module.keyvault.key_vault_resource_id
}

# Postgresql server
module "pgsql" {
  source = "../../"

  location                          = "eastus2"
  resource_group_name               = "rg-gh-dev-sandbox"
  administrator_login               = "cloudpostgresqlghadmin"
  administrator_password_wo         = ephemeral.azurerm_key_vault_secret.this.value
  administrator_password_wo_version = azurerm_key_vault_secret.this.value_wo_version
  authentication = {
    active_directory_auth_enabled = true
    password_auth_enabled         = true
    tenant_id                     = "7aa4356e-1227-4975-bb58-165bff68ff0a" #data.azurerm_client_config.this.tenant_id
  }
  #   geo_redundant_backup_enabled = true
  high_availability = null #For B_ prefix skus, high availability is not supported
  #   high_availability = {
  #     mode                      = "ZoneRedundant"
  #     standby_availability_zone = 2
  #   }
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
  #   zone           = 1

  ad_administrator = {
    admin1 = {
      tenant_id      = "7aa4356e-1227-4975-bb58-165bff68ff0a" #data.azurerm_client_config.this.tenant_id
      object_id      = "b5b38394-a156-4df0-a7c4-441bed5e48a8" #suraj
      principal_name = "Suraj.Koditala@myridius.com"
      principal_type = "User"
    }
  }

  firewall_rules = {
    firewall-rule-US-VPN-IP = {
      name             = "firewall-rule-US-VPN-IP"
      start_ip_address = "99.2.116.74"
      end_ip_address   = "99.2.116.74"
    }
  }
}