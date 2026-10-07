# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v1.0.0] - 2026-06-11
### Added
- Initial release of the module to create:
  - Azure Virtual Network with address space
  - Optional integration with DDoS Protection Plan
  - DNS servers association to VNet
  - Subnets with optional delegation and address prefixes
  - Network Security Groups (NSGs) with support for dynamic security rules
  - Subnet-to-NSG associations
  - Support for `service_endpoints` in subnet definition.
  - Support for additional NSG rule fields:
    - `source_port_ranges`
    - `destination_port_ranges`
    - `source_address_prefixes`
    - `destination_address_prefixes`
  - Route tables with configurable routes
  - Subnet-to-route table associations
  - Optional Virtual Network (VNet) peering support