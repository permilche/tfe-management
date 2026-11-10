terraform {
  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.79.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.60"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.9.0"
    }
  }
}

provider "tfe" {
  hostname        = var.tfe_hostname
  token           = var.tfe_token
}

provider "azurerm" {
  features {}
  subscription_id = var.az_subscription_id
}

provider "azuread" {
}