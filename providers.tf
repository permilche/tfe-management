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
  hostname = var.tfe_hostname
  token    = var.tfe_token
}

provider "azurerm" {
  // use_cli should be set to false to yield more accurate error messages on auth failure.
  use_cli              = false
  // use_oidc must be explicitly set to true when using multiple configurations.
  use_oidc             = true
  alias                = "SUBSCRIPTION_A"
  client_id_file_path  = var.tfc_azure_dynamic_credentials.aliases["SUBSCRIPTION_A"].client_id_file_path
  oidc_token_file_path = var.tfc_azure_dynamic_credentials.aliases["SUBSCRIPTION_A"].oidc_token_file_path
  subscription_id      = var.az_subscription_id_subscription_a
  tenant_id            = var.az_tenant_id
  features {}
}

provider "azurerm" {
  // use_cli should be set to false to yield more accurate error messages on auth failure.
  use_cli              = false
  // use_oidc must be explicitly set to true when using multiple configurations.
  use_oidc             = true
  alias                = "SUBSCRIPTION_B"
  client_id_file_path  = var.tfc_azure_dynamic_credentials.aliases["SUBSCRIPTION_B"].client_id_file_path
  oidc_token_file_path = var.tfc_azure_dynamic_credentials.aliases["SUBSCRIPTION_B"].oidc_token_file_path
  subscription_id      = var.az_subscription_id_subscription_b
  tenant_id            = var.az_tenant_id
  features {}
}

# azuread is tenant-scoped, no alias so modules inherit it without a providers passthrough.
# Bootstrap injects only tagged env vars (ARM_TENANT_ID_SUBSCRIPTION_A etc.), not bare
# ARM_CLIENT_ID / ARM_TENANT_ID, so we must wire OIDC explicitly using the file paths
# from tfc_azure_dynamic_credentials. SUBSCRIPTION_A is used since both subscriptions
# share the same tenant.
provider "azuread" {
  // use_cli should be set to false to yield more accurate error messages on auth failure.
  use_cli              = false
  // use_oidc must be explicitly set to true when using multiple configurations.
  use_oidc             = true
  client_id_file_path  = var.tfc_azure_dynamic_credentials.aliases["SUBSCRIPTION_A"].client_id_file_path
  oidc_token_file_path = var.tfc_azure_dynamic_credentials.aliases["SUBSCRIPTION_A"].oidc_token_file_path
  tenant_id            = var.az_tenant_id
}