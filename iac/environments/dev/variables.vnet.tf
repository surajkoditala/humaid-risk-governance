# VNet Variables
variable "address_space" {
  description = "Address space for the Virtual Network"
  type        = list(string)
  default     = ["10.12.0.0/16"]
}

variable "subnets" {
  description = "List of subnet definitions"
  type = list(object({
    name              = string
    address_prefixes  = list(string)
    service_endpoints = optional(list(string))
    delegation = optional(object({
      name = string
      service_delegation = object({
        name    = string
        actions = optional(list(string), [])
      })
    }))
  }))
  default = []
}

variable "network_security_groups" {
  description = "List of NSGs and their rules"
  type = list(object({
    name = string
    security_rules = list(object({
      name                       = string
      priority                   = number
      direction                  = string
      access                     = string
      protocol                   = string
      source_port_range          = optional(string)
      destination_port_range     = optional(string)
      source_address_prefix      = optional(string)
      destination_address_prefix = optional(string)

      source_port_ranges           = optional(list(string)) # List of source port ranges - Required if source_port_range is not specified
      destination_port_ranges      = optional(list(string)) # List of destination port ranges - Required if destination_port_range is not specified
      source_address_prefixes      = optional(list(string)) # List of source address prefixes - Required if source_address_prefix is not specified
      destination_address_prefixes = optional(list(string)) # List of destination address prefixes - Required if destination_address_prefix is not specified
    }))
  }))
  default = []
}

variable "subnet_nsg_map" {
  description = "Map of subnet name to NSG name for association"
  type        = map(string)
  default     = {}
}

variable "route_tables" {
  description = "Map of route table keys to their definitions"
  type = map(object({
    name = string
    routes = list(object({
      name                   = optional(string)
      address_prefix         = optional(string)
      next_hop_type          = optional(string)
      next_hop_in_ip_address = optional(string)
    }))
  }))
  default = {}
}

variable "subnet_route_table_map" {
  description = "Map of subnet name to RT names for association"
  type        = map(string)
  default     = {}
}