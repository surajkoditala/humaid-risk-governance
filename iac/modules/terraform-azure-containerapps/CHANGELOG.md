# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v1.0.0] - 2027-07-09
### Added
- Initial release of the module to create:
  - Azure Container App resource with:
    - Container and Init container templates
    - Liveness and Startup probes
    - Volume and Volume Mount configuration
    - Custom, HTTP, and TCP scale rules
    - Secure secret injection via Key Vault or inline values
    - Registry integration using system or user-assigned identities
    - Ingress block with transport, port, HTTPS, client cert, and traffic weights
  - Support for:
    - System-assigned managed identity
    - User-assigned managed identities
    - Dynamic identity type selection via locals
  - Output for:
    - Fully qualified container app name
    - System assigned principal ID (for role assignments)
  - Optional lock support for resources
  - Optional role assignments for system-assigned identity
  - Optional CORS policy
  - Maximum inactive revisions for a container app
  - Added `ignore_changes` to prevent Terraform from updating the container app on image version changes
