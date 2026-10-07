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
  description = "(Optional) Name of the log analytics workspace"
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

#Diagnostic settings enablement on the resource to route the logs and metrics to the log analytics workspace
variable "diagnostic_settings" {
  type = map(object({
    name                                     = optional(string, null)
    log_categories                           = optional(set(string), [])
    log_groups                               = optional(set(string), ["allLogs"])
    metric_categories                        = optional(set(string), ["AllMetrics"])
    log_analytics_destination_type           = optional(string, "Dedicated")
    workspace_resource_id                    = optional(string, null)
    storage_account_resource_id              = optional(string, null)
    event_hub_authorization_rule_resource_id = optional(string, null)
    event_hub_name                           = optional(string, null)
    marketplace_partner_resource_id          = optional(string, null)
  }))
  default     = {}
  description = <<DESCRIPTION
A map of diagnostic settings to create on the ddos protection plan. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.

- `name` - (Optional) The name of the diagnostic setting. One will be generated if not set, however this will not be unique if you want to create multiple diagnostic setting resources.
- `log_categories` - (Optional) A set of log categories to send to the log analytics workspace. Defaults to `[]`.
- `log_groups` - (Optional) A set of log groups to send to the log analytics workspace. Defaults to `["allLogs"]`.
- `metric_categories` - (Optional) A set of metric categories to send to the log analytics workspace. Defaults to `["AllMetrics"]`.
- `log_analytics_destination_type` - (Optional) The destination type for the diagnostic setting. Possible values are `Dedicated` and `AzureDiagnostics`. Defaults to `Dedicated`.
- `workspace_resource_id` - (Optional) The resource ID of the log analytics workspace to send logs and metrics to.
- `storage_account_resource_id` - (Optional) The resource ID of the storage account to send logs and metrics to.
- `event_hub_authorization_rule_resource_id` - (Optional) The resource ID of the event hub authorization rule to send logs and metrics to.
- `event_hub_name` - (Optional) The name of the event hub. If none is specified, the default event hub will be selected.
- `marketplace_partner_resource_id` - (Optional) The full ARM resource ID of the Marketplace resource to which you would like to send Diagnostic LogsLogs.
DESCRIPTION
  nullable    = false

  validation {
    condition     = alltrue([for _, v in var.diagnostic_settings : contains(["Dedicated", "AzureDiagnostics"], v.log_analytics_destination_type)])
    error_message = "Log analytics destination type must be one of: 'Dedicated', 'AzureDiagnostics'."
  }
  validation {
    condition = alltrue(
      [
        for _, v in var.diagnostic_settings :
        v.workspace_resource_id != null || v.storage_account_resource_id != null || v.event_hub_authorization_rule_resource_id != null || v.marketplace_partner_resource_id != null
      ]
    )
    error_message = "At least one of `workspace_resource_id`, `storage_account_resource_id`, `marketplace_partner_resource_id`, or `event_hub_authorization_rule_resource_id`, must be set."
  }
}

# Log analytics workspace variables
variable "log_analytics_workspace_allow_resource_only_permissions" {
  type        = bool
  default     = null
  description = "(Optional) Specifies if the log Analytics Workspace allow users accessing to data associated with resources they have permission to view, without permission to workspace. Defaults to `true`."
}

variable "log_analytics_workspace_cmk_for_query_forced" {
  type        = bool
  default     = null
  description = "(Optional) Is Customer Managed Storage mandatory for query management?"
}

variable "log_analytics_workspace_daily_quota_gb" {
  type        = number
  default     = null
  description = "(Optional) The workspace daily quota for ingestion in GB. Defaults to -1 (unlimited) if omitted."
}

variable "log_analytics_workspace_internet_ingestion_enabled" {
  type        = string
  default     = "true"
  description = "(Optional) Should the Log Analytics Workspace support ingestion over the Public Internet? Possible values are `true`, `false`, and `SecuredByPerimeter`. Defaults to `true`."
}

variable "log_analytics_workspace_internet_query_enabled" {
  type        = string
  default     = "true"
  description = "(Optional) Should the Log Analytics Workspace support querying over the Public Internet? Possible values are `true`, `false`, and `SecuredByPerimeter`. Defaults to `true`."
}

variable "log_analytics_workspace_local_authentication_enabled" {
  type        = bool
  default     = true
  description = "(Optional) Specifies if the log Analytics workspace should enforce authentication using Azure AD. Defaults to `true`."
}

variable "log_analytics_workspace_reservation_capacity_in_gb_per_day" {
  type        = number
  default     = null
  description = "(Optional) The capacity reservation level in GB for this workspace. Possible values are `100`, `200`, `300`, `400`, `500`, `1000`, `2000` and `5000`."
}

variable "log_analytics_workspace_retention_in_days" {
  type        = number
  default     = null
  description = "(Optional) The workspace data retention in days. Possible values are either 7 (Free Tier only) or range between 30 and 730."
}

variable "log_analytics_workspace_sku" {
  type        = string
  default     = null
  description = "(Optional) Specifies the SKU of the Log Analytics Workspace. Possible values are `Free`, `PerNode`, `Premium`, `Standard`, `Standalone`, `Unlimited`, `CapacityReservation`, and `PerGB2018` (new SKU as of `2018-04-03`). Defaults to `PerGB2018`."
}

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

variable "log_analytics_workspace_timeouts" {
  type = object({
    create = optional(string)
    delete = optional(string)
    read   = optional(string)
    update = optional(string)
  })
  default     = null
  description = <<DESCRIPTION
 - `create` - (Defaults to 30 minutes) Used when creating the Log Analytics Workspace.
 - `delete` - (Defaults to 30 minutes) Used when deleting the Log Analytics Workspace.
 - `read` - (Defaults to 5 minutes) Used when retrieving the Log Analytics Workspace.
 - `update` - (Defaults to 30 minutes) Used when updating the Log Analytics Workspace.
DESCRIPTION
}

# Application Insights variables
variable "application_insights_enabled" {
  type        = bool
  default     = true
  description = "(Optional) Specifies if the application insights should be used for log analytics"
}

variable "application_insights_name" {
  type        = string
  default     = null
  description = "(Optional) Name of the appliction insights"
}

variable "application_type" {
  type        = string
  default     = "web"
  description = "(Required) The type of the application. Possible values are 'web', 'ios', 'java', 'phone', 'MobileCenter', 'Node.JS', 'other', 'store'."

  validation {
    condition     = contains(["ios", "java", "MobileCenter", "Node.JS", "other", "phone", "store", "web"], var.application_type)
    error_message = "Invalid value for application type. Valid options are 'web', 'ios', 'java', 'phone', 'MobileCenter', 'Node.JS', 'other', 'store'."
  }
}

variable "workspace_id" {
  type        = string
  description = "(Optinal) The ID of the Log Analytics workspace to send data to"
  default     = null
}

variable "daily_data_cap_in_gb" {
  type        = number
  default     = 100
  description = "(Optional) The daily data cap in GB. 0 means unlimited."
}

variable "daily_data_cap_notifications_enabled" {
  type        = bool
  default     = true
  description = "(Optional) Enables the daily data cap notifications."
}

variable "ip_masking_enabled" {
  type        = bool
  default     = false
  description = "(Optional) Disables IP masking and logs the real client IP. Defaults to false. For more information see <https://aka.ms/avm/ipmasking>."
}

variable "force_customer_storage_for_profiler" {
  type        = bool
  default     = false
  description = "(Optional) Forces customer storage for profiler. Defaults to false."
}

variable "internet_ingestion_enabled" {
  type        = bool
  default     = true
  description = "(Optional) Enables internet ingestion. Defaults to true."
}

variable "internet_query_enabled" {
  type        = bool
  default     = true
  description = "(Optional) Enables internet query. Defaults to true."
}

variable "local_authentication_enabled" {
  type        = bool
  default     = true
  description = "(Optional) Enables local authentication. Defaults to true."
}

variable "retention_in_days" {
  type        = number
  default     = 90
  description = "(Optional) The retention period in days. 0 means unlimited."
}

variable "sampling_percentage" {
  type        = number
  default     = 100
  description = "(Optional) The sampling percentage. 100 means all."
}