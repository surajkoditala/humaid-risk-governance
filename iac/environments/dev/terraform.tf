terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0, < 5.0.0"
    }
  }
  required_version = "~> 1.8"

  backend "azurerm" {
    resource_group_name  = "rg-gh-tf-dev"
    storage_account_name = "sterctfstatedev01"
    container_name       = "tfstate"
    key                  = "dev/terraform.tfstate"
  }
}