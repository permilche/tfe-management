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
      access  = string
      project_access  = optional(object({
        settings      = optional(string)
        teams         = optional(string)
        variable_sets = optional(string)
      }))
      workspace_access   = optional(object({
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
    # Map of subscription name to set of run phases that should use dynamic credentials.
    # Key must match a known subscription name (e.g. "subscription-a", "subscription-b").
    # Value is the set of run phases: "plan", "apply", or both.
    # Omit entirely (or leave as {}) if this workspace does not use dynamic credentials.
    # Example: { "subscription-a" = ["plan", "apply"] }
    dynamic_credentials = optional(map(set(string)), {})
  }))

  default = {
    "dev-app-1-backend" = {
      project_key = "app-1"
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
      dynamic_credentials = { "subscription-a" = ["plan", "apply"] }
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
      dynamic_credentials = { "subscription-b" = ["plan", "apply"] }
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

# Required by TFE to supply OIDC token and client ID file paths at runtime for dynamic provider credentials.
# DO NOT change the variable name or type, TFE injects this automatically when dynamic credentials are configured.
# See: https://developer.hashicorp.com/terraform/enterprise/dynamic-provider-credentials/azure-configuration#required-terraform-variable
variable "tfc_azure_dynamic_credentials" {
  description = "Object containing Azure dynamic credentials configuration supplied by TFE at runtime"
  type = object({
    default = optional(object({
      client_id_file_path  = string
      oidc_token_file_path = string
    }))
    aliases = map(object({
      client_id_file_path  = string
      oidc_token_file_path = string
    }))
  })
}

# Dynamic credentials configuration to inject on the workspaces to identify what App Registration to use

# subscription-a
variable "tfc_application_id_subscription_a" {
  description = "The application (object) ID of the Azure application registration used to create the Credential Identity Federation for managed workspaces in subscription-a (used in the dynamic-credentials-azure-management module)"
  type        = string
}

variable "tfc_application_client_id_subscription_a" {
  description = "Application (client) ID of the Azure App Registration used for TFC dynamic credentials in managed workspaces in subscription-a (used in the variable-set module)"
  type        = string
}

variable "az_subscription_id_subscription_a" {
  type        = string
  description = "Azure Subscription ID for subscription-a"
}

# subscription-b
variable "tfc_application_id_subscription_b" {
  description = "The application (object) ID of the Azure application registration used to create the Credential Identity Federation for managed workspaces in subscription-b (used in the dynamic-credentials-azure-management module)"
  type        = string
}

variable "tfc_application_client_id_subscription_b" {
  description = "Application (client) ID of the Azure App Registration used for TFC dynamic credentials in managed workspaces in subscription-b (used in the variable-set module)"
  type        = string
}

variable "az_subscription_id_subscription_b" {
  type        = string
  description = "Azure Subscription ID for subscription-b"
}

# Shared
variable "az_tenant_id" {
  type        = string
  description = "Azure Tenant ID for the Subscription"
}

variable "policy_sets" {
  description = "Map of policy sets to create with VCS configuration"
  type = map(object({
    repository           = string
    description          = string
    assign_to_projects   = optional(set(string), [])
    assign_to_workspaces = optional(set(string), [])
    global               = optional(bool, false)
    kind                 = optional(string, "sentinel")
    exclude_workspaces   = optional(set(string), []) # add only if the policy is global
    exclude_projects     = optional(set(string), []) # add only if the policy is global
  }))
  default = {
    "policy-library-azure-compute-terraform" = {
      repository           = "policy-library-azure-compute-terraform"
      description          = "Azure Compute Terraform Policy Library"
      global               = true  # assigned to all projects
      exclude_projects     = ["tfe-management"]
    }
    "policy-library-azure-networking-terraform" = {
      repository           = "policy-library-azure-networking-terraform"
      description          = "Azure Networking Terraform Policy Library"
      assign_to_projects   = []
      assign_to_workspaces = ["dev-app-1-backend"]
    }
    "policy-library-azure-storage-terraform" = {
      repository           = "policy-library-azure-storage-terraform"
      description          = "Azure Storage Terraform Policy Library"
      assign_to_projects   = ["app-2"]
      assign_to_workspaces = []
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
