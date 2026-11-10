output "scim_token" {
  value     = module.saml_sso_scim.scim_token
  sensitive = true
}

output "scim_token_expiration" {
  value = module.saml_sso_scim.scim_token_expiration
  description = "CAUTION: The expiration date of the SCIM token. REMEMBER to update it in your identity provider before it expires to avoid service disruption"
}

output "projects" {
  value = {
    for key, project in module.projects : key => project.id
  }
}

output "workspaces" {
  value = {
    for key, workspace in module.workspaces : key => workspace.id
  }
}

output "variable_set_azure_credentials_subscription_a" {
  value = module.varset_azure_credentials_subscription_a.id
}

output "variable_set_azure_credentials_subscription_b" {
  value = module.varset_azure_credentials_subscription_b.id
}
