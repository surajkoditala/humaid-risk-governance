# Private DNS Zone for PostgreSQL
module "private_dns_postgres" {
  source = "../../modules/terraform-azure-privatednszone"

  resource_group_name = module.rg.resource_group_name
  tags                = var.tags
  domain_name         = "privatelink.postgres.database.azure.com" #domain name of the private dns zone

  vnets_to_link = [
    {
      name = module.vnet.vnet_name
      id   = module.vnet.vnet_id
    }
  ]
}

# Private DNS Zone for Storage Blob
module "private_dns_storage_blob" {
  source = "../../modules/terraform-azure-privatednszone"

  resource_group_name = module.rg.resource_group_name
  tags                = var.tags
  domain_name         = "privatelink.blob.core.windows.net" #domain name of the private dns zone

  vnets_to_link = [
    {
      name = module.vnet.vnet_name
      id   = module.vnet.vnet_id
    }
  ]
}

# Private DNS Zone for Storage File
module "private_dns_storage_file" {
  source = "../../modules/terraform-azure-privatednszone"

  resource_group_name = module.rg.resource_group_name
  tags                = var.tags
  domain_name         = "privatelink.file.core.windows.net" #domain name of the private dns zone

  vnets_to_link = [
    {
      name = module.vnet.vnet_name
      id   = module.vnet.vnet_id
    }
  ]
}

# Private DNS Zone for Storage Table
module "private_dns_storage_table" {
  source = "../../modules/terraform-azure-privatednszone"

  resource_group_name = module.rg.resource_group_name
  tags                = var.tags
  domain_name         = "privatelink.table.core.windows.net" #domain name of the private dns zone

  vnets_to_link = [
    {
      name = module.vnet.vnet_name
      id   = module.vnet.vnet_id
    }
  ]
}

# Private DNS Zone for Storage Queue
module "private_dns_storage_queue" {
  source = "../../modules/terraform-azure-privatednszone"

  resource_group_name = module.rg.resource_group_name
  tags                = var.tags
  domain_name         = "privatelink.queue.core.windows.net" #domain name of the private dns zone

  vnets_to_link = [
    {
      name = module.vnet.vnet_name
      id   = module.vnet.vnet_id
    }
  ]
}

# Private DNS Zone for key vault
module "private_dns_key_vault" {
  source = "../../modules/terraform-azure-privatednszone"

  resource_group_name = module.rg.resource_group_name
  tags                = var.tags
  domain_name         = "privatelink.vaultcore.azure.net" #domain name of the private dns zone

  vnets_to_link = [
    {
      name = module.vnet.vnet_name
      id   = module.vnet.vnet_id
    }
  ]
}