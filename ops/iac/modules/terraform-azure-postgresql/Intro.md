## Introduction

This module provisions an **Azure PostgreSQL Flexible Server** with optional integrations for high availability, security, identity management, observability, and network isolation.

---

## 📘 Overview

This module enables:

- **Azure PostgreSQL Flexible Server** deployment with configurable SKU, version, storage, backup retention, and availability zone placement
- **High availability** support with `ZoneRedundant` or `SameZone` modes and automatic standby provisioning
- **Authentication flexibility** — password-based, Azure Active Directory, or both; supports ephemeral passwords to avoid storing credentials in state
- **Active Directory administrator** assignment for EntraID-based access control
- **Customer-managed keys (CMK)** integration via Azure Key Vault for encryption at rest, including geo-backup key support
- **Managed identity** support for both system-assigned and user-assigned identities
- **Private endpoints** for secure, private network access to the PostgreSQL server
- **Private DNS zone integration** for seamless name resolution of private endpoints
- **Firewall rules** for IP-based access control when public access is required
- **Virtual endpoints** for read/write routing across primary and replica servers
- **Server configuration** parameters for fine-grained PostgreSQL engine tuning
- **Diagnostic settings** to route logs and metrics to Log Analytics, Storage Account, or Event Hub
- **Role assignments (RBAC)** for fine-grained access control on the server and private endpoints
- **Resource locks** to protect against accidental deletion or modification
- **Maintenance window** configuration for controlled update scheduling
- **Geo-redundant backups** with configurable retention (7–35 days)
- **Storage auto-grow** to automatically expand storage as data grows
