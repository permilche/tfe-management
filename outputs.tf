# output "scim_token" {
#   value     = module.saml_sso_scim.scim_token
#   sensitive = true
# }

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

output "variable_set" {
  value = module.varset_azure_credentials.id
}
