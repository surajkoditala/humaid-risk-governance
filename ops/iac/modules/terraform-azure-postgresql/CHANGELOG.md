# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v1.0.0] - 2026-06-29
### Added
- Initial release of the module to create:
  - Azure PostgreSQL Flexible Server with configurable SKU, version, storage, backup retention, and availability zone placement
  - High availability with `ZoneRedundant` or `SameZone` modes and standby provisioning
  - Password-based and Azure Active Directory authentication, including ephemeral password support to avoid state exposure
  - Active Directory administrator assignment for EntraID-based access control
  - Customer-managed keys (CMK) integration via Azure Key Vault, including geo-backup key support
  - System-assigned and user-assigned managed identity support
  - Private Endpoint for secure, private network access to the PostgreSQL server
  - Private DNS zone integration for name resolution of private endpoints
  - Firewall rules for IP-based access control
  - Virtual endpoints for read/write routing across primary and replica servers
  - Server configuration parameters for PostgreSQL engine tuning
  - Azure Monitor diagnostic settings with support for Log Analytics, Event Hub, and Storage
  - Role assignments (RBAC) for fine-grained access control on the server and private endpoints
  - Optional resource-level lock for protection of critical environments
  - Maintenance window configuration for controlled update scheduling
  - Geo-redundant backup with configurable retention (7–35 days)
  - Storage auto-grow support
