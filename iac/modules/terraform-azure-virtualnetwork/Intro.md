## Introduction

This Terraform module is designed to provision a robust, and secure Azure Virtual Network (VNet) architecture. It encapsulates the creation of VNets, subnets, DNS servers, network security groups (NSGs), route tables, and their associations. It is built to quickly roll out and manage consistent networking configurations across environments.

## 📘 Overview

This module enables:

- Creation of a Virtual Network with custom address spaces
- Optional DNS server configuration per VNet
- Creation of multiple subnets using `for_each`, including optional service delegation
- NSG creation and security rule definitions using `dynamic` blocks with `try()` for optional attributes
- NSG-to-subnet associations
- Route table provisioning using `for_each`, with optional routes
- Subnet-to-route table associations
- Optional DDoS protection plan integration
