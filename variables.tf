variable "organization" {
  description = "TFE organization name"
  type        = string
}

variable "tfe_token" {
  description = "TFE API token for authentication"
  type        = string
  sensitive   = true
}

variable "tfe_hostname" {
  description = "TFE hostname for the organization"
  type        = string
}

variable "idp_cert_path" {
  description = "Path to the IdP certificate file for SAML SSO"
  type        = string
  default     = "./certs/azure-ad-certificate.cer"
}

variable "projects" {
  description = "Map of projects to create"
  type = map(object({
    description = string
    team_access = optional(map(object({
      access = string
      project_access = optional(object({
        settings      = optional(string)
        teams         = optional(string)
        variable_sets = optional(string)
      }))
      workspace_access = optional(object({
        create           = optional(bool)
        locking          = optional(bool)
        delete           = optional(bool)
        move             = optional(bool)
        policy_overrides = optional(bool)
        runs             = optional(string)
        run_tasks        = optional(bool)
        sentinel_mocks   = optional(string)
        state_versions   = optional(string)
        variables        = optional(string)
      }))
    })))
  }))

  validation {
    condition = alltrue([
      for project_key, project in var.projects : alltrue([
        for team_name, team_config in coalesce(project.team_access, {}) :
        contains(["admin", "maintain", "write", "read", "custom"], team_config.access)
      ])
    ])
    error_message = "The 'access' field in team_access must be one of: admin, maintain, write, read, or custom."
  }
  default = {
    "app-1" = {
      description = "App 1 Project"
      team_access = {
        "Hashicorp" = {
          access = "admin"
        }
        "Developers" = {
          access = "custom"
          project_access = {
            settings      = "read"
            teams         = "read"
            variable_sets = "read"
          }
          workspace_access = {
            create           = true
            locking          = true
            delete           = true
            move             = true
            policy_overrides = false
            runs             = "apply"
            run_tasks        = true
            sentinel_mocks   = "read"
            state_versions   = "write"
            variables        = "write"
          }
        }
      }
    }
    "app-2" = {
      description = "App 2 Project"
      team_access = {
        "Hashicorp" = {
          access = "admin"
        }
        "Developers" = {
          access = "admin"
        }
      }
    }
  }
}

variable "workspaces" {
  description = "Map of workspaces to create with VCS configuration"
  type = map(object({
    project_key = string
    environment = string # dev, sta, pro...
    app_type    = string # backend, frontend...
    local_variables = optional(map(object({
      value       = string
      category    = string
      description = optional(string)
      hcl         = optional(bool, false)
      sensitive   = optional(bool, false)
    })), {}) # Optional local variables for the workspace
    team_access = optional(map(object({
      access = optional(string)
      permissions = optional(object({
        runs              = string
        variables         = string
        state_versions    = string
        sentinel_mocks    = string
        workspace_locking = bool
        run_tasks         = bool
      }))
    })), {}) # Optional team access configuration for the workspace
  }))

  default = {
    "dev-app-1-backend" = {
      project_key = "app-1"
      environment = "dev"
      app_type    = "backend"
      local_variables = {
        "command" = {
          value       = "az account show"
          category    = "terraform"
          description = "An example variable for the dev backend workspace"
          hcl         = false
          sensitive   = false
        }
      }
      team_access = {
        "Developers" = {
          access = "admin"
        }
      }
    }
    "sta-app-1-backend" = {
      project_key = "app-1"
      environment = "sta"
      app_type    = "backend"
      team_access = {
        "Developers" = {
          access = "write"
        }
      }
    }
    "pro-app-1-backend" = {
      project_key = "app-1"
      environment = "pro"
      app_type    = "backend"
      team_access = {
        "Developers" = {
          permissions = {
            runs              = "read"
            variables         = "read"
            state_versions    = "read"
            sentinel_mocks    = "read"
            workspace_locking = false
            run_tasks         = false
          }
        }
      }
    }
    "dev-app-1-frontend" = {
      project_key = "app-1"
      environment = "dev"
      app_type    = "frontend"
      local_variables = {
        "EXAMPLE_VAR" = {
          value       = "example_value"
          category    = "env"
          description = "An example variable for the dev frontend workspace"
          hcl         = false
          sensitive   = false
        }
      }
    }
    "sta-app-1-frontend" = {
      project_key = "app-1"
      environment = "sta"
      app_type    = "frontend"
    }
    "pro-app-1-frontend" = {
      project_key = "app-1"
      environment = "pro"
      app_type    = "frontend"
    }
    "dev-app-2-backend" = {
      project_key = "app-2"
      environment = "dev"
      app_type    = "backend"
      local_variables = {
        # doesn't work, using data "azurerm_client_config" "current" {} and an output of the client_id in the repository to see the dynamic credentials used
        # "command" = {
        #   value       = "az account show"
        #   category    = "terraform"
        #   description = "An example variable for the dev backend workspace to test dynamic credentials"
        #   hcl         = false
        #   sensitive   = false
        # }
      }
      team_access = {
        "Developers" = {
          access = "admin"
        }
      }
    }
  }
}

variable "vcs_oauth_token_id" {
  description = "OAuth token ID for VCS connection in TFE"
  type        = string
}

variable "vcs_org" {
  description = "VCS organization name"
  type        = string
}

variable "vcs_project" {
  description = "VCS project name"
  type        = string
}

variable "az_client_id" {
  description = "Application (client) ID of the Azure Service Principal used to authenticate to Azure"
  type        = string
}

variable "az_client_secret" {
  description = "Client secret of the Azure Service Principal used to authenticate to Azure"
  type        = string
  sensitive   = true
}

variable "az_subscription_id" {
  type        = string
  description = "Azure Subscription ID where resources will be created"
}

variable "az_tenant_id" {
  type        = string
  description = "Azure Tenant ID for the Subscription"
}

# The policies folder holds the local policies used by the CLI-driven workflow (no VCS needed)
variable "policy_sets" {
  description = "Map of policy sets to create with VCS configuration"
  type = map(object({
    repository           = optional(string)
    description          = string
    assign_to_projects   = optional(set(string), [])
    assign_to_workspaces = optional(set(string), [])
    global               = optional(bool, false)
    kind                 = optional(string, "sentinel")
    # use only if it is a vcs policy_set (so if you add the repository argument too)
    policies_path        = optional(string)
    # the drawback of using non vcs-managed policies is that you can only upload a file for the policy instead of mapping a whole repo (as  you can do with vcs)
    # so no sentinel modules created by others, pre-created functions, etc. Everything needs to be on that file
    policies             = optional(map(object({
      description = optional(string)
      policy_path = string # path to the .sentinel/.rego file
      enforcement_level = string # advisory | soft-mandatory | hard-mandatory (sentinel) or advisory | mandatory (opa) (validation done in the module)
    })))
    exclude_workspaces   = optional(set(string), []) # add only if the policy is global
    exclude_projects     = optional(set(string), []) # add only if the policy is global
  }))
  default = {
    # "policy-library-azure-compute-terraform" = {
    #   repository       = "policy-library-azure-compute-terraform"
    #   description      = "Azure Compute Terraform Policy Library"
    #   global           = true # assigned to all projects
    #   exclude_projects = ["tfe-management"]
    # }
    # "policy-library-azure-networking-terraform" = {
    #   repository           = "policy-library-azure-networking-terraform"
    #   description          = "Azure Networking Terraform Policy Library"
    #   assign_to_projects   = []
    #   assign_to_workspaces = ["dev-app-1-backend"]
    # }
    # "policy-library-azure-storage-terraform" = {
    #   repository           = "policy-library-azure-storage-terraform"
    #   description          = "Azure Storage Terraform Policy Library"
    #   assign_to_projects   = ["app-2"]
    #   assign_to_workspaces = []
    # }
    "policy-null-resource-local-exec-block" = {
      description = "Blocks local-exec provisioners on null_resource"
      global = true
      policies = {
        "prevent-local-exec-on-null-resources" = {
          description = "Blocks local-exec provisioners on null_resource"
          policy_path = "./policies/no-null-resource-local-exec-block/prevent-local-exec-on-null-resources.sentinel"
          enforcement_level = "soft-mandatory"
        }
      }
    }
  }

  validation {
    condition = alltrue([
      for k, v in var.policy_sets :
      v.global || (length(v.exclude_projects) == 0 && length(v.exclude_workspaces) == 0)
    ])

    error_message = "exclude_projects/exclude_workspaces can only be set when global = true."
  }
}

variable "teams" {
  description = "Map of teams to create, keyed by team name"
  type = map(object({
    visibility   = optional(string, "organization")
    sso_team_id  = optional(string)

    organization_access = optional(object({
      access_secret_teams         = optional(bool, false)
      delegate_policy_overrides   = optional(bool, false)
      manage_agent_pools          = optional(bool, false)
      manage_membership           = optional(bool, false)
      manage_modules              = optional(bool, false)
      manage_organization_access  = optional(bool, false)
      manage_policies             = optional(bool, false)
      manage_policy_overrides     = optional(bool, false)
      manage_projects             = optional(bool, false)
      manage_providers            = optional(bool, false)
      manage_run_tasks            = optional(bool, false)
      manage_teams                = optional(bool, false)
      manage_vcs_settings         = optional(bool, false)
      manage_workspaces           = optional(bool, false)
      read_projects               = optional(bool, false)
      read_workspaces             = optional(bool, false)
    }))

    organization_member_ids = optional(set(string), [])
  }))
  default = {
    "Admin" = {
      organization_access = {
        manage_organization_access = true
        manage_membership          = true
        manage_teams               = true
      }
    }
    "Developers" = {
      organization_access = {
        manage_workspaces = true
        manage_projects   = true
      }
    }
    "Hashicorp" = {
      sso_team_id = "<entra_group_object_id>" # the rest should also have this but not added for testing purposes
      organization_access = {
        read_projects   = true
        read_workspaces = true
      }
    }
  }
}

