## Introduction

This module provisions an **Azure Container Registry (ACR)** with support for private networking, geo-replication, customer-managed encryption, network access controls, and observability.

---

## 📘 Overview

This module enables:

- **Azure Container Registry** deployment with configurable SKU (`Basic`, `Standard`, `Premium`) and admin access controls
- **Premium SKU features** — zone redundancy, untagged image retention policy, and data endpoint support
- **Geo-replication** across multiple Azure regions with per-replica zone redundancy and regional endpoint configuration
- **Customer-managed key (CMK)** encryption via Azure Key Vault, requiring a user-assigned managed identity
- **Managed identity** support for both system-assigned and user-assigned identities
- **Network rule set** for IP-based access restrictions with configurable default action (requires Premium SKU)
- **Private endpoints** for secure, private network access to the registry; supports managed and unmanaged DNS zone group modes
- **Private DNS zone integration** for name resolution of private endpoints
- **Application Security Group (ASG) associations** on private endpoints
- **Anonymous pull** and **export policy** controls for registry access governance
- **Quarantine policy** and **content trust (trust policy)** for image security
- **Diagnostic settings** to route registry logs and metrics to Log Analytics, Storage Account, or Event Hub
- **Role assignments (RBAC)** for fine-grained access control on the registry; supports role name or full definition ID, conditions, and delegated managed identity
- **Resource locks** to protect against accidental deletion or modification
- **Standard naming convention** (`cr<product><env><index>`) with optional custom name override; name validated to 5–50 lowercase alphanumeric characters
- **Required tag enforcement** via input validation for `business_unit`, `customer`, `environment`, `product`, `owner`, and `region`
