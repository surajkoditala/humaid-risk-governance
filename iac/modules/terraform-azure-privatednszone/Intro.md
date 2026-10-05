## Introduction

This module provisions an **Azure Private DNS Zone** with virtual network links for private name resolution, along with optional access control and resource protection.

---

## 📘 Overview

This module enables:

- **Azure Private DNS Zone** deployment with a configurable domain name (e.g., `privatelink.vaultcore.azure.net`, `privatelink.postgres.database.azure.com`)
- **Virtual Network links** to one or more VNets so resources in linked networks can resolve records in the zone
- **Resource locks** to protect against accidental deletion or modification
- **Role assignments (RBAC)** for fine-grained access control on the zone
- **Resource ID output** for referencing the zone from other modules (e.g., private endpoint DNS zone groups)
