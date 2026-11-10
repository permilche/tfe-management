# SSO and SCIM Configuration with EntraID
module "saml_sso_scim" {
  source = "app.terraform.io/<organization_name>/saml-sso-and-scim/tfe" # IMPORTANT: cannot use variables there, so app.terraform.io (HCP Terraform FQDN) and the organization name must be hardcoded. Update them for your environment (self-hosted TFE: use your own FQDN)
  # version = "0.0.5"
  # should always pin the version to avoid unexpected changes, but for the sake of testing and development, we can leave it unpinned (TFE will always use the latest version of the module in the private registry)

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

  scim_token_rotation_days   = 365
}

# Projects, keeping things DRY with for_each
module "projects" {
  source = "app.terraform.io/<organization_name>/project/tfe" # IMPORTANT: cannot use variables there, so app.terraform.io (HCP Terraform FQDN) and the organization name must be hardcoded. Update them for your environment (self-hosted TFE: use your own FQDN)
  # version  = "0.0.2"
  # should always pin the version to avoid unexpected changes, but for the sake of testing and development, we can leave it unpinned (TFE will always use the latest version of the module in the private registry)

  for_each = var.projects

  organization = var.organization
  name         = each.key
  description  = each.value.description

  # IMPORTANT: uncomment after applying first and reapply (read the README.md for a deeper explanation: Dual-apply approach)
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
  source = "app.terraform.io/<organization_name>/workspace/tfe" # IMPORTANT: cannot use variables there, so app.terraform.io (HCP Terraform FQDN) and the organization name must be hardcoded. Update them for your environment (self-hosted TFE: use your own FQDN)
  # version = "0.0.1"
  # should always pin the version to avoid unexpected changes, but for the sake of testing and development, we can leave it unpinned (TFE will always use the latest version of the module in the private registry)

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

locals {
  # Maps the human-readable subscription name used in var.workspaces dynamic_credentials
  # to the provider alias format (uppercase, hyphens → underscores) used in providers.tf.
  # Initial manual mapping kept commented for reference/manual override if yu don't want to use the standard convention chosen
  # I encourage you to update it accordingly to your standards instead of mapping it manually:
  # subscription_to_alias = {
  #   "subscription-a" = "SUBSCRIPTION_A"
  #   "subscription-b" = "SUBSCRIPTION_B"
  # }

  # Derive all unique subscription names declared across workspaces
  all_subscriptions = distinct(flatten([
    for workspace in values(var.workspaces) : keys(workspace.dynamic_credentials)
  ]))

  # Standard convention for provider aliases: uppercase subscription name and replace hyphens with underscores
  subscription_to_alias = {
    for sub in local.all_subscriptions : sub => upper(replace(sub, "-", "_")) # Convention chosen
  }

  # For each subscription, build the map of workspace+phase entries that have opted in.
  # Key format: "{environment}-{project_key}-{app_type}-{phase}" — explicit and unique even
  # if the same workspace name appears in multiple projects.
  dynamic_credentials_by_subscription = {
    for sub in keys(local.subscription_to_alias) : sub => merge([
      for workspace_name, cfg in var.workspaces : {
        for phase in lookup(cfg.dynamic_credentials, sub, []) :
        "${cfg.environment}-${cfg.project_key}-${cfg.app_type}-${phase}" => {
          organization = var.organization
          project      = cfg.project_key
          workspace    = workspace_name
          run_phase    = phase
        }
      }
    ]...)
  }

  # For each subscription, collect the IDs of workspaces that have opted in.
  # Used to scope variable sets to only the workspaces that actually need them.
  varset_workspace_ids_by_subscription = {
    for sub in keys(local.subscription_to_alias) : sub => {
      for workspace_name, cfg in var.workspaces :
      workspace_name => module.workspaces[workspace_name].id
      if length(lookup(cfg.dynamic_credentials, sub, [])) > 0
    }
  }
}

# Variable Set with AZURE_CREDENTIALS for subscription-a subscription.
# Assigned only to the workspaces that have opted into this subscription via dynamic_credentials.
module "varset_azure_credentials_subscription_a" {
  source = "app.terraform.io/<organization_name>/variable-set/tfe" # IMPORTANT: cannot use variables there, so app.terraform.io (HCP Terraform FQDN) and the organization name must be hardcoded. Update them for your environment (self-hosted TFE: use your own FQDN)
  # version = "0.0.5"
  # should always pin the version to avoid unexpected changes, but for the sake of testing and development, we can leave it unpinned (TFE will always use the latest version of the module in the private registry)

  organization = var.organization
  name         = "Dynamic Azure Credentials Variable Set - subscription-a"
  description  = "Contains the environment variables to use Azure dynamic credentials for subscription-a subscription"

  workspace_ids_map = local.varset_workspace_ids_by_subscription["subscription-a"]

  variables = {
    TFC_AZURE_PROVIDER_AUTH = {
      category = "env"
      value    = "true"
    }
    TFC_AZURE_RUN_CLIENT_ID = {
      category = "env"
      value    = var.tfc_application_client_id_subscription_a
    }
    ARM_SUBSCRIPTION_ID = {
      category = "env"
      value    = var.az_subscription_id_subscription_a
    }
    ARM_TENANT_ID = {
      category = "env"
      value    = var.az_tenant_id
    }
  }
}

# Variable Set with AZURE_CREDENTIALS for subscription-b subscription.
# Assigned only to the workspaces that have opted into this subscription via dynamic_credentials.
module "varset_azure_credentials_subscription_b" {
  source  = "app.terraform.io/<organization_name>/variable-set/tfe" # IMPORTANT: cannot use variables there, so app.terraform.io (HCP Terraform FQDN) and the organization name must be hardcoded. Update them for your environment (self-hosted TFE: use your own FQDN)
  version = "0.0.5"

  organization = var.organization
  name         = "Dynamic Azure Credentials Variable Set - subscription-b"
  description  = "Contains the environment variables to use Azure dynamic credentials for subscription-b subscription"

  workspace_ids_map = local.varset_workspace_ids_by_subscription["subscription-b"]

  variables = {
    TFC_AZURE_PROVIDER_AUTH = {
      category = "env"
      value    = "true"
    }
    TFC_AZURE_RUN_CLIENT_ID = {
      category = "env"
      value    = var.tfc_application_client_id_subscription_b
    }
    ARM_SUBSCRIPTION_ID = {
      category = "env"
      value    = var.az_subscription_id_subscription_b
    }
    ARM_TENANT_ID = {
      category = "env"
      value    = var.az_tenant_id
    }
  }
}

# Register federated identity credentials per subscription, only for workspaces that opted in.
# The module uses the default azuread provider (no alias needed, it is tenant-scoped and
# TFE injects ARM_CLIENT_ID / ARM_TENANT_ID as env vars which azuread picks up natively).
module "dynamic_credentials_azure_management_subscription_a" {
  source = "app.terraform.io/<organization_name>/dynamic-credentials-azure-management/tfe" # IMPORTANT: cannot use variables there, so app.terraform.io (HCP Terraform FQDN) and the organization name must be hardcoded. Update them for your environment (self-hosted TFE: use your own FQDN)
  # version = "0.0.5"
  # should always pin the version to avoid unexpected changes, but for the sake of testing and development, we can leave it unpinned (TFE will always use the latest version of the module in the private registry)

  for_each = local.dynamic_credentials_by_subscription["subscription-a"]

  tfc_application_id = var.tfc_application_id_subscription_a
  tfc_hostname       = var.tfe_hostname
  organization       = each.value.organization
  project            = each.value.project
  workspace          = each.value.workspace
  run_phase          = each.value.run_phase
}

module "dynamic_credentials_azure_management_subscription_b" {
  source = "app.terraform.io/<organization_name>/dynamic-credentials-azure-management/tfe" # IMPORTANT: cannot use variables there, so app.terraform.io (HCP Terraform FQDN) and the organization name must be hardcoded. Update them for your environment (self-hosted TFE: use your own FQDN)
  # version = "0.0.5"
  # should always pin the version to avoid unexpected changes, but for the sake of testing and development, we can leave it unpinned (TFE will always use the latest version of the module in the private registry)

  for_each = local.dynamic_credentials_by_subscription["subscription-b"]

  tfc_application_id = var.tfc_application_id_subscription_b
  tfc_hostname       = var.tfe_hostname
  organization       = each.value.organization
  project            = each.value.project
  workspace          = each.value.workspace
  run_phase          = each.value.run_phase
}

# Look up the tfe-management project dynamically. It is created in the tfe-bootstrap layer, not here
data "tfe_project" "tfe_management" {
  name         = "tfe-management"
  organization = var.organization
}

locals {
  all_project_ids = merge(
    { "tfe-management" = data.tfe_project.tfe_management.id },    # external projects like tfe-management
    { for name, project in module.projects : name => project.id } # all projects created here
  )
}

module "policy_sets" {
  source = "app.terraform.io/<organization_name>/policy-set/tfe" # IMPORTANT: cannot use variables there, so app.terraform.io (HCP Terraform FQDN) and the organization name must be hardcoded. Update them for your environment (self-hosted TFE: use your own FQDN)
  # version = "0.0.3"
  # should always pin the version to avoid unexpected changes, but for the sake of testing and development, we can leave it unpinned (TFE will always use the latest version of the module in the private registry)

  for_each = var.policy_sets

  name         = each.key
  description  = each.value.description
  organization = var.organization
  global       = each.value.global
  kind         = each.value.kind

  vcs_repo = {
    identifier = "${var.vcs_org}/${var.vcs_project}/_git/${each.value.repository}" # because we are working with Azure Devops. We could do the same logic as in workspaces to detect the identifier in the module as an upgrade
    branch     = "main"
    # ingress_submodules = false
    oauth_token_id = var.vcs_oauth_token_id
  }

  # assign to projects based on configuration
  project_ids = {
    for project_name in each.value.assign_to_projects :
    project_name => local.all_project_ids[project_name]
  }

  # assign to workspaces based on configuration
  workspace_ids = {
    for workspace_name in each.value.assign_to_workspaces :
    workspace_name => module.workspaces[workspace_name].id
  }

  # assign to projects based on configuration
  # no need to check if it is a global policy set because that is done already in the module
  # I have added a validation though in the policy_sets variable to make it more explicit
  project_exclusion_ids = {
    for project_name in each.value.exclude_projects :
    project_name => local.all_project_ids[project_name]
  }

  # assign to workspaces based on configuration
  # no need to check if it is a global policy set because that is done already in the module
  # I have added a validation though in the policy_sets variable to make it more explicit
  workspace_exclusion_ids = {
    for workspace_name in each.value.exclude_workspaces :
    workspace_name => module.workspaces[workspace_name].id
  }
}

# Organization Run Task (Post-Plan)
# module "run_task_post_plan" {
#   source = "app.terraform.io/<organization_name>/run-task/tfe" # IMPORTANT: cannot use variables there, so app.terraform.io (HCP Terraform FQDN) and the organization name must be hardcoded; update them for your environment (self-hosted TFE: use your own FQDN)
#   version = "0.0.1"
#   should always pin the version to avoid unexpected changes, but for the sake of testing and development, we can leave it unpinned (TFE will always use the latest version of the module in the private registry)


#   organization = var.organization
#   name         = "post-plan-echo"
#   url          = "https://mockvalue.com/post-plan-echo"
#   description  = "Post-plan run task that echoes a message"
#   enabled      = true
# }
