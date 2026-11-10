terraform {
  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.79.0"
    }
  }
}

provider "tfe" {
  hostname = var.tfe_hostname
  token    = var.tfe_token
}