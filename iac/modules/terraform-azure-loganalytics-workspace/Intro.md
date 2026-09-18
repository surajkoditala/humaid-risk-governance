## Introduction

This module provisions an **Azure Log Analytics Workspace** with an optional **Application Insights** instance for centralized observability, telemetry, and log management.

---

## 📘 Overview

This module enables:

- **Azure Log Analytics Workspace** deployment with configurable SKU, retention period, daily ingestion quota, and capacity reservation
- **Application Insights** integration for APM and telemetry, linked to the Log Analytics Workspace; supports custom application type, sampling percentage, daily data cap, and IP masking controls
- **Internet ingestion and query controls** to restrict or allow public access to the workspace
- **Local authentication toggle** to enforce Azure Active Directory-only access
- **Customer-managed key (CMK)** enforcement for query management
- **Managed identity** support for both system-assigned and user-assigned identities
- **Diagnostic settings** to route the workspace's own logs and metrics to another Log Analytics workspace, Storage Account, or Event Hub
- **Role assignments (RBAC)** for fine-grained access control on the workspace
- **Resource locks** to protect against accidental deletion or modification
- **Standard naming convention** (`log-<product>-<env>-<index>` / `appi-<product>-<env>-<index>`) with optional custom name override
- **Required tag enforcement** via input validation for `business_unit`, `customer`, `environment`, `product`, `owner`, and `region`
