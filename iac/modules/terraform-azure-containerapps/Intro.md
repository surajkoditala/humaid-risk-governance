## Introduction

This Terraform module provisions an **Azure Container App** in a flexible, and secure manner.

## 📘 Overview

This module enables:

- Deployment of an Azure Container App with revision support
- Fine-grained control over container templates, init containers, scale rules, and probes
- Support for both **System Assigned** and **User Assigned** managed identities
- Ingress configuration with HTTPS, transport modes, and traffic splitting
- Optional private container registry integration (ACR) with identity support
- Volume and volume mount support for persistent data use cases
