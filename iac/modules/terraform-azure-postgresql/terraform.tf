terraform {

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  required_version = ">= 1.9, < 2.0"
}