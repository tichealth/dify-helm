terraform {
  required_version = ">= 1.5.0"

  backend "azurerm" {
    # Configure via: terraform init -reconfigure -backend-config=backend.azurerm.tfvars
    # Or in CI: -backend-config=resource_group_name=... -backend-config=storage_account_name=... etc.
    # Required: resource_group_name, storage_account_name, container_name, key, access_key
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
    # NOTE: Kubernetes and Helm providers removed - using Helm directly via deploy.sh
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}

