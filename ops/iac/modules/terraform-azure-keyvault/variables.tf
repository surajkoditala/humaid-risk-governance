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
  description = "Name of the key vault"
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

variable "enable_monitoring_alerts" {
  type        = bool
  default     = false
  description = "Controls whether Azure Monitor metric and activity log alerts are created for the Key Vault."
  nullable    = false
}

variable "action_group_id" {
  type        = string
  default     = null
  description = "The Azure Monitor action group resource ID used by Key Vault monitoring alerts."
}

variable "keyvault_alerts" {
  type = map(object({
    enabled                = optional(bool, true)
    name                   = optional(string, null)
    description            = optional(string, null)
    criterion_type         = optional(string, "StaticThresholdCriterion")
    severity               = optional(number, 3)
    frequency              = optional(string, "PT5M")
    window                 = optional(string, "PT5M")
    auto_mitigate          = optional(bool, true)
    metric_namespace       = optional(string, "Microsoft.KeyVault/vaults")
    metric_name            = string
    aggregation            = string
    operator               = string
    threshold              = optional(number)
    skip_metric_validation = optional(bool, false)
    alert_sensitivity      = optional(string)
    failing_periods = optional(object({
      min_failing_periods_to_alert = number
      number_of_evaluation_periods = number
    }))
    dimensions = optional(list(object({
      name     = string
      operator = optional(string, "Include")
      values   = list(string)
    })), [])
  }))
  default     = {}
  nullable    = false
  description = "A map of Azure Monitor metric alerts to create for the Key Vault."

  validation {
    condition = alltrue([
      for _, v in var.keyvault_alerts :
      contains(["StaticThresholdCriterion", "DynamicThresholdCriterion"], v.criterion_type)
    ])
    error_message = "Key Vault alert criterion_type must be StaticThresholdCriterion or DynamicThresholdCriterion."
  }
  validation {
    condition     = alltrue([for _, v in var.keyvault_alerts : v.severity >= 0 && v.severity <= 4])
    error_message = "Key Vault alert severity must be between 0 and 4."
  }
  validation {
    condition = alltrue([
      for _, v in var.keyvault_alerts :
      v.criterion_type == "DynamicThresholdCriterion" ?
      contains(["GreaterThan", "LessThan", "GreaterOrLessThan"], v.operator) :
      contains(["Equals", "GreaterThan", "GreaterThanOrEqual", "LessThan", "LessThanOrEqual"], v.operator)
    ])
    error_message = "Key Vault alert operator must be one of: Equals, GreaterThan, GreaterThanOrEqual, LessThan, LessThanOrEqual for static criteria, or GreaterThan, LessThan, GreaterOrLessThan for dynamic criteria."
  }
  validation {
    condition     = alltrue([for _, v in var.keyvault_alerts : contains(["Average", "Count", "Minimum", "Maximum", "Total"], v.aggregation)])
    error_message = "Key Vault alert aggregation must be one of: Average, Count, Minimum, Maximum, Total."
  }
  validation {
    condition = alltrue([
      for _, v in var.keyvault_alerts :
      v.criterion_type == "DynamicThresholdCriterion" || v.threshold != null
    ])
    error_message = "threshold is required when criterion_type is StaticThresholdCriterion."
  }
  validation {
    condition = alltrue([
      for _, v in var.keyvault_alerts :
      v.criterion_type == "StaticThresholdCriterion" || v.failing_periods != null
    ])
    error_message = "failing_periods is required when criterion_type is DynamicThresholdCriterion."
  }
  validation {
    condition = alltrue([
      for _, v in var.keyvault_alerts :
      v.alert_sensitivity == null || contains(["Low", "Medium", "High"], v.alert_sensitivity)
    ])
    error_message = "alert_sensitivity must be one of: Low, Medium, High."
  }
}

variable "enable_keyvault_delete_alert" {
  type        = bool
  default     = true
  description = "Controls whether an activity log alert is created for successful Key Vault delete operations."
  nullable    = false
}

variable "sku_name" {
  type        = string
  default     = "standard"
  description = "The SKU name of the Key Vault. Default is `premium`. Possible values are `standard` and `premium`."

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "The SKU name must be either `standard` or `premium`."
  }
}

variable "tenant_id" {
  type        = string
  description = "The Azure tenant ID used for authenticating requests to Key Vault. You can use the `azurerm_client_config` data source to retrieve it."

  validation {
    condition     = can(regex("^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$", var.tenant_id))
    error_message = "The tenant ID must be a valid GUID. Letters must be lowercase."
  }
}

variable "legacy_access_policies_enabled" {
  type        = bool
  default     = false
  description = "Specifies whether legacy access policies are enabled for this Key Vault. Prevents use of Azure RBAC for data plane."
  nullable    = false
}

variable "enabled_for_deployment" {
  type        = bool
  default     = false
  description = "Specifies whether Azure Virtual Machines are permitted to retrieve certificates stored as secrets from the vault."
}

variable "enabled_for_disk_encryption" {
  type        = bool
  default     = false
  description = "Specifies whether Azure Disk Encryption is permitted to retrieve secrets from the vault and unwrap keys."
}

variable "enabled_for_template_deployment" {
  type        = bool
  default     = false
  description = "Specifies whether Azure Resource Manager is permitted to retrieve secrets from the vault."
}

variable "public_network_access_enabled" {
  type        = bool
  default     = true
  description = "Specifies whether public access is permitted."
}

variable "purge_protection_enabled" {
  type        = bool
  default     = true
  description = "Specifies whether protection against purge is enabled for this Key Vault. Note once enabled this cannot be disabled."
}

variable "soft_delete_retention_days" {
  type        = number
  default     = null
  description = <<DESCRIPTION
The number of days that items should be retained for once soft-deleted. This value can be between 7 and 90 (the default) days.
DESCRIPTION

  validation {
    condition     = var.soft_delete_retention_days == null ? true : var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "Value must be between 7 and 90."
  }
  validation {
    condition     = var.soft_delete_retention_days == null ? true : ceil(var.soft_delete_retention_days) == var.soft_delete_retention_days
    error_message = "Value must be an integer."
  }
}

variable "network_acls" {
  type = object({
    bypass                     = optional(string, "None")
    default_action             = optional(string, "Deny")
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  default     = {}
  description = <<DESCRIPTION
The network ACL configuration for the Key Vault.
If not specified then the Key Vault will be created with a firewall that blocks access.
Specify `null` to create the Key Vault with no firewall.

- `bypass` - (Optional) Should Azure Services bypass the ACL. Possible values are `AzureServices` and `None`. Defaults to `None`.
- `default_action` - (Optional) The default action when no rule matches. Possible values are `Allow` and `Deny`. Defaults to `Deny`.
- `ip_rules` - (Optional) A list of IP rules in CIDR format. Defaults to `[]`.
- `virtual_network_subnet_ids` - (Optional) When using with Service Endpoints, a list of subnet IDs to associate with the Key Vault. Defaults to `[]`.
DESCRIPTION

  validation {
    condition     = var.network_acls == null ? true : contains(["AzureServices", "None"], var.network_acls.bypass)
    error_message = "The bypass value must be either `AzureServices` or `None`."
  }
  validation {
    condition     = var.network_acls == null ? true : contains(["Allow", "Deny"], var.network_acls.default_action)
    error_message = "The default_action value must be either `Allow` or `Deny`."
  }
}

variable "private_endpoints" {
  type = map(object({
    name = optional(string, null)
    role_assignments = optional(map(object({
      role_definition_id_or_name             = string
      principal_id                           = string
      description                            = optional(string, null)
      skip_service_principal_aad_check       = optional(bool, false)
      condition                              = optional(string, null)
      condition_version                      = optional(string, null)
      delegated_managed_identity_resource_id = optional(string, null)
      principal_type                         = optional(string, null)
    })), {})
    lock = optional(object({
      kind = string
      name = optional(string, null)
    }), null)
    tags                                    = optional(map(string), null)
    subnet_resource_id                      = string
    subresource_name                        = optional(string, "vault")
    private_dns_zone_group_name             = optional(string, "default") #not needed
    private_dns_zone_resource_ids           = optional(set(string), [])   #not needed
    application_security_group_associations = optional(map(string), {})
    private_service_connection_name         = optional(string, null)
    network_interface_name                  = optional(string, null)
    location                                = optional(string, null)
    resource_group_name                     = optional(string, null)
    ip_configurations = optional(map(object({
      name               = string
      private_ip_address = string
    })), {})
  }))
  default     = {}
  description = <<DESCRIPTION
A map of private endpoints to create on the Key Vault. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.

- `name` - (Optional) The name of the private endpoint. One will be generated if not set.
- `role_assignments` - (Optional) A map of role assignments to create on the private endpoint. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time. See `var.role_assignments` for more information.
- `lock` - (Optional) The lock level to apply to the private endpoint. Default is `None`. Possible values are `None`, `CanNotDelete`, and `ReadOnly`.
- `tags` - (Optional) A mapping of tags to assign to the private endpoint.
- `subnet_resource_id` - The resource ID of the subnet to deploy the private endpoint in.
- `private_dns_zone_group_name` - (Optional) The name of the private DNS zone group. One will be generated if not set.
- `private_dns_zone_resource_ids` - (Optional) A set of resource IDs of private DNS zones to associate with the private endpoint. If not set, no zone groups will be created and the private endpoint will not be associated with any private DNS zones. DNS records must be managed external to this module.
- `application_security_group_resource_ids` - (Optional) A map of resource IDs of application security groups to associate with the private endpoint. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.
- `private_service_connection_name` - (Optional) The name of the private service connection. One will be generated if not set.
- `network_interface_name` - (Optional) The name of the network interface. One will be generated if not set.
- `location` - (Optional) The Azure location where the resources will be deployed. Defaults to the location of the resource group.
- `resource_group_name` - (Optional) The resource group where the resources will be deployed. Defaults to the resource group of the Key Vault.
- `ip_configurations` - (Optional) A map of IP configurations to create on the private endpoint. If not specified the platform will create one. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.
  - `name` - The name of the IP configuration.
  - `private_ip_address` - The private IP address of the IP configuration.
DESCRIPTION
  nullable    = false
}

variable "private_endpoints_manage_dns_zone_group" {
  type        = bool
  default     = true
  description = "Whether to manage private DNS zone groups with this module. If set to false, you must manage private DNS zone groups externally, e.g. using Azure Policy."
  nullable    = false
}
