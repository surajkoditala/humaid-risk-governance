## Introduction

This Terraform module provisions an Azure Container App Environment (CAE) in a secure and modular manner. 

## 📘 Overview

This module enables:
- Provisioning of an Azure Container App Environment
- Optional creation of a Log Analytics Workspace for observability
- Configurable workload profiles using `for_each`
- Support for optional Dapr Application Insights connection, mutual TLS
- Optional integration with a delegated subnet (VNet), Internal Load Balancer and Zone Redundancy
