# Virtual Network full object
output "vnet" {
  description = "The full Azure Virtual Network resource"
  value       = module.vnet.vnet
}

# Virtual Network ID
output "vnet_id" {
  description = "The ID of the Azure Virtual Network"
  value       = module.vnet.vnet_id
}

# Virtual Network name
output "vnet_name" {
  description = "The name of the Azure Virtual Network"
  value       = module.vnet.vnet_name
}

# Subnet map
output "subnets" {
  description = "Map of subnets created in the VNet"
  value       = module.vnet.subnets
}

# Subnet IDs
output "subnet_ids" {
  description = "Map of subnet names to their IDs"
  value       = module.vnet.subnet_ids
}

# NSGs created
output "network_security_groups" {
  description = "Map of Network Security Group resources"
  value       = module.vnet.network_security_groups
}

# NSG IDs
output "nsg_ids" {
  description = "Map of NSG names to their IDs"
  value       = module.vnet.nsg_ids
}

# Route Tables created
output "route_tables" {
  description = "Map of route table resources"
  value       = module.vnet.route_tables
}

# Route Table IDs
output "route_table_ids" {
  description = "Map of route table names to their IDs"
  value       = module.vnet.route_table_ids
}