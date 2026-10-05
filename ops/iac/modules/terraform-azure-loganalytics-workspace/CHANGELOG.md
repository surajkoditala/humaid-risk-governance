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
