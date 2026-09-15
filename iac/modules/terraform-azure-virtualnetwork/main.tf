# Create Azure VNet
resource "azurerm_virtual_network" "vnet" {
  address_space       = var.address_space
  location            = var.location
  name                = var.name != null ? var.name : "vnet-${var.tags.product}-${var.tags.environment}"
  resource_group_name = var.resource_group_name
  tags                = merge(local.default_tags, var.tags)

  dynamic "ddos_protection_plan" {
    for_each = var.ddos_protection_plan != null ? [var.ddos_protection_plan] : []

    content {
      enable = ddos_protection_plan.value.enable
      id     = ddos_protection_plan.value.id
    }
  }

}

# DNS servers associated with a virtual network
resource "azurerm_virtual_network_dns_servers" "dns_servers" {
  count = length(var.dns_servers) > 0 ? 1 : 0

  virtual_network_id = azurerm_virtual_network.vnet.id
  dns_servers        = var.dns_servers
}

# Create subnets under the Virtual Network, with optional delegation
resource "azurerm_subnet" "subnet" {
  for_each = { for s in var.subnets : s.name => s }

  name                 = each.value.name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = each.value.address_prefixes
  service_endpoints    = try(each.value.service_endpoints, null)

  dynamic "delegation" {
    for_each = try(each.value.delegation != null, false) ? [1] : []
    content {
      name = each.value.delegation.name
      service_delegation {
        name    = each.value.delegation.service_delegation.name
        actions = try(each.value.delegation.service_delegation.actions, null)
      }
    }
  }
}

# Create Network Security Groups (NSGs) with security rules
resource "azurerm_network_security_group" "network_security_group" {
  for_each = { for nsg in var.network_security_groups : nsg.name => nsg }

  name                = each.value.name
  location            = var.location
  resource_group_name = var.resource_group_name

  dynamic "security_rule" {
    for_each = each.value.security_rules

    content {
      # Required attributes - assumed always present
      name      = security_rule.value.name
      priority  = security_rule.value.priority
      direction = security_rule.value.direction
      access    = security_rule.value.access
      protocol  = security_rule.value.protocol

      # Optional attributes - to pass null if missing
      source_port_range          = try(security_rule.value.source_port_range, null)
      destination_port_range     = try(security_rule.value.destination_port_range, null)
      source_address_prefix      = try(security_rule.value.source_address_prefix, null)
      destination_address_prefix = try(security_rule.value.destination_address_prefix, null)

      # Optional plural attributes - to pass null if missing
      source_port_ranges           = try(security_rule.value.source_port_ranges, null)           #This is required if source_port_range is not specified
      destination_port_ranges      = try(security_rule.value.destination_port_ranges, null)      #This is required if destination_port_range is not specified
      source_address_prefixes      = try(security_rule.value.source_address_prefixes, null)      #This is required if source_address_prefix is not specified
      destination_address_prefixes = try(security_rule.value.destination_address_prefixes, null) #This is required if destination_address_prefix is not specified
    }
  }

  tags = merge(local.default_tags, var.tags)
}

# Associate NSGs to Subnets
resource "azurerm_subnet_network_security_group_association" "subnet_network_security_group_association" {
  for_each = var.subnet_nsg_map

  subnet_id                 = azurerm_subnet.subnet[each.key].id
  network_security_group_id = azurerm_network_security_group.network_security_group[each.value].id
}

# Create Route Tables with optional routes
resource "azurerm_route_table" "route_table" {
  for_each = var.route_tables

  name                = each.value.name
  location            = var.location
  resource_group_name = var.resource_group_name

  dynamic "route" {
    for_each = each.value.routes
    content {
      name                   = try(route.value.name, null)
      address_prefix         = try(route.value.address_prefix, null)
      next_hop_type          = try(route.value.next_hop_type, null)
      next_hop_in_ip_address = try(route.value.next_hop_in_ip_address, null)
    }
  }

  tags = merge(local.default_tags, var.tags)
}

# Associate subnets to route tables
resource "azurerm_subnet_route_table_association" "subnet_route_table_association" {
  for_each = var.subnet_route_table_map

  subnet_id      = azurerm_subnet.subnet[each.key].id
  route_table_id = azurerm_route_table.route_table[each.value].id
}

# Optional VNet peerings
resource "azurerm_virtual_network_peering" "virtual_network_peering" {
  for_each = var.vnet_peerings

  name                      = each.value.name_local
  resource_group_name       = each.value.rg_local
  virtual_network_name      = each.value.vnet_name_local
  remote_virtual_network_id = each.value.remote_vnet_id

  allow_virtual_network_access = try(each.value.allow_vnet_access, true)
  allow_forwarded_traffic      = try(each.value.allow_forwarded_traffic, true)
  allow_gateway_transit        = try(each.value.allow_gateway_transit, false)
  use_remote_gateways          = try(each.value.use_remote_gateways, false)
}
