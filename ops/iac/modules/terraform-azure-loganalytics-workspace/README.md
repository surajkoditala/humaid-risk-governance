<!-- BEGIN_TF_DOCS -->


## Introduction

This module provisions an **Azure Log Analytics Workspace** with an optional **Application Insights** instance for centralized observability, telemetry, and log management.

---

## 📘 Overview

This module enables:

- **Azure Log Analytics Workspace** deployment with configurable SKU, retention period, daily ingestion quota, and capacity reservation
- **Application Insights** integration for APM and telemetry, linked to the Log Analytics Workspace; supports custom application type, sampling percentage, daily data cap, and IP masking controls
- **Internet ingestion and query controls** to restrict or allow public access to the workspace
- **Local authentication toggle** to enforce Azure Active Directory-only access
- **Customer-managed key (CMK)** enforcement for query management
- **Managed identity** support for both system-assigned and user-assigned identities
- **Diagnostic settings** to route the workspace's own logs and metrics to another Log Analytics workspace, Storage Account, or Event Hub
- **Role assignments (RBAC)** for fine-grained access control on the workspace
- **Resource locks** to protect against accidental deletion or modification
- **Standard naming convention** (`log-<product>-<env>-<index>` / `appi-<product>-<env>-<index>`) with optional custom name override
- **Required tag enforcement** via input validation for `business_unit`, `customer`, `environment`, `product`, `owner`, and `region`

#Examples

#Default Example
```hcl
module "log_analytics_workspace" {
  source = "../../" # In reality, this will be like "app.terraform.io/<tfc-org-name>/<registry-name>/azure"; version = "<version>"

  location            = "eastus2"
  resource_group_name = "rg-gh-dev-sandbox"
  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }
}





terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0, < 5.0.0"
    }
  }
  required_version = ">= 1.9, < 2.0"

  # During Infra Provisioning in Myridius, the backend will be configured to use TFC
  # This is to ensure that the state file is stored in TFC and not on the local machine
  # cloud {
  #   organization = "Myridius"

  #   workspaces {
  #     name = "your-workspace-name"
  #   }
  # }

  # If you want to use a azure storage account as the backend, you can do so by uncommenting the following block
  # backend "azurerm" {
  #   resource_group_name = "your-resource-group-name"
  #   storage_account_name = "your-storage-account-name"
  #   container_name = "your-container-name"
  #   key = "your-key"
  # }

}

provider "azurerm" {
  features {}
}


```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.8 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0.0, < 5.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.81.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_application_insights.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/application_insights) | resource |
| [azurerm_log_analytics_workspace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_workspace) | resource |
| [azurerm_management_lock.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_lock) | resource |
| [azurerm_monitor_diagnostic_setting.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| <a name="input_application_insights_enabled"></a> [application\_insights\_enabled](#input\_application\_insights\_enabled) | (Optional) Specifies if the application insights should be used for log analytics | `bool` | `true` |
| <a name="input_application_insights_name"></a> [application\_insights\_name](#input\_application\_insights\_name) | (Optional) Name of the appliction insights | `string` | `null` |
| <a name="input_application_type"></a> [application\_type](#input\_application\_type) | (Required) The type of the application. Possible values are 'web', 'ios', 'java', 'phone', 'MobileCenter', 'Node.JS', 'other', 'store'. | `string` | `"web"` |
| <a name="input_daily_data_cap_in_gb"></a> [daily\_data\_cap\_in\_gb](#input\_daily\_data\_cap\_in\_gb) | (Optional) The daily data cap in GB. 0 means unlimited. | `number` | `100` |
| <a name="input_daily_data_cap_notifications_enabled"></a> [daily\_data\_cap\_notifications\_enabled](#input\_daily\_data\_cap\_notifications\_enabled) | (Optional) Enables the daily data cap notifications. | `bool` | `true` |
| <a name="input_diagnostic_settings"></a> [diagnostic\_settings](#input\_diagnostic\_settings) | A map of diagnostic settings to create on the ddos protection plan. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/><br/>- `name` - (Optional) The name of the diagnostic setting. One will be generated if not set, however this will not be unique if you want to create multiple diagnostic setting resources.<br/>- `log_categories` - (Optional) A set of log categories to send to the log analytics workspace. Defaults to `[]`.<br/>- `log_groups` - (Optional) A set of log groups to send to the log analytics workspace. Defaults to `["allLogs"]`.<br/>- `metric_categories` - (Optional) A set of metric categories to send to the log analytics workspace. Defaults to `["AllMetrics"]`.<br/>- `log_analytics_destination_type` - (Optional) The destination type for the diagnostic setting. Possible values are `Dedicated` and `AzureDiagnostics`. Defaults to `Dedicated`.<br/>- `workspace_resource_id` - (Optional) The resource ID of the log analytics workspace to send logs and metrics to.<br/>- `storage_account_resource_id` - (Optional) The resource ID of the storage account to send logs and metrics to.<br/>- `event_hub_authorization_rule_resource_id` - (Optional) The resource ID of the event hub authorization rule to send logs and metrics to.<br/>- `event_hub_name` - (Optional) The name of the event hub. If none is specified, the default event hub will be selected.<br/>- `marketplace_partner_resource_id` - (Optional) The full ARM resource ID of the Marketplace resource to which you would like to send Diagnostic LogsLogs. | <pre>map(object({<br/>    name                                     = optional(string, null)<br/>    log_categories                           = optional(set(string), [])<br/>    log_groups                               = optional(set(string), ["allLogs"])<br/>    metric_categories                        = optional(set(string), ["AllMetrics"])<br/>    log_analytics_destination_type           = optional(string, "Dedicated")<br/>    workspace_resource_id                    = optional(string, null)<br/>    storage_account_resource_id              = optional(string, null)<br/>    event_hub_authorization_rule_resource_id = optional(string, null)<br/>    event_hub_name                           = optional(string, null)<br/>    marketplace_partner_resource_id          = optional(string, null)<br/>  }))</pre> | `{}` |
| <a name="input_force_customer_storage_for_profiler"></a> [force\_customer\_storage\_for\_profiler](#input\_force\_customer\_storage\_for\_profiler) | (Optional) Forces customer storage for profiler. Defaults to false. | `bool` | `false` |
| <a name="input_internet_ingestion_enabled"></a> [internet\_ingestion\_enabled](#input\_internet\_ingestion\_enabled) | (Optional) Enables internet ingestion. Defaults to true. | `bool` | `true` |
| <a name="input_internet_query_enabled"></a> [internet\_query\_enabled](#input\_internet\_query\_enabled) | (Optional) Enables internet query. Defaults to true. | `bool` | `true` |
| <a name="input_ip_masking_enabled"></a> [ip\_masking\_enabled](#input\_ip\_masking\_enabled) | (Optional) Disables IP masking and logs the real client IP. Defaults to false. For more information see <https://aka.ms/avm/ipmasking>. | `bool` | `false` |
| <a name="input_local_authentication_enabled"></a> [local\_authentication\_enabled](#input\_local\_authentication\_enabled) | (Optional) Enables local authentication. Defaults to true. | `bool` | `true` |
| <a name="input_location"></a> [location](#input\_location) | Azure region where the resource group will be created | `string` | `"eastus2"` |
| <a name="input_lock"></a> [lock](#input\_lock) | Controls the Resource Lock configuration for this resource. The following properties can be specified:<br/><br/>  - `kind` - (Required) The type of lock. Possible values are `\"CanNotDelete\"` and `\"ReadOnly\"`.<br/>  - `name` - (Optional) The name of the lock. If not specified, a name will be generated based on the `kind` value. Changing this forces the creation of a new resource. | <pre>object({<br/>    kind = string<br/>    name = optional(string, null)<br/>  })</pre> | `null` |
| <a name="input_log_analytics_workspace_allow_resource_only_permissions"></a> [log\_analytics\_workspace\_allow\_resource\_only\_permissions](#input\_log\_analytics\_workspace\_allow\_resource\_only\_permissions) | (Optional) Specifies if the log Analytics Workspace allow users accessing to data associated with resources they have permission to view, without permission to workspace. Defaults to `true`. | `bool` | `null` |
| <a name="input_log_analytics_workspace_cmk_for_query_forced"></a> [log\_analytics\_workspace\_cmk\_for\_query\_forced](#input\_log\_analytics\_workspace\_cmk\_for\_query\_forced) | (Optional) Is Customer Managed Storage mandatory for query management? | `bool` | `null` |
| <a name="input_log_analytics_workspace_daily_quota_gb"></a> [log\_analytics\_workspace\_daily\_quota\_gb](#input\_log\_analytics\_workspace\_daily\_quota\_gb) | (Optional) The workspace daily quota for ingestion in GB. Defaults to -1 (unlimited) if omitted. | `number` | `null` |
| <a name="input_log_analytics_workspace_internet_ingestion_enabled"></a> [log\_analytics\_workspace\_internet\_ingestion\_enabled](#input\_log\_analytics\_workspace\_internet\_ingestion\_enabled) | (Optional) Should the Log Analytics Workspace support ingestion over the Public Internet? Possible values are `true`, `false`, and `SecuredByPerimeter`. Defaults to `true`. | `string` | `"true"` |
| <a name="input_log_analytics_workspace_internet_query_enabled"></a> [log\_analytics\_workspace\_internet\_query\_enabled](#input\_log\_analytics\_workspace\_internet\_query\_enabled) | (Optional) Should the Log Analytics Workspace support querying over the Public Internet? Possible values are `true`, `false`, and `SecuredByPerimeter`. Defaults to `true`. | `string` | `"true"` |
| <a name="input_log_analytics_workspace_local_authentication_enabled"></a> [log\_analytics\_workspace\_local\_authentication\_enabled](#input\_log\_analytics\_workspace\_local\_authentication\_enabled) | (Optional) Specifies if the log Analytics workspace should enforce authentication using Azure AD. Defaults to `true`. | `bool` | `true` |
| <a name="input_log_analytics_workspace_reservation_capacity_in_gb_per_day"></a> [log\_analytics\_workspace\_reservation\_capacity\_in\_gb\_per\_day](#input\_log\_analytics\_workspace\_reservation\_capacity\_in\_gb\_per\_day) | (Optional) The capacity reservation level in GB for this workspace. Possible values are `100`, `200`, `300`, `400`, `500`, `1000`, `2000` and `5000`. | `number` | `null` |
| <a name="input_log_analytics_workspace_retention_in_days"></a> [log\_analytics\_workspace\_retention\_in\_days](#input\_log\_analytics\_workspace\_retention\_in\_days) | (Optional) The workspace data retention in days. Possible values are either 7 (Free Tier only) or range between 30 and 730. | `number` | `null` |
| <a name="input_log_analytics_workspace_sku"></a> [log\_analytics\_workspace\_sku](#input\_log\_analytics\_workspace\_sku) | (Optional) Specifies the SKU of the Log Analytics Workspace. Possible values are `Free`, `PerNode`, `Premium`, `Standard`, `Standalone`, `Unlimited`, `CapacityReservation`, and `PerGB2018` (new SKU as of `2018-04-03`). Defaults to `PerGB2018`. | `string` | `null` |
| <a name="input_log_analytics_workspace_timeouts"></a> [log\_analytics\_workspace\_timeouts](#input\_log\_analytics\_workspace\_timeouts) | - `create` - (Defaults to 30 minutes) Used when creating the Log Analytics Workspace.<br/> - `delete` - (Defaults to 30 minutes) Used when deleting the Log Analytics Workspace.<br/> - `read` - (Defaults to 5 minutes) Used when retrieving the Log Analytics Workspace.<br/> - `update` - (Defaults to 30 minutes) Used when updating the Log Analytics Workspace. | <pre>object({<br/>    create = optional(string)<br/>    delete = optional(string)<br/>    read   = optional(string)<br/>    update = optional(string)<br/>  })</pre> | `null` |
| <a name="input_managed_identities"></a> [managed\_identities](#input\_managed\_identities) | Controls the Managed Identity configuration on this resource. The following properties can be specified:<br/><br/>  - `system_assigned` - (Optional) Specifies if the System Assigned Managed Identity should be enabled.<br/>  - `user_assigned_resource_ids` - (Optional) Specifies a list of User Assigned Managed Identity resource IDs to be assigned to this resource. | <pre>object({<br/>    system_assigned            = optional(bool, false)<br/>    user_assigned_resource_ids = optional(set(string), [])<br/>  })</pre> | `{}` |
| <a name="input_name"></a> [name](#input\_name) | (Optional) Name of the log analytics workspace | `string` | `null` |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group where resources will be created | `string` | n/a |
| <a name="input_retention_in_days"></a> [retention\_in\_days](#input\_retention\_in\_days) | (Optional) The retention period in days. 0 means unlimited. | `number` | `90` |
| <a name="input_role_assignments"></a> [role\_assignments](#input\_role\_assignments) | A map of role assignments to create on the <RESOURCE>. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.<br/><br/>  - `role_definition_id_or_name` - The ID or name of the role definition to assign to the principal.<br/>  - `principal_id` - The ID of the principal to assign the role to.<br/>  - `description` - (Optional) The description of the role assignment.<br/>  - `skip_service_principal_aad_check` - (Optional) If set to true, skips the Azure Active Directory check for the service principal in the tenant. Defaults to false.<br/>  - `condition` - (Optional) The condition which will be used to scope the role assignment.<br/>  - `condition_version` - (Optional) The version of the condition syntax. Leave as `null` if you are not using a condition, if you are then valid values are '2.0'.<br/>  - `delegated_managed_identity_resource_id` - (Optional) The delegated Azure Resource Id which contains a Managed Identity. Changing this forces a new resource to be created. This field is only used in cross-tenant scenario.<br/>  - `principal_type` - (Optional) The type of the `principal_id`. Possible values are `User`, `Group` and `ServicePrincipal`. It is necessary to explicitly set this attribute when creating role assignments if the principal creating the assignment is constrained by ABAC rules that filters on the PrincipalType attribute.<br/><br/>  > Note: only set `skip_service_principal_aad_check` to true if you are assigning a role to a service principal. | <pre>map(object({<br/>    role_definition_id_or_name             = string<br/>    principal_id                           = string<br/>    scope                                  = string<br/>    description                            = optional(string, null)<br/>    skip_service_principal_aad_check       = optional(bool, false)<br/>    condition                              = optional(string, null)<br/>    condition_version                      = optional(string, null)<br/>    delegated_managed_identity_resource_id = optional(string, null)<br/>    principal_type                         = optional(string, null)<br/>  }))</pre> | `{}` |
| <a name="input_sampling_percentage"></a> [sampling\_percentage](#input\_sampling\_percentage) | (Optional) The sampling percentage. 100 means all. | `number` | `100` |
| <a name="input_tags"></a> [tags](#input\_tags) | Map of tags to be applied to all resources | `map(string)` | <pre>{<br/>  "business_unit": "banking",<br/>  "customer": "myridius",<br/>  "environment": "dev",<br/>  "owner": "devops",<br/>  "product": "gh",<br/>  "region": "eastus2"<br/>}</pre> |
| <a name="input_user_preferred_index"></a> [user\_preferred\_index](#input\_user\_preferred\_index) | A value to append at the end of the name | `number` | `1` |
| <a name="input_workspace_id"></a> [workspace\_id](#input\_workspace\_id) | (Optinal) The ID of the Log Analytics workspace to send data to | `string` | `null` |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_application_insights_app_id"></a> [application\_insights\_app\_id](#output\_application\_insights\_app\_id) | App ID of the Application Insights |
| <a name="output_application_insights_connection_string"></a> [application\_insights\_connection\_string](#output\_application\_insights\_connection\_string) | Connection String of the Application Insights |
| <a name="output_application_insights_instrumentation_key"></a> [application\_insights\_instrumentation\_key](#output\_application\_insights\_instrumentation\_key) | Instrumentation Key of the Application Insights |
| <a name="output_application_insights_name"></a> [application\_insights\_name](#output\_application\_insights\_name) | Name of the Application Insights |
| <a name="output_application_insights_resource"></a> [application\_insights\_resource](#output\_application\_insights\_resource) | "This is the full output for the Application Insights resource. This is the default output for the module."<br/>Examples:<br/>- module.log\_analytics.application\_insights\_resource.id<br/>- module.log\_analytics.application\_insights\_resource.name |
| <a name="output_application_insights_resource_id"></a> [application\_insights\_resource\_id](#output\_application\_insights\_resource\_id) | The ID of the Application Insights |
| <a name="output_log_analytics_workspace_resource"></a> [log\_analytics\_workspace\_resource](#output\_log\_analytics\_workspace\_resource) | "This is the full output for the Log Analytics resource. This is the default output for the module."<br/>Examples:<br/>- module.log\_analytics.log\_analytics\_workspace\_resource.id<br/>- module.log\_analytics.log\_analytics\_workspace\_resource.name |
| <a name="output_log_analytics_workspace_resource_id"></a> [log\_analytics\_workspace\_resource\_id](#output\_log\_analytics\_workspace\_resource\_id) | The resource ID for the resource. |

# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v1.0.0] - 2026-07-01
### Added
- Initial release of the module to create:
  - `azurerm_log_analytics_workspace` — central log sink with configurable SKU, retention, daily quota, internet ingestion/query controls, local authentication toggle, and CMK query enforcement
  - `azurerm_application_insights` — workspace-based APM instance linked to the Log Analytics Workspace; supports custom name, application type, daily data cap, sampling percentage, and IP masking controls
  - `azurerm_management_lock` — optional `CanNotDelete` or `ReadOnly` resource lock for higher environments
  - `azurerm_role_assignment` — optional RBAC role assignments on the workspace; supports role name or full definition ID, conditions, delegated managed identity, and principal type
  - `azurerm_monitor_diagnostic_setting` — optional diagnostic settings to route the workspace's own logs and metrics to another Log Analytics workspace, storage account, or event hub
- Managed identity support: System Assigned, User Assigned, or both
- Standard naming convention: `log-<product>-<env>-<index>` / `appi-<product>-<env>-<index>`; custom name override via `var.name` and `var.application_insights_name`
- Required tag enforcement via input validation for `business_unit`, `customer`, `environment`, `product`, `owner`, `region`
- Configurable timeout block for workspace create/read/update/delete operations

<!-- END_TF_DOCS -->