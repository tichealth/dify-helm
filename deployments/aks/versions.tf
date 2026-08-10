terraform {
  required_version = ">= 1.5.0"

  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.57.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.7.2"
    }
    null = {
      source  = "hashicorp/null"
      version = "= 3.2.4"
    }
    time = {
      source  = "hashicorp/time"
      version = "= 0.13.1"
    }
    # NOTE: Kubernetes and Helm providers removed - using Helm directly via deploy.sh
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}
