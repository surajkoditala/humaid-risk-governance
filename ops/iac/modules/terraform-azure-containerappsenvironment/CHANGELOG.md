# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v1.0.0] - 2026-07-06
### Added
- Initial release of the module to create:
  - Azure Container App Environment with configurable tags and naming
  - Optional Log Analytics Workspace creation
  - Support for Dapr Application Insights integration
  - Infrastructure subnet integration for VNet scenarios
  - Internal Load Balancer and Zone Redundancy options
  - Dynamic workload profiles using `for_each`
  - Mutual TLS support for secure app communication
  - Private DNS Zone creation for internal name resolution.
  - Virtual Network linking for DNS integration.
  - DNS record sets creation within the private DNS zone.
  - Optional resource lock to prevent accidental deletion or modification.
  - Logs routing to Log Analytics Workspace for centralized monitoring.
  - Virtual Network linking for DNS integration can be done for multiple VNets by passing in a list
