# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v1.0.0] - 2026-06-16
### Added
- Initial release of the module to create:
  - Azure Key Vault with configurable SKU, purge protection, soft delete, and RBAC authorization
  - Optional resource-level lock for protection of critical environments
  - Private Endpoint for secure, private access to Key Vault
  - Private DNS Zone creation with automatic record set management
  - Virtual Network linking for DNS zone resolution
  - Azure Monitor diagnostic settings with support for Log Analytics, Event Hub, and Storage
  - Network ACL configuration with IP rules and VNet-based access
  - Azure Monitor metric alerts for Key Vault with support for static and dynamic threshold criteria.
  - Key Vault delete activity log alert for successful delete operations.
  - Optional action group integration for critical metric alerts and delete activity alerts.
  - Monitoring alerts example with action group, availability, capacity, latency, and service API result alerts.
  - Outputs for Key Vault metric alert IDs and delete activity log alert ID.