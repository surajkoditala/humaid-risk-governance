module "vnet" {
  source = "../../modules/terraform-azure-virtualnetwork"

  location                = var.location #"eastus2"
  resource_group_name     = module.rg.resource_group_name
  address_space           = var.address_space
  subnets                 = var.subnets
  network_security_groups = var.network_security_groups
  subnet_nsg_map          = var.subnet_nsg_map
  route_tables            = var.route_tables
  subnet_route_table_map  = var.subnet_route_table_map

  tags = var.tags
}