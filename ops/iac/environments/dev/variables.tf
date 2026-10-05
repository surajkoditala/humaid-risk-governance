# Common Variables
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
}

variable "location" {
  description = "Azure region where the resource group will be created"
  type        = string
  nullable    = false
  default     = "eastus2"
}

variable "location_cus" {
  description = "Central US Azure region where the resource group will be created"
  type        = string
  nullable    = false
  default     = "centralus"
}

variable "public_network_access_enabled" {
  description = "Whether public network access is enabled for the container registry"
  type        = bool
  default     = true
}