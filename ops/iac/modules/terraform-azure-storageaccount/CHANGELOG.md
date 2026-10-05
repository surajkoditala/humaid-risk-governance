# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v1.0.0] - 2026-06-18
### Added
- Initial release of the module to create:
  - Azure Storage Account with configurable replication, tier, kind, networking, and encryption
  - Optional resource-level lock for protection of critical environments
  - Role assignments (RBAC) for fine-grained access control
  - Customer-managed keys (CMK) integration with Azure Key Vault
  - Private Endpoint for secure, private access to Storage Account with managing the private DNS zone option
  - Azure Monitor diagnostic settings with support for Log Analytics, Event Hub, and Storage
  - Network rules with IP restrictions and VNet-based access
  - Private Endpoints for multiple subresource names based on the input
  - Storage Account metric alerts with static and dynamic criteria support.
