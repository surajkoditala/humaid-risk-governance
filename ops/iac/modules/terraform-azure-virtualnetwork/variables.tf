locals {
  default_tags = {
    managed-by = "terraform"
  }
}

#Common Variables
variable "location" {
  description = "Azure region where the resource group will be created"
  type        = string
  nullable    = false
  default     = "eastus2"
}

variable "name" {
  description = "Name of the virtual network"
  type        = string
  default     = null
}

variable "resource_group_name" {
  description = "Name of the resource group where resources will be created"
  type        = string
}

variable "tags" {
  description = "Map of tags to be applied to all resources"
  type        = map(string)
  default = {
    "business_unit" = "banking"
    "customer"      = "myridius"
    "environment"   = "dev"
    "product"       = "gh" #genius-hacks
    "owner"         = "devops"
    "region"        = "eastus2"
  }
  validation {
    condition     = contains(keys(var.tags), "business_unit")
    error_message = "ERROR: tag 'business_unit' is required, tags provided are: ${join(", ", keys(var.tags))}"
  }
  validation {
    condition     = contains(keys(var.tags), "customer")
    error_message = "ERROR: tag 'customer' is required, tags provided are: ${join(", ", keys(var.tags))}"
  }
  validation {
    condition     = contains(keys(var.tags), "environment")
    error_message = "ERROR: tag 'environment' is required, tags provided are: ${join(", ", keys(var.tags))}"
  }
  validation {
    condition     = contains(keys(var.tags), "product")
    error_message = "ERROR: tag 'product' is required, tags provided are: ${join(", ", keys(var.tags))}"
  }
  validation {
    condition     = contains(keys(var.tags), "owner")
    error_message = "ERROR: tag 'owner' is required, tags provided are: ${join(", ", keys(var.tags))}"
  }
  validation {
    condition     = contains(keys(var.tags), "region")
    error_message = "ERROR: tag 'region' is required, tags provided are: ${join(", ", keys(var.tags))}"
  }
}

#vNet Variables
variable "address_space" {
  description = "Address space for the Virtual Network"
  type        = list(string)
}

variable "ddos_protection_plan" {
  type = object({
    enable = bool
    id     = string
  })
  default     = null
  description = "The set of DDoS protection plan configuration"
}

#DNS Servers Variables
variable "dns_servers" {
  description = "List of DNS servers to associate with the virtual network"
  type        = list(string)
  default     = []
}

#Subnets Variables
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

#Network Security Group Variables
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

#Subnet-NSG map Variables
variable "subnet_nsg_map" {
  description = "Map of subnet name to NSG name for association"
  type        = map(string)
  default     = {}
}

#Route table variables
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

#Subnet-RT map Variables
variable "subnet_route_table_map" {
  description = "Map of subnet name to RT names for association"
  type        = map(string)
  default     = {}
}

#Vnet peering map
variable "vnet_peerings" {
  description = "Map of VNet peering configurations"
  type = map(object({
    name_local              = string
    rg_local                = string
    vnet_name_local         = string
    remote_vnet_id          = string
    allow_vnet_access       = optional(bool, true)
    allow_forwarded_traffic = optional(bool, true)
    allow_gateway_transit   = optional(bool, false)
    use_remote_gateways     = optional(bool, false)
  }))
  default = {}
}
