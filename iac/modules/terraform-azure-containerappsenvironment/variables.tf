#Common Variables
variable "location" {
  description = "Azure region where the resource group will be created"
  type        = string
  nullable    = false
  default     = "eastus2"
}

variable "resource_group_name" {
  description = "Name of the resource group where resources will be created"
  type        = string
}

variable "name" {
  description = "Name of the container app environment"
  type        = string
  default     = null
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
  description = "List of VNets to link with the CAE private DNS zone"
  type = list(object({
    name = string
    id   = string
  }))
  default = []
}

# Dapr observability (optional Application Insights connection string)
variable "dapr_application_insights_connection_string" {
  description = "Optional Dapr Application Insights connection string."
  type        = string
  default     = null
}

# Optional infra resource group if using workload profiles
variable "infrastructure_resource_group_name" {
  description = "Resource group for infrastructure resources. Only valid if workload_profile is specified."
  type        = string
  default     = null
}

# Subnet for VNet integration
variable "infrastructure_subnet_id" {
  description = "Subnet ID to use for internal networking."
  type        = string
  default     = null
}

# Enable internal load balancer (requires subnet)
variable "internal_load_balancer_enabled" {
  description = "Use internal load balancer. Requires subnet."
  type        = bool
  default     = false
}

# Enable zone redundancy (requires subnet)
variable "zone_redundancy_enabled" {
  description = "Enable zone redundancy. Requires subnet."
  type        = bool
  default     = false
}

# Use existing Log Analytics Workspace ID (optional)
variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID. Required if logs_destination is log-analytics."
  type        = string
  default     = null
}

# Logs destination - 'log-analytics' or 'azure-monitor'
variable "logs_destination" {
  description = "Destination for logs: 'log-analytics' or 'azure-monitor', default is 'log-analytics'. Don’t need to set logs_destination when you’re already using log_analytics_workspace_id"
  type        = string
  default     = null
}

# Whether to create a new Log Analytics Workspace
variable "create_log_analytics_workspace" {
  description = "Whether to create a Log Analytics Workspace."
  type        = bool
  default     = false
}

# Optional workload profiles for custom scaling
variable "workload_profiles" {
  description = "List of workload profiles."
  type = list(object({
    name                  = string #must be less than 16 characters
    workload_profile_type = string #Possible values include Consumption, D4, D8, D16, D32, E4, E8, E16 and E32
    maximum_count         = number
    minimum_count         = number
  }))
  default = []
}

# Enforce mutual TLS between apps
variable "mutual_tls_enabled" {
  description = "Enable mutual TLS for container apps."
  type        = bool
  default     = false
}

# Optional Identity block
variable "managed_identities" {
  type = object({
    system_assigned            = optional(bool, false)
    user_assigned_resource_ids = optional(set(string), [])
  })
  default     = {}
  description = <<DESCRIPTION
  Controls the Managed Identity configuration on this resource. The following properties can be specified:

  - `system_assigned` - (Optional) Specifies if the System Assigned Managed Identity should be enabled.
  - `user_assigned_resource_ids` - (Optional) Specifies a list of User Assigned Managed Identity resource IDs to be assigned to this resource.
  DESCRIPTION
  nullable    = false
}