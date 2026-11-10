# SSO and SCIM Configuration with EntraID
module "saml_sso_scim" {
  source  = "app.terraform.io/<organization_name>/saml-sso-and-scim/tfe" # IMPORTANT: cannot use variables there, so app.terraform.io (HCP Terraform FQDN) and the organization name must be hardcoded. Update them for your environment (self-hosted TFE: use your own FQDN)
  version = "0.0.5"

  idp_cert         = file(var.idp_cert_path)
  # Replace <tenant_id> with your Microsoft Entra tenant ID (not a secret, but specific to your environment)
  sso_endpoint_url = "https://login.microsoftonline.com/<tenant_id>/saml2"
  slo_endpoint_url = "https://login.microsoftonline.com/<tenant_id>/saml2"

  # SAML Configuration
  provider_type           = "entra"
  team_management_enabled = false
  authn_requests_signed   = false
  want_assertions_signed  = false
  attr_username           = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"
  # managed through SCIM, so no need to map groups in SAML assertion
  #   attr_groups                = "MemberOf"
  #   site_admin_role            = "site-admins"
  sso_api_token_session_timeout = 1209600 # 14 days

  # SCIM Configuration
  enable_scim            = true
  organization           = var.organization
  scim_token_description = "SCIM token for Azure Entra ID"

  # IMPORTANT: uncomment after applying first and reapply (read the README.md for a deeper explanation: Dual-apply approach)
  # scim_teams = [
  #   {
  #     group_name = "Hashicorp"
  #     team_name  = "Hashicorp"
  #     organization_access = {
  #       manage_organization_access = true
  #       manage_membership          = true
  #       manage_teams               = true
  #     }
  #   },
  #   {
  #     group_name = "developers"
  #     team_name  = "Developers"
  #     organization_access = {
  #       manage_workspaces = true
  #       manage_projects   = true
  #     }
  #   },
  # ]

}

# Projects, keeping things DRY with for_each
module "projects" {
  source   = "app.terraform.io/<organization_name>/project/tfe" # IMPORTANT: cannot use variables there, so app.terraform.io (HCP Terraform FQDN) and the organization name must be hardcoded. Update them for your environment (self-hosted TFE: use your own FQDN)
  version  = "0.0.2"
  for_each = var.projects

  organization = var.organization
  name         = each.key
  description  = each.value.description
  # team_access  = local.project_team_access[each.key]
}

# Workspaces, keeping things DRY with for_each and VCS workflow (local mapping of the environment to branch)
locals {
  # Map environment to branch
  env_to_branch = {
    dev = "develop"
    sta = "staging"
    pro = "main"
  }
  
  # no need to treat null workspace.team_access because it is {} by default in the variable definition
  # IMPORTANT: uncomment after applying first and reapply (read the README.md for a deeper explanation: Dual-apply approach)
  # workspace_team_access = {
  #   for workspace_name, workspace in var.workspaces : workspace_name => {
  #     for team_name, config in workspace.team_access : team_name => merge(
  #       config,
  #       {
  #         team_id = module.saml_sso_scim.scim_group_mappings[team_name].team_id
  #       }
  #     )
  #   }
  # }

  # project_team_access = {
  #   for project_name, project in var.projects : project_name => {
  #     for team_name, config in project.team_access : team_name => merge(
  #       config,
  #       {
  #         team_id = module.saml_sso_scim.scim_group_mappings[team_name].team_id
  #       }
  #     )
  #   }
  # }
}

module "workspaces" {
  source  = "app.terraform.io/<organization_name>/workspace/tfe" # IMPORTANT: cannot use variables there, so app.terraform.io (HCP Terraform FQDN) and the organization name must be hardcoded. Update them for your environment (self-hosted TFE: use your own FQDN)
  version = "0.0.1"

  for_each = var.workspaces

  organization = var.organization
  name         = each.key
  description  = "${each.key} workspace"
  project_id   = module.projects[each.value.project_key].id

  # VCS configuration
  vcs_repo = {
    vcs_provider     = "azure_devops"
    vcs_organization = var.vcs_org
    vcs_project      = var.vcs_project
    repository       = "${each.value.project_key}-${each.value.app_type}"
    branch           = local.env_to_branch[each.value.environment]
    oauth_token_id   = var.vcs_oauth_token_id
  }

  variables = each.value.local_variables != null ? each.value.local_variables : {}

  # IMPORTANT: uncomment after applying first and reapply (read the README.md for a deeper explanation: Dual-apply approach)
  # team_access = local.workspace_team_access[each.key]
}

# Variable Set with AZURE_CREDENTIALS applied to all app projects (can filter projects accordingly)
module "varset_azure_credentials" {
  source  = "app.terraform.io/<organization_name>/variable-set/tfe" # IMPORTANT: cannot use variables there, so app.terraform.io (HCP Terraform FQDN) and the organization name must be hardcoded. Update them for your environment (self-hosted TFE: use your own FQDN)
  version = "0.0.5"

  organization = var.organization
  name         = "Dynamic Azure Credentials Variable Set"
  description  = "Contains the environment variables to use Azure dynamiccredentials for all application projects"

  project_ids_map = { for project_key, project in var.projects :
    project_key => module.projects[project_key].id
  }

  variables = {
    TFC_AZURE_PROVIDER_AUTH = {
      category  = "env"
      value     = "true"
      #sensitive = true
    }
    TFC_AZURE_RUN_CLIENT_ID = {
      category  = "env"
      value     = var.tfc_application_client_id # azuread_application.tfc_application.client_id
    }
    ARM_SUBSCRIPTION_ID = {
      category  = "env"
      value     = var.az_subscription_id
    }
    ARM_TENANT_ID  = {
      category  = "env"
      value     = var.az_tenant_id
    }
  }
}

locals {
  dynamic_credentials_allowed_workspaces = merge([
    for workspace_name, cfg in var.workspaces : {
      for phase in cfg.dynamic_credentials_enabled :
      "${cfg.environment}-${cfg.project_key}-${cfg.app_type}-${phase}" => { # we could have just done "${workspace_name}-${phase}" but this is more explicit and readable and we make sure every object is different and unique since we could have the same workspace name in different projects and environments
        organization = var.organization
        project      = cfg.project_key
        workspace    = workspace_name
        run_phase    = phase
      }
    }
  ]...)
  
# These commented debug locals help you visualize the structure of the dynamic credentials allowed workspaces mapping and how it transforms to reach a single map(object) with the structure we need for our module input variable
# Uncomment them and run `terraform console` to see the output and understand how the transformation works
#   debug1 = {for workspace_name, cfg in var.workspaces : 
#       "${cfg.environment}-${cfg.project_key}-${cfg.app_type}" => {
#         organization = var.organization
#         project      = cfg.project_key
#         workspace    = workspace_name
#       }}
#   debug2 = [for workspace_name, cfg in var.workspaces : {
#       for phase in cfg.dynamic_credentials_enabled :
#       "${cfg.environment}-${cfg.project_key}-${cfg.app_type}-${phase}" => {
#         organization = var.organization
#         project      = cfg.project_key
#         workspace    = workspace_name
#         run_phase    = phase
#       }
#     }]
#     debug3 = merge([
#       for workspace_name, cfg in var.workspaces : {
#         for phase in cfg.dynamic_credentials_enabled :
#         "${cfg.environment}-${cfg.project_key}-${cfg.app_type}-${phase}" => {
#           organization = var.organization
#           project      = cfg.project_key
#           workspace    = workspace_name
#           run_phase    = phase
#         }
#       }
#     ]...)
}

module "dynamic_credentials_azure_management" {
  source  = "app.terraform.io/<organization_name>/dynamic-credentials-azure-management/tfe" # IMPORTANT: cannot use variables there, so app.terraform.io (HCP Terraform FQDN) and the organization name must be hardcoded. Update them for your environment (self-hosted TFE: use your own FQDN)
  version = "0.0.5"

  allowed_workspaces        = local.dynamic_credentials_allowed_workspaces
  tfc_application_id        = var.tfc_application_id
  tfc_hostname              = var.tfe_hostname
}

locals {
  all_project_ids = merge(local.external_project_ids,            # external projects like tfe-management
  { for name, project in module.projects : name => project.id }) # all projects created here
}

module "policy_sets" {
  source  = "app.terraform.io/<organization_name>/policy-set/tfe" # IMPORTANT: cannot use variables there, so app.terraform.io (HCP Terraform FQDN) and the organization name must be hardcoded. Update them for your environment (self-hosted TFE: use your own FQDN)
  version = "0.0.2"

  for_each = var.policy_sets

  name         = each.key
  description  = each.value.description
  organization = var.organization
  global       = each.value.global
  kind         = each.value.kind

  vcs_repo = {
    identifier         = "${var.vcs_org}/${var.vcs_project}/_git/${each.value.repository}" # because we are working with Azure Devops. We could do the same logic as in workspaces to detect the identifier in the module as an upgrade
    branch             = "main"
    # ingress_submodules = false
    oauth_token_id     = var.vcs_oauth_token_id
  }

  # assign to projects based on configuration
  project_ids = toset([
    for project_name in each.value.assign_to_projects :
    local.all_project_ids[project_name]
  ])

  # assign to workspaces based on configuration
  workspace_ids = toset([
    for workspace_name in each.value.assign_to_workspaces :
    module.workspaces[workspace_name].id
  ])

  # assign to projects based on configuration
   # no need to check if it is a global policy set because that is done already in the module
  # I have added a validation though in the policy_sets variable to make it more explicit
  project_exclusion_ids = toset([
    for project_name in each.value.exclude_projects :
    local.all_project_ids[project_name]
  ])

  # assign to workspaces based on configuration
  # no need to check if it is a global policy set because that is done already in the module
  # I have added a validation though in the policy_sets variable to make it more explicit
  workspace_exclusion_ids = toset([
    for workspace_name in each.value.exclude_workspaces :
    module.workspaces[workspace_name].id
  ])
}

# Organization Run Task (Post-Plan)
# module "run_task_post_plan" {
#   source = "app.terraform.io/<organization_name>/run-task/tfe" # IMPORTANT: cannot use variables there, so app.terraform.io (HCP Terraform FQDN) and the organization name must be hardcoded; update them for your environment (self-hosted TFE: use your own FQDN)
#   version = "0.0.1"

#   organization = var.organization
#   name         = "post-plan-echo"
#   url          = "https://mockvalue.com/post-plan-echo"
#   description  = "Post-plan run task that echoes a message"
#   enabled      = true
# }
