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