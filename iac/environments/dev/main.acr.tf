module "acr" {
  source = "../../modules/terraform-azure-containerregistry"

  resource_group_name = module.rg.resource_group_name
  location            = var.location

  sku                           = "Standard"
  admin_enabled                 = false
  public_network_access_enabled = var.public_network_access_enabled
  zone_redundancy_enabled       = false

  # For production, we can add geo-replication for the container registry.
  #   georeplications = [
  #     {
  #       location                = "westus"
  #       zone_redundancy_enabled = false
  #     }
  #   ]

  tags = var.tags
}
