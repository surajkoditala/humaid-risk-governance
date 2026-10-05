# Virtual Network full object
output "vnet" {
  description = "The full Azure Virtual Network resource"
  value       = azurerm_virtual_network.vnet
}

# Virtual Network ID
output "vnet_id" {
  description = "The ID of the Azure Virtual Network"
  value       = azurerm_virtual_network.vnet.id
}

# Virtual Network name
output "vnet_name" {
  description = "The name of the Azure Virtual Network"
  value       = azurerm_virtual_network.vnet.name
}

# DNS servers used
output "dns_servers" {
  description = "List of DNS servers configured for the VNet"
  value       = var.dns_servers
}

# Subnet map
output "subnets" {
  description = "Map of subnets created in the VNet"
  value       = azurerm_subnet.subnet
}

# Subnet IDs
output "subnet_ids" {
  description = "Map of subnet names to their IDs"
  value       = { for name, s in azurerm_subnet.subnet : name => s.id }
}

# NSGs created
output "network_security_groups" {
  description = "Map of Network Security Group resources"
  value       = azurerm_network_security_group.network_security_group
}

# NSG IDs
output "nsg_ids" {
  description = "Map of NSG names to their IDs"
  value       = { for name, nsg in azurerm_network_security_group.network_security_group : name => nsg.id }
}

# Route Tables created
output "route_tables" {
  description = "Map of route table resources"
  value       = azurerm_route_table.route_table
}

# Route Table IDs
output "route_table_ids" {
  description = "Map of route table names to their IDs"
  value       = { for name, rt in azurerm_route_table.route_table : name => rt.id }
}
