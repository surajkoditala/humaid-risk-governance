# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v1.0.0] - 2025-07-17
### Added
- Initial release of the module to create:
  - Azure Container Registry with configurable SKU (`Basic`, `Standard`, `Premium`), admin access, anonymous pull, export policy, quarantine policy, and content trust controls
  - Premium SKU features: zone redundancy, untagged image retention policy, and data endpoint support
  - Geo-replication across multiple Azure regions with per-replica zone redundancy and regional endpoint configuration
  - Customer-managed key (CMK) encryption via Azure Key Vault using a user-assigned managed identity
  - System-assigned and user-assigned managed identity support
  - Network rule set for IP-based access restrictions with configurable default action (Premium SKU required)
  - Private endpoints for secure, private network access with managed and unmanaged DNS zone group modes
  - Application Security Group (ASG) associations on private endpoints
  - Azure Monitor diagnostic settings with support for Log Analytics, Event Hub, and Storage
  - Role assignments (RBAC) for fine-grained access control; supports role name or full definition ID, conditions, and delegated managed identity
  - Optional resource-level lock (`CanNotDelete` or `ReadOnly`) for protection of critical environments
  - Standard naming convention (`cr<product><env><index>`) with optional custom name override; name validated to 5–50 lowercase alphanumeric characters
  - Lifecycle preconditions enforcing Premium SKU requirement for zone redundancy, network rule sets, and CMK encryption
