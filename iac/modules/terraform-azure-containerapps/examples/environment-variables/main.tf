#CAE
module "container_app_env" {
  source = "../../../terraform-azure-containerappsenvironment"

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

#ACR
resource "azurerm_private_dns_zone" "this" {
  name                = "privatelink.azurecr.io"
  resource_group_name = "rg-gh-dev-sandbox"
}

resource "azurerm_private_dns_zone_virtual_network_link" "example" {
  name                  = "dns-zone-vnet-link"
  resource_group_name   = "rg-gh-dev-sandbox"
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox"
}

module "containerregistry" {
  source = "../../../terraform-azure-containerregistry"

  location                      = "eastus2"
  resource_group_name           = "rg-gh-dev-sandbox"
  public_network_access_enabled = true
  private_endpoints = {
    primary = {
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.this.id]
      subnet_resource_id            = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01" #PEP subnet ID
    }
  }

  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }
}

resource "azurerm_user_assigned_identity" "this" {
  location            = "eastus2"
  name                = "id-acr-gh-dev-sandbox"
  resource_group_name = "rg-gh-dev-sandbox"
}

resource "azurerm_role_assignment" "example_pull" {
  scope                = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452"
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

resource "azurerm_role_assignment" "example_push" {
  scope                = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452"
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

#role assignment for system identity
resource "azurerm_role_assignment" "example_pull_sa" {
  scope                = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452"
  role_definition_name = "AcrPull"
  principal_id         = module.container_app.container_app_system_assigned_identity_principal_id
}

resource "azurerm_role_assignment" "example_push_sa" {
  scope                = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452"
  role_definition_name = "AcrPush"
  principal_id         = module.container_app.container_app_system_assigned_identity_principal_id
}

resource "azurerm_role_assignment" "example_storage_sa" {
  scope                = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.container_app.container_app_system_assigned_identity_principal_id
}

resource "azurerm_role_assignment" "example_contrib_sa" {
  scope                = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452"
  role_definition_name = "Contributor"
  principal_id         = module.container_app.container_app_system_assigned_identity_principal_id
}

#Containerapp
module "container_app" {
  source = "../.."

  # Can be used for Prod resource
  # lock = {
  #   name = "lock-ca-oscarr-dev-sandbox" # optional
  #   kind = "CanNotDelete"
  # }

  container_app_service_name   = "gh-integration"
  container_app_environment_id = module.container_app_env.container_app_environment_id
  resource_group_name          = "rg-gh-dev-sandbox"
  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }

  template = {
    container = [
      {
        name   = "ca-gh-integration-service-dev-sandbox"
        memory = "0.5"
        cpu    = 0.25
        image  = "crghdev01.azurecr.io/hello-dotnet-http:v1"
        env = [
          {
            name  = "PEP-SQL-SERVER"
            value = ""
          },
          {
            name  = "DATABASE-NAME"
            value = ""
          },
          {
            name  = "PEP-KEY-VAULT"
            value = ""
          },
          {
            name  = "PEP-STORAGE-ACCOUNT"
            value = ""
          },
          {
            name  = "AI-INSTRUMENTATION-KEY"
            value = ""
          }
        ]
      }
    ]
  }

  ingress = {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = 8080
    cors = {
      allowed_origins = ["*"]
      allowed_methods = ["*"]
      allowed_headers = ["*"]
      exposed_headers = ["*"]
    }

    traffic_weight = [
      {
        latest_revision = true
        percentage      = 100
      }
    ]
  }

  managed_identities = {
    user_assigned_resource_ids = toset([azurerm_user_assigned_identity.this.id])
  }

  registry = [
    {
      server   = "crghdev01.azurecr.io"
      identity = azurerm_user_assigned_identity.this.id
    }
  ]
}