#Common Variables
variable "resource_group_name" {
  description = "Name of the resource group where resources will be created"
  type        = string
}

variable "domain_name" {
  description = <<DESCRIPTION
  "Name of the private dns zone"
  "To use the Private DNS Zone with a Private Endpoint, the name of the Private DNS Zone must follow the Private DNS Zone name schema in the 
  product documentation (https://docs.microsoft.com/azure/private-link/private-endpoint-dns#virtual-network-and-on-premises-workloads-using-a-dns-forwarder) 
  in order for the two resources to be connected successfully"

  DESCRIPTION
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

# Index value to add to the name of the resource
variable "user_preferred_index" {
  description = "A value to append at the end of the name"
  type        = number
  default     = 1
}

#Resource level lock
variable "lock" {
  type = object({
    kind = string
    name = optional(string, null)
  })
  default     = null
  description = <<DESCRIPTION
  Controls the Resource Lock configuration for this resource. The following properties can be specified:

  - `kind` - (Required) The type of lock. Possible values are `\"CanNotDelete\"` and `\"ReadOnly\"`.
  - `name` - (Optional) The name of the lock. If not specified, a name will be generated based on the `kind` value. Changing this forces the creation of a new resource.
  DESCRIPTION

  validation {
    condition     = var.lock != null ? contains(["CanNotDelete", "ReadOnly"], var.lock.kind) : true
    error_message = "Lock kind must be either `\"CanNotDelete\"` or `\"ReadOnly\"`."
  }
}

#Role assignment on the resource
variable "role_assignments" {
  type = map(object({
    role_definition_id_or_name             = string
    principal_id                           = string
    scope                                  = string
    description                            = optional(string, null)
    skip_service_principal_aad_check       = optional(bool, false)
    condition                              = optional(string, null)
    condition_version                      = optional(string, null)
    delegated_managed_identity_resource_id = optional(string, null)
    principal_type                         = optional(string, null)
  }))
  default     = {}
  description = <<DESCRIPTION
  A map of role assignments to create on the <RESOURCE>. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.

  - `role_definition_id_or_name` - The ID or name of the role definition to assign to the principal.
  - `principal_id` - The ID of the principal to assign the role to.
  - `description` - (Optional) The description of the role assignment.
  - `skip_service_principal_aad_check` - (Optional) If set to true, skips the Azure Active Directory check for the service principal in the tenant. Defaults to false.
  - `condition` - (Optional) The condition which will be used to scope the role assignment.
  - `condition_version` - (Optional) The version of the condition syntax. Leave as `null` if you are not using a condition, if you are then valid values are '2.0'.
  - `delegated_managed_identity_resource_id` - (Optional) The delegated Azure Resource Id which contains a Managed Identity. Changing this forces a new resource to be created. This field is only used in cross-tenant scenario.
  - `principal_type` - (Optional) The type of the `principal_id`. Possible values are `User`, `Group` and `ServicePrincipal`. It is necessary to explicitly set this attribute when creating role assignments if the principal creating the assignment is constrained by ABAC rules that filters on the PrincipalType attribute.

  > Note: only set `skip_service_principal_aad_check` to true if you are assigning a role to a service principal.
  DESCRIPTION
  nullable    = false
}

# VNet linking to the Private DNS zone
variable "vnets_to_link" {
  type = list(object({
    name = string
    id   = string
  }))
  description = <<DESCRIPTION
  "List of VNets to link with the private DNS zone"

  - `name` - The name of the vnet to link.
  - `id` - The virtual network ID of the vnet to link.
  DESCRIPTION
  default     = []
}