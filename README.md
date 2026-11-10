# TFE Management

> **Disclaimer:** this is a personal project and not an official HashiCorp product. It is not officially supported or maintained by HashiCorp, and I share it to help out the community. It comes "as is", without any warranty. There may be errors, and the Terraform, provider or module versions used here may get deprecated or stop working. Please review and test everything outside production before using it, and use it at your own risk. The repository is public and issues and pull requests are welcome, but I review and validate each one myself, so there is no guaranteed response time, no promise to merge, and no support SLA (see [CONTRIBUTING](.github/CONTRIBUTING.md)). All names, IDs and values are examples or placeholders, so never commit credentials. Terraform, HCP Terraform and Terraform Enterprise are trademarks of HashiCorp.

> **Looking for a different setup?** This branch (`single-provider-azure-static-credentials`) uses a static Service Principal secret, the **CLI-driven** workflow for workspaces and policy sets, and local policy sets (see [Workflow used in this branch](#workflow-used-in-this-branch)). Check out the other branches for other configurations: `main` for Azure dynamic credentials (OIDC) with one subscription and the VCS-driven workflow, and `multi-provider-azure-dynamic-credentials` for dynamic credentials across several subscriptions.

This Terraform configuration serves as the **management layer** for the Terraform Enterprise (TFE) organization, enabling complete GitOps-based control of TFE infrastructure. All TFE configuration changes are managed through Infrastructure as Code (IaC), eliminating manual "clickops" in favor of version-controlled, auditable changes.

## Overview

This management module controls all aspects of the TFE organization using the TFE provider, including:

- **Projects and Workspaces**: Organizational structure and execution environments
- **Teams and Permissions**: Access control and team management
- **SSO/SCIM Integration**: Enterprise authentication and user provisioning
- **Variable Sets**: Shared configuration across workspaces
- **Policy Sets**: Sentinel and OPA policy enforcement, from VCS repositories or from local files (Terraform policies may be added later)
- **VCS Integration**: Version control system connections
- **Azure Credentials**: Azure Service Principal client secret shared through a variable set (static credentials)

### Workflow used in this branch

This example does **not** use the VCS-driven workflow for the workspaces and policy sets it manages. It uses the **CLI-driven** one: the managed workspaces have no VCS connection (the `vcs_repo` block of the workspace module is commented out in `main.tf`) and the default policy set reads local files from the [`policies`](policies) folder. The VCS code is kept commented in `main.tf` and `variables.tf` in case you prefer that workflow. This is done on purpose, to show as many configuration examples as possible. Any VCS-related comment or section in this README only applies if you enable the VCS workflow.

### Authentication Method

This branch uses **Azure static credentials with a single provider**: one Service Principal **client secret**, created manually and injected by `tfe-bootstrap` (`single-provider-azure-static-credentials` branch). This repository shares it with the application projects through a variable set (`ARM_CLIENT_ID`, `ARM_CLIENT_SECRET` (sensitive), `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID`). There is **no** dynamic-credentials / federated-credential code in this branch.

- Simple to set up, but the secret is long-lived: it expires and has to be rotated, and it is readable by anything that can run code in the workspaces that receive it. Prefer the `main` (single) or `multi-provider-azure-dynamic-credentials` branch for production.
- Several subscriptions or tenants, and the architecture patterns for them, are covered in the `multi-provider-azure-dynamic-credentials` branch.
- Never commit `az_client_secret`: set it as a sensitive workspace variable (or `TF_VAR_az_client_secret`).

> Authentication currently focuses on **Azure**. Other clouds will come.

## Dependencies and Related Repositories

| Repository | Role |
|------------|------|
| [`tfe-tf-modules`](https://github.com/permilche/tfe-tf-modules) | **Source of the modules** this repository calls (`saml-sso-and-scim`, `project`, `workspace`, `variable-set`, `policy-set`, ...). It is not referenced directly: its modules are published to the private registry by `tfe-private-registry` and consumed from there |
| [`tfe-bootstrap`](https://github.com/permilche/tfe-bootstrap) | **Creates the workspace that runs this repository** (branch `single-provider-azure-static-credentials`), its SSH key and the variables it needs (`az_client_id`, `az_client_secret`, `az_subscription_id`, `az_tenant_id`, `organization`, `tfe_token`, `tfe_hostname`, `vcs_oauth_token_id`, ...) |
| [`tfe-private-registry`](https://github.com/permilche/tfe-private-registry) | **Must be applied first.** It registers the `tfe-tf-modules` modules, and creates their versions through tags, in the private registry that this repository consumes |

## Before You Start: Values to Replace

1. **Registry module sources.** Every module `source` in [`main.tf`](main.tf) is `app.terraform.io/<organization_name>/<module>/tfe`. Replace `<organization_name>` with your organization, and `app.terraform.io` (HCP Terraform) with your own FQDN if you run **self-hosted TFE**. A `source` cannot use variables, so this must be hardcoded. Each line has a comment saying so.
2. **`tfe_hostname`.** Injected by `tfe-bootstrap`: `app.terraform.io` for HCP Terraform, or your FQDN for self-hosted TFE (it must match the FQDN used in the sources).
3. **Module versions.** The `version` arguments are commented out (latest version is used). Pin each one to a version that `tfe-private-registry` has published (tag `<module>-<version>`).
4. **SAML / SCIM.** In `main.tf`, replace `<tenant_id>` in `sso_endpoint_url` and `slo_endpoint_url` with your Microsoft Entra tenant ID. The SAML module also needs the **IdP signing certificate** of your Entra ID enterprise application (`idp_cert`, read from `idp_cert_path`): TFE uses it to verify the signature of the SAML assertions. It is a public certificate and **normally should be committed** to the repository the workspace runs from. Only the author's file name, `certs/azure-ad-certificate.cer`, is git-ignored here, so that a certificate from another environment is not published and others can reuse the repository: save yours under a different name and set `idp_cert_path` (it will then be tracked), or delete that line from `.gitignore` (see [Setup Instructions](#setup-instructions)). The break-glass admin settings of the SAML module are not used by this configuration (they only produce instructions in a module output), so they were removed.
5. **VCS (Azure DevOps).** `vcs_org`, `vcs_project` and the example projects, workspaces and policy sets (`variables.tf` defaults) refer to Azure DevOps repositories that do not exist in your environment. Adapt them.
6. **Teams.** The `Hashicorp` team default in `variables.tf` has `sso_team_id = "<entra_group_object_id>"`: replace it with the object ID of your Entra ID group, or remove the attribute.
7. **Azure values.** `az_client_id`, `az_client_secret`, `az_subscription_id`, `az_tenant_id` are provided by `tfe-bootstrap` as workspace variables. Do not commit them. `terraform.tfvars` is git-ignored (`*tfvars`) and only `terraform.tfvars.example` is tracked.
8. **SCIM: two-step apply.** The SCIM team mappings need the IdP to synchronize first, so a new organization needs a **two-step apply** (details in [Configure SCIM in Azure AD](#1-configure-scim-in-azure-ad)): (1) apply with SCIM enabled and without the team mappings, (2) configure provisioning in Entra ID with the SCIM token and wait for the sync, (3) uncomment and apply again. The lines to toggle are marked `IMPORTANT: uncomment after applying first` in `main.tf`: `scim_teams`, `project_team_access`, `workspace_team_access` and the `team_access` arguments of the projects and workspaces modules. **On this branch SCIM is disabled** (`enable_scim = false`, and the `scim_token` output in `outputs.tf` is commented out), and the team mapping lines are commented out. To use SCIM, set `enable_scim = true`, uncomment the output and follow the two steps above.

### Important Context

This is **not** the initial bootstrap configuration. A separate bootstrap configuration creates this management workspace in TFE. Once established, this management layer becomes the single source of truth for all TFE configuration changes, ensuring:

- **GitOps Workflow**: All changes go through version control and code review
- **Auditability**: Complete history of infrastructure changes
- **Consistency**: Declarative configuration prevents configuration drift
- **No Clickops**: Manual UI changes are avoided in favor of IaC

### Organization Setup
- **Organization**: Pre-existing, managed by separate bootstrap
- **SSO/SCIM**: EntraID (Azure AD) integration with automatic user provisioning
- **Azure Credentials**: Azure Service Principal client secret (static credentials) shared through a variable set
- **Private Registry**: Uses SSH key authentication to connect to the source repository and publish modules to TFE's private registry. This is necessary because the VCS OAuth connection cannot be used for the initial registry module publication, it creates a chicken-and-egg problem where the registry module would need to exist before it can be used to create itself. Once the modules are published to the private registry, other configurations can reference them using the standard registry syntax. This SSH Key is added to the management workspace (where this configuration runs) from the bootstrap module that creates this workspace and its SSH Key.

### Projects (Default Configuration)

The following projects are created by default via `var.projects` (these are **default values** and can be customized based on your requirements):

1. `app-1`: App 1 Project
   - **Hashicorp team**: Admin access
   - **Developers team**: Custom access with read permissions on project settings and full workspace management capabilities
2. `app-2`: App 2 Project
   - **Hashicorp team**: Admin access
   - **Developers team**: Admin access

**Team Access Management at Project Level:**

Projects support team access configuration that controls permissions across all workspaces within the project. The implementation uses a `project_team_access` local variable that merges team configurations from projects with actual team IDs, mapping project permissions accordingly. This approach handles the complexity of both `team_id` and `project_id` resolution internally using a `for_each` loop, maintaining a clean, declarative interface.

**You only need to specify the team name** (e.g., "Hashicorp", "Developers") and desired permissions, the module automatically:
- Resolves team names to team IDs
- Injects the project ID when creating team project access resources
- Handles the mapping between projects and their team access configurations

**Access Levels:**
- **Admin**: Full administrative access (simplified configuration)
- **Custom**: Granular control via `project_access` and `workspace_access` objects

**Example Configuration:**
```hcl
"app-1" = {
  description = "App 1 Project"
  team_access = {
    "Hashicorp" = {
      access = "admin"  # Simple admin access
    }
    "Developers" = {
      # Custom granular permissions
      project_access = {
        settings      = "read"   # read, update, or delete
        teams         = "read"
        variable_sets = "read"
      }
      workspace_access = {
        create           = true
        locking          = true
        delete           = true
        move             = true
        policy_overrides = false
        runs             = "apply"  # read, plan, or apply
        run_tasks        = true
        sentinel_mocks   = "read"   # none or read
        state_versions   = "write"  # none, read-outputs, read, or write
        variables        = "write"  # none, read, or write
      }
    }
  }
}
```

For detailed permission options, refer to the [TFE Project Permissions Documentation](https://developer.hashicorp.com/terraform/enterprise/users-teams-organizations/permissions/project).

**Note**: You can modify the `projects` variable in `variables.tf` or your `terraform.tfvars` file to create different projects based on your organizational needs.

### Workspaces (Default Configuration)

The following workspaces are created by default via `var.workspaces` (CLI-driven in this branch, see [Workflow used in this branch](#workflow-used-in-this-branch)). These are **default values** and can be customized:

1. `dev-app-1-backend`: Development backend workspace for app-1

**Permission Design Rationale:**

The default configuration demonstrates two permission models:

**app-1 (Balanced Security Model):**
- **Hashicorp team**: Full admin access for platform management
- **Developers team**: Custom granular permissions designed to provide:
  - **Project-level read-only access**: Developers can view organizational structure (settings, teams, variable sets) but cannot modify it, maintaining security boundaries while providing visibility
  - **Full workspace operational capabilities**: Complete autonomy for workspace lifecycle (create, lock, delete, move) and deployment operations (plan + apply)
  - **Security controls**: `policy_overrides = false` prevents bypassing Sentinel policies. `sentinel_mocks = "read"` allows viewing but not modifying policy test data
  - **Operational permissions**: Full state and variable management (`write` access) necessary for normal Terraform operations

This model is ideal for development teams that need operational autonomy within their workspaces while restricting project-level changes that could affect the entire organization.

**app-2 (Simplified Admin Model):**
- **Hashicorp team**: Full admin access
- **Developers team**: Simple admin access for complete control

This model is appropriate for less critical projects, smaller teams, or when developers need full administrative capabilities without granular restrictions.

**Variable Management Strategy:**

The app-1 configuration demonstrates a powerful security pattern:
- **Variable Sets (Project-level)**: Read-only access (`variable_sets = "read"`) prevents developers from modifying shared organizational configuration
- **Workspace Variables**: Full write access (`variables = "write"`) allows developers to manage workspace-specific configuration

This creates an excellent balance:
- **Operability**: Developers can freely manage workspace-specific variables for their applications
- **Security**: Shared variable sets (e.g., Azure credentials, compliance settings) remain protected from accidental or unauthorized changes
- **Flexibility**: If a workspace needs different values from a shared variable set, developers can override them at the workspace level

**Practical Use Cases:**

1. **Requesting New Variable Sets**: When multiple workspaces need shared configuration (e.g., database connection strings, API endpoints), developers can:
   - Request the platform team to create a new variable set
   - Or, if permissions allow, create workspace-specific variables as a temporary solution
   - Platform team can later consolidate common patterns into shared variable sets

2. **Environment-Specific Permissions**: Consider different permission models per environment:
   ```hcl
   # Development: Full autonomy
   "dev-project" = {
     team_access = {
       "Developers" = { access = "admin" }
     }
   }
   
   # Production: Restricted access
   "prod-project" = {
     team_access = {
       "Developers" = {
         workspace_access = {
           runs = "plan"  # Can plan but not apply
           variables = "read"  # Read-only variables
           # ... other restrictions
         }
       }
     }
   }
   ```

3. **Graduated Permissions**: Start restrictive and gradually expand:
   - New teams: Read-only or plan-only access
   - Established teams: Full workspace management
   - Senior teams: Project-level permissions for self-service

4. **Audit and Compliance**: Use read-only project access to ensure:
   - Developers can view team assignments for collaboration
   - Settings remain visible for troubleshooting
   - Changes to organizational structure go through proper approval channels

**Customization Guidance:**
These are **reference examples**, adjust based on your organization's:
- Security requirements and compliance needs
- Team structure and trust levels
- Environment criticality (dev/staging/prod may need different permissions)
- Operational workflows and deployment practices
- Regulatory requirements (SOC2, HIPAA, PCI-DSS, etc.)

2. `sta-app-1-backend`: Staging backend workspace for app-1
3. `pro-app-1-backend`: Production backend workspace for app-1
4. `dev-app-1-frontend`: Development frontend workspace for app-1
5. `sta-app-1-frontend`: Staging frontend workspace for app-1
6. `pro-app-1-frontend`: Production frontend workspace for app-1
7. `dev-app-2-backend`: Development backend workspace for app-2

**Workspace Configuration:**
- Workspaces are CLI-driven here. The repository and branch mapping below only applies if you uncomment the `vcs_repo` block (VCS workflow connected to Azure DevOps)
- Repository mapping:
  - Backend workspaces → `{project_key}-backend` repository
  - Frontend workspaces → `{project_key}-frontend` repository
- Branch mapping by environment:
  - `dev-*` workspaces → `develop` branch
  - `sta-*` workspaces → `staging` branch
  - `pro-*` workspaces → `main` branch
- **Local Variables**: Workspaces can define local variables (Terraform or environment variables)

**Team Access Management:**
The workspace module includes team access configuration at the workspace level. This design choice provides several benefits:
- **Intuitive Management**: Define team permissions when creating the workspace, rather than managing them separately in team modules
- **Single Apply**: Avoid the two-step process of creating workspaces first, then updating team modules with workspace IDs
- **DRY Principle**: Works with both SCIM teams and regular teams without duplicating logic across modules

The implementation uses a `workspace_team_access` local variable that merges team configurations from workspaces with actual team IDs, mapping workspace permissions accordingly. This approach handles the complexity of team ID resolution internally while maintaining a clean, declarative interface.

**Note**: You can modify the `workspaces` variable in `variables.tf` or your `terraform.tfvars` file to create different workspaces, connect to different repositories, or use different branch strategies.

### Variable Sets
1. **Azure Credentials Variable Set**: Contains environment variables for the Azure Service Principal (static credentials):
   - `ARM_CLIENT_ID`: Service Principal application (client) ID
   - `ARM_CLIENT_SECRET`: Service Principal client secret (**sensitive**)
   - `ARM_SUBSCRIPTION_ID`: Azure subscription ID
   - `ARM_TENANT_ID`: Azure tenant ID

   Applied to the projects defined in `var.projects`.

### Policy Sets (Default Configuration)

This branch shows both ways of defining a policy set. These are **default values** and can be customized:

- **Local policies (active by default, CLI-driven)**: `policy-null-resource-local-exec-block` is a global Sentinel policy set (`soft-mandatory`) that blocks `local-exec` provisioners on `null_resource`. The policy file lives in the [`policies`](policies) folder. It is only an example, there are no Azure policies here. No VCS integration is needed. The drawback is that you can upload a single file per policy, so no Sentinel modules or shared functions from other files.
- **VCS-based policies (commented out in the `variables.tf` defaults)**: the three policy libraries below. They need repositories in your VCS provider (Azure DevOps in the examples).

VCS-based examples:

1. `policy-library-azure-compute-terraform`: Azure Compute Terraform Policy Library
   - **Assignment**: Global (applied to all workspaces)
   - **Repository**: `policy-library-azure-compute-terraform`
   - **Branch**: `main`
   - **Kind**: Sentinel (default)

2. `policy-library-azure-networking-terraform`: Azure Networking Terraform Policy Library
   - **Assignment**: Specific workspace (`dev-app-1-backend`)
   - **Repository**: `policy-library-azure-networking-terraform`
   - **Branch**: `main`

3. `policy-library-azure-storage-terraform`: Azure Storage Terraform Policy Library
   - **Assignment**: Specific project (`app-2`)
   - **Repository**: `policy-library-azure-storage-terraform`
   - **Branch**: `main`

**Policy Set Configuration:**
- VCS-based policy sets follow the VCS workflow connected to Azure DevOps. Local policy sets read their files from the `policies` folder
- Repository naming: `policy-library-{domain}-{technology}-terraform`
- Default branch: `main`
- Default kind: `sentinel` (Sentinel policies)

**Assignment Strategies:**

Policy sets can be assigned in three ways:

1. **Global Assignment** (`global = true`): Applied to all workspaces in the organization
   - Use for organization-wide compliance policies
   - Allows excluding projects (`exclude_projects`) and workspaces (`exclude_workspaces`)
   - Example: Security baselines, cost controls, naming conventions

2. **Project-Level Assignment** (`assign_to_projects`): Applied to all workspaces within specified projects
   - Use for project-specific governance
   - Example: Environment-specific policies, team-specific requirements

3. **Workspace-Level Assignment** (`assign_to_workspaces`): Applied to specific workspaces
   - Use for fine-grained control
   - Example: Production-only policies, application-specific rules

**Example Configuration:**
```hcl
"policy-library-azure-compute-terraform" = {
  repository           = "policy-library-azure-compute-terraform"
  description          = "Azure Compute Terraform Policy Library"
  global               = true  # Applied to all workspaces
}

"policy-library-azure-networking-terraform" = {
  repository           = "policy-library-azure-networking-terraform"
  description          = "Azure Networking Terraform Policy Library"
  assign_to_workspaces = ["dev-app-1-backend"]  # Specific workspaces
}

"policy-library-azure-storage-terraform" = {
  repository           = "policy-library-azure-storage-terraform"
  description          = "Azure Storage Terraform Policy Library"
  assign_to_projects   = ["app-2"]  # All workspaces in app-2 project
}
```

**Policy Set Management (VCS-based policy sets):**
- Policy sets are version-controlled in separate repositories
- Changes to policies are managed through Git commits
- TFE automatically syncs policy updates from VCS
- Policies are evaluated during plan and apply phases

**Customization Guidance:**
You can modify the `policy_sets` variable in `variables.tf` or your `terraform.tfvars` file to:
- Add new policy sets for different Azure services or compliance frameworks
- Change assignment strategies (global vs. project vs. workspace)
- Connect to different policy repositories
- Use different policy kinds (sentinel, opa)

**Note**: VCS-based policy sets require corresponding repositories in your VCS provider (Azure DevOps in the examples) with valid Sentinel or OPA policy code. Terraform policies (an alternative to Sentinel and OPA) were not available when this was built, but they are expected to be, and this configuration can then be expanded to support them too, not only `sentinel` or `opa`. Policies can also be local: put the files in the `policies` folder and no VCS integration is needed (a CLI-driven workflow works too), even though VCS is simpler to maintain. The default policy set of this branch does exactly that.

### Azure Credentials Management

- **Static Service Principal**: a single client secret (`az_client_id` / `az_client_secret`) is shared with the projects through the variable set
- **Managed by `tfe-bootstrap`**: those values are injected into this workspace by the bootstrap layer. Change them there and not in the TFE UI or the Portal, otherwise the next bootstrap apply reverts them (drift). If you prefer to manage the secret only in TFE, add a `lifecycle { ignore_changes = [value] }` block to that variable in the `tfe-bootstrap` project, knowing that bootstrap then stops tracking it
- **Rotation**: the secret expires. Create the new one in Entra ID, update `az_client_secret` in `tfe-bootstrap` and apply it
- **Keep it out of files**: do not write the secret in plaintext in a `tfvars` file. Pass it as `TF_VAR_az_client_secret` (or from a secret store) when running `tfe-bootstrap`
- **Dynamic credentials**: not used in this branch (see `main` or `multi-provider-azure-dynamic-credentials`)

## Architecture

This management configuration uses a **DRY (Don't Repeat Yourself)** approach:
- Projects are defined in `var.projects` and created via `for_each`
- Workspaces are defined in `var.workspaces` and created via `for_each`
- VCS configuration (when the VCS workflow is enabled) is automatically derived from workspace metadata
- Variable sets are applied dynamically based on project type

## Prerequisites

1. **TFE Instance**: Access to your TFE hostname
2. **TFE Organization**: Must already exist (created by separate bootstrap)
3. **Management Workspace**: This configuration should run in a dedicated TFE workspace created by the initial bootstrap
4. **TFE Token**: API token with appropriate permissions for managing organization resources. Its duration cannot exceed the maximum token duration configured on the organization, otherwise the operations will fail
5. **Azure AD Certificate**: Certificate file for SSO configuration (default path: `./certs/azure-ad-certificate.cer`)
6. **Azure Service Principal**: App Registration / Service Principal with a client secret and the required roles
7. **Azure Credentials**: `az_client_id`, `az_client_secret`, `az_subscription_id` and `az_tenant_id` available as workspace variables (provided by `tfe-bootstrap`)
8. **Existing VCS OAuth Connection** (VCS workflow only): Azure DevOps VCS OAuth connection must be configured in TFE
9. **Azure DevOps Repositories** (VCS workflow only):
   - `{project_key}-backend` repository with branches: develop, staging, main
   - `{project_key}-frontend` repository with branches: develop, staging, main
10. **Private Registry**: TFE modules must be published to private registry
11. **Azure Providers**: AzureRM and AzureAD providers configured for managing Azure resources
12. **Policy Repositories** (only for VCS-based policy sets, local policy sets just need the files in the `policies` folder): repositories in your VCS provider (Azure DevOps in the examples) containing Sentinel or OPA policy code (e.g., `policy-library-azure-compute-terraform`, `policy-library-azure-networking-terraform`, `policy-library-azure-storage-terraform`)

## Default Configuration Strategy

This configuration uses **default values** for projects and workspaces to enable a self-service workflow that avoids repeatedly modifying the `tfe-bootstrap` repository.

### Why Use Defaults?

The `tfe-bootstrap` repository is designed to run **only once** during initial setup using Terraform Community Edition (TFCE). After the initial bootstrap:

1. **Operators can add/remove projects and workspaces** by simply modifying the `projects` and `workspaces` variables (or their default values)
2. **Changes are applied directly in TFE** through this management workspace
3. **No need to touch tfe-bootstrap**: avoiding the complexity of running TFCE again

### Configuration Approach

Variables in TFE workspaces are configured through:
- **Variable values in TFE**: Set directly in the workspace or via variable sets
- **Variable sets in TFE**: Shared configuration across multiple workspaces

This management configuration provides sensible defaults that operators can:
- **Accept as-is** for quick setup
- **Override in `terraform.tfvars`** for customization
- **Modify in `variables.tf`** for organization-wide changes

### Implementation Options

Operators can choose between three approaches for defining variables:

**Option 1: Variable Defaults (Current Approach)**
```hcl
variable "projects" {
  type = map(object({
    description = string
    app_type    = string
  }))
  default = {
    "app-1" = {
      description = "App 1 Project"
      app_type    = "backend"
    }
    # ... more defaults
  }
}
```

**Option 2: Locals (Alternative Approach)**
```hcl
variable "projects" {
  type = map(object({
    description = string
    app_type    = string
  }))
  default = {}
}

locals {
  default_projects = {
    "app-1" = {
      description = "App 1 Project"
      app_type    = "backend"
    }
    # ... more defaults
  }
  
  projects = length(var.projects) > 0 ? var.projects : local.default_projects
}
```

**Option 3: terraform.tfvars file**
Instead of relying on defaults or locals, you can commit your terraform.tfvars file to the repository and TFE will use it. **Be careful** with this approach since you could end up uploading sensitive data to your repositories. 

All three approaches are valid, and the choice depends on your team's preferences and workflow. Using variable defaults is simpler, while locals provide more flexibility for complex default logic.

### Benefits

- **Self-Service**: Teams can add projects/workspaces without platform team intervention
- **GitOps Friendly**: All changes go through version control and code review
- **Bootstrap Isolation**: The bootstrap repository remains stable and unchanged
- **Flexibility**: Easy to customize defaults for different organizational needs

## Setup Instructions

### 1. Add Azure AD Certificate

Place your Azure AD SAML certificate in the certs directory:
```bash
# Create certs directory if it doesn't exist
mkdir -p certs

# Copy your certificate file
cp /path/to/your/azure-ad-certificate.cer ./certs/azure-ad-certificate.cer
```

> **Why this certificate is needed:** the SSO/SCIM module configures SAML in TFE, and TFE needs the public signing certificate of your IdP (Entra ID) to verify the SAML assertions. It contains no private key, so it **should normally be committed** to git. The workspace is VCS-driven, so it must be in the repository the workspace is connected to.
>
> **Why `certs/azure-ad-certificate.cer` is git-ignored here:** only the author's file name is ignored (not the whole `certs/` folder) so the author's certificate is not published and others can reuse the repository. Save your certificate under another name and set `idp_cert_path` accordingly (it will be tracked), or remove that line from `.gitignore` and commit it with the default name.

### 2. Push it to your VCS repository

```bash
git add .
git commit -m "my first commit"
git push origin
```

### 3. Review the Plan in TFE

Review the resources that will be managed:
- The SSO/SCIM configuration
- Projects (default: 2, customizable)
- Teams (default: 3, created here as regular teams because SCIM is disabled in this branch, customizable)
- Workspaces (default: 7, customizable)
- Policy sets (default: 1 local policy set, customizable)
- The variable set (Azure Credentials)

### 4. Apply the Configuration

Confirm, add a comment if needed and start the run in TFE.

## Post-Deployment Steps

### 1. Configure SCIM in Azure AD

After deployment, configure SCIM provisioning in Azure AD:

1. Get the SCIM token:
   ```bash
   terraform output -raw scim_token
   ```

2. In Azure AD:
   - Go to Enterprise Applications > Your TFE App
   - Navigate to Provisioning
   - Set Tenant URL to: `https://<TFE_HOSTNAME>/api/v2/admin/scim/v2`
   - Set Secret Token to the SCIM token from step 1
   - Test the connection and start provisioning

> **Note:** the SCIM token currently has a maximum duration of 365 days, so it has to be rotated periodically (see [Rotating SCIM Token](#rotating-scim-token)).

**IMPORTANT, Dual-Apply Approach for SCIM Teams:**

When first enabling SCIM, **do not include any `scim_teams` configuration in your initial apply**. Here's why:

1. **First Apply**: Enable SCIM and generate the SCIM token
2. **Manual Configuration**: Use the generated token to configure SCIM in your IdP (Azure AD)
3. **Wait for Sync**: Allow the IdP to synchronize groups and users to TFE
4. **Second Apply**: After synchronization is complete, add `scim_teams` mappings and reapply

This dual-apply approach is necessary because:
- SCIM requires manual operations in the IdP before team mappings can work
- The SCIM token must be established in the provider first
- Team mappings will fail if attempted before IdP synchronization is complete
- After the initial SCIM configuration, subsequent team management works seamlessly

This is a one-time setup requirement. Once SCIM is established, you can manage teams declaratively through Terraform without this limitation.

#### Known issues when configuring SCIM

1. Invalid or expired SCIM token

```bash
While attempting to validate our authorization to access your application, we received this unexpected response: Received response from Web resource. Resource: https://<your-tfe-fqdn>/scim/v2/Users?filter=userName+eq+"<user-object-id>" Operation: GET Response Status Code: Unauthorized Response Headers: Connection: keep-alive x-frame-options: SAMEORIGIN x-xss-protection: 1; mode=block '[Redacted]': nosniff x-download-options: noopen x-permitted-cross-domain-policies: none referrer-policy: strict-origin-when-cross-origin x-request-id: <request-id> vary: Origin Cache-Control: no-cache Date: Tue, 25 Aug 2026 11:13:39 GMT Server: nginx Response Content: {"schemas":["urn:ietf:params:scim:api:messages:2.0:Error"],"detail":"Invalid or expired SCIM token","status":"401"} Please check the service.
```

Make sure the SCIM token you copied from the outputs is valid and works with the Test connectivity option when configuring it. Restart provisioning after that to test again

### 2. Verify SSO Configuration

1. Test SSO login at: `https://<TFE_HOSTNAME>`
2. Verify users from configured Azure AD groups can log in
3. Check team memberships are correctly assigned

### 3. Verify Workspaces

1. Navigate to each project in TFE UI
2. If you enabled the VCS workflow, verify workspaces are connected to correct repositories and branches
3. Trigger a plan (to test the VCS integration, if enabled)

### 4. Verify Policy Sets

1. Navigate to Organization Settings > Policy Sets in TFE UI
2. Verify policy sets are created and connected to correct repositories
3. Check policy set assignments (global, project-level, or workspace-level)
4. Trigger a plan in an assigned workspace to test policy evaluation

### 5. Verify Azure Credentials

1. Navigate to a workspace of one of the projects
2. Queue a plan to test Azure authentication
3. Verify the plan can authenticate to Azure with the Service Principal

## Configuration Variables

### Required Variables

- `tfe_token`: TFE API token for authentication (its duration cannot exceed the maximum token duration configured on the organization, otherwise the operations will fail)
- `tfe_hostname`: TFE hostname for the organization
- `organization`: TFE organization name
- `vcs_oauth_token_id`: OAuth token ID for VCS connection in TFE
- `vcs_org`: VCS organization name
- `vcs_project`: VCS project name
- `az_client_id`: Application (client) ID of the Azure Service Principal
- `az_client_secret`: Client secret of the Azure Service Principal (**sensitive**, never commit it)
- `az_subscription_id`: Azure Subscription ID
- `az_tenant_id`: Azure Tenant ID

### Optional Variables (with defaults)

- `idp_cert_path`: Path to the IdP certificate file (default: "./certs/azure-ad-certificate.cer")
- `projects`: Map of projects to create (see variables.tf for default structure, **customizable**)
- `workspaces`: Map of workspaces to create (see variables.tf for default structure, **customizable**)
- `policy_sets`: Map of policy sets to create, from VCS repositories or local files (see variables.tf for default structure, **customizable**)
- `teams`: Map of teams to create (see variables.tf for default structure, **customizable**)

## Customization

### Adding New Projects

Edit `variables.tf` or your `terraform.tfvars` file and add to the `projects` variable:

```hcl
variable "projects" {
  default = {
    # ... existing projects ...
    "new-project-name" = {
      description = "Description of new project"
      app_type    = "backend"  # or "frontend" or "management"
    }
  }
}
```

### Adding New Workspaces

Edit `variables.tf` or your `terraform.tfvars` file and add to the `workspaces` variable:

```hcl
variable "workspaces" {
  default = {
    # ... existing workspaces ...
    "new-workspace-name" = {
      project_key      = "project-name"
      environment      = "dev"  # or "sta" or "pro"
      app_type         = "backend"  # or "frontend"
      local_variables  = {  # Optional
        "VAR_NAME" = {
          value       = "value"
          category    = "terraform"  # or "env"
          description = "Variable description"
          hcl         = false
          sensitive   = false
        }
      }
      team_access = {  # Optional
        "TeamName" = {
          access = "admin"  # or "write", "read", or use permissions object
        }
      }
    }
  }
}
```

The VCS configuration will be automatically derived:
- Repository: Based on `app_type` (backend → `{project_key}-backend`, frontend → `{project_key}-frontend`)
- Branch: Based on `environment` (dev → develop, sta → staging, pro → main)

### Adding New Policy Sets

Edit `variables.tf` or your `terraform.tfvars` file and add to the `policy_sets` variable:

```hcl
variable "policy_sets" {
  default = {
    # ... existing policy sets ...
    "policy-library-azure-security-terraform" = {
      repository           = "policy-library-azure-security-terraform"
      description          = "Azure Security Terraform Policy Library"
      global               = false
      assign_to_projects   = ["app-1", "app-2"]  # Assign to specific projects
      assign_to_workspaces = []                   # Or specific workspaces
      kind                 = "sentinel"           # or "opa"
    }
  }
}
```

**Policy Set Assignment Options:**
- **Global**: Set `global = true` to apply to all workspaces. Global policy sets also allow excluding projects (`exclude_projects`) and workspaces (`exclude_workspaces`)
- **Project-Level**: Use `assign_to_projects` to apply to all workspaces in specified projects
- **Workspace-Level**: Use `assign_to_workspaces` to apply to specific workspaces only

**Note**: for VCS-based policy sets, the policy repositories must exist in your VCS provider (Azure DevOps in the examples) with valid Sentinel or OPA policy code. Policies can also be local files in the `policies` folder, with no VCS integration needed. Terraform policies (an alternative to Sentinel and OPA) can be added once they are available.

### Modifying Default Configuration

To change the default projects, workspaces, or policy sets:

1. Override the `projects`, `workspaces`, or `policy_sets` variables with your desired configuration by modifying the default values (I suggest using defaults or locals instead of `terraform.tfvars` files to avoid publishing potentially critical variables in the repository, since it is better practice not to track this files but if you are fine committing them to the repository it would also work)
2. Depending on the workflow (VCS-driven, CLI-driven or API-driven) you will have to apply the configuration differently

## Module Sources

All modules are consumed from the **private registry** of the organization, using the HCP Terraform FQDN (`app.terraform.io`) and the organization name hardcoded in the `source` (`app.terraform.io/<ORG>/<NAME>/tfe`). A module `source` does not support variables, which is why they are hardcoded and each `source` line carries a comment saying so. For self-hosted TFE use your own FQDN instead of `app.terraform.io`. The modules are published to the registry by `tfe-private-registry` from `tfe-tf-modules`.

- `saml-sso-and-scim/tfe`: SSO and SCIM configuration
- `team/tfe`: Team management
- `project/tfe`: Project management
- `workspace/tfe`: Workspace management
- `variable-set/tfe`: Variable set management
- `policy-set/tfe`: Policy set management (VCS repositories or local policies)

> **Warning: pin the module versions (do not leave them unpinned in production).** Without a `version`, the registry resolves the **latest** published version on every run, so a new release of a module can change what the next apply does. Pin each module with `version = "x.y.z"` and bump it deliberately. The `version` arguments are commented out, so the latest published version is used on every run. Unpinned sources are used in development only for simplicity. Note also that the modules are registered from `tfe-tf-modules` with `?ref=main` in the other repositories (`tfe-private-registry`, `tfe-bootstrap`). Pinning a tag there is better too.

## Outputs

After successful deployment:

```bash
# SCIM token (sensitive). Only available when SCIM is enabled: the `scim_token` output is commented out in this branch
terraform output -raw scim_token

# All project IDs
terraform output projects

# All workspace IDs
terraform output workspaces

# Variable set ID
terraform output variable_set
```

## GitOps Workflow

### Making Changes to TFE Configuration

1. **Create a Branch**: Create a feature branch for your changes
   ```bash
   git checkout -b feature/add-new-project
   ```

2. **Modify Configuration**: Update `variables.tf` or `terraform.tfvars` with your changes

3. **Test Locally**: Run `terraform plan` to review changes

4. **Commit and Push**: Commit your changes and push to version control
   ```bash
   git add .
   git commit -m "Add new project for team X"
   git push origin feature/add-new-project
   ```

5. **Create Pull Request**: Open a PR for code review

6. **Review Plan**: The management workspace will automatically run a plan

7. **Merge and Apply**: After approval, merge the PR to trigger automatic apply

### Benefits of GitOps Approach

- **Version Control**: All changes are tracked in Git
- **Code Review**: Changes are reviewed before implementation
- **Rollback**: Easy to revert to previous configurations
- **Audit Trail**: Complete history of who changed what and when
- **Consistency**: Prevents manual configuration drift
- **Collaboration**: Team members can propose and review changes

## Troubleshooting

### Issue: Module not found during init

**Solution**: Ensure the private registry is set up and modules are published.

### Issue: Certificate file not found

**Solution**: Verify the certificate file exists at the path specified in `idp_cert_path` variable (default: `./certs/azure-ad-certificate.cer`).

### Issue: VCS connection not found

**Solution**: Ensure Azure DevOps VCS OAuth connection is configured in the TFE organization.

### Issue: Repository or branch not found

**Solution**: Verify the repositories exist in Azure DevOps with the correct naming pattern (`{project_key}-{app_type}`) and branches (develop, staging, main).

### Issue: Azure authentication fails

**Solution**:
1. Verify the Service Principal client secret has not expired
2. Verify `az_client_id`, `az_client_secret`, `az_subscription_id` and `az_tenant_id` are set in the workspace
3. Verify the Service Principal has the required role on the subscription
4. Verify the variable set is applied to the workspace's project

### Issue: Policy set not syncing from VCS

**Solution**: 
1. Verify the policy repository exists in your VCS provider (Azure DevOps in the examples) with the correct name
2. Check that the repository contains valid Sentinel or OPA policy code
3. Ensure the VCS OAuth token has access to the policy repository
4. Verify the branch specified (default: `main`) exists in the repository
5. Check TFE UI for any VCS connection errors in the policy set settings

### Issue: Policy evaluation failing

**Solution**:
1. Review the policy code for syntax errors
2. Check policy set logs in TFE UI for detailed error messages
3. Verify policy parameters are correctly configured
4. Test policies locally using Sentinel CLI or OPA CLI before committing
5. Ensure policy enforcement level is appropriate (advisory, soft-mandatory, hard-mandatory)

### Issue: Policy set not applied to workspaces

**Solution**:
1. Verify assignment configuration: check `global`, `assign_to_projects`, or `assign_to_workspaces` settings
2. For project assignments, ensure project names match exactly
3. For workspace assignments, ensure workspace names match exactly
4. Check that workspaces are in the correct projects if using project-level assignment
5. Review policy set details in TFE UI to confirm actual assignments

### Issue: Permission denied when applying changes

**Solution**: Verify the TFE token has appropriate permissions for managing organization resources, and that its duration does not exceed the maximum token duration configured on the organization (otherwise the operations will fail).

## Maintenance

### Updating Modules

To update to the latest version of the TFE modules:
```bash
terraform init -upgrade
terraform plan
terraform apply
```

### Rotating SCIM Token

The SCIM token currently lasts at most 365 days, so rotate it before it expires (or whenever it may have been exposed):
1. Run `terraform taint module.saml_sso_scim.tfe_admin_scim_token.this[0]`
2. Run `terraform apply`
3. Update the token in Azure AD provisioning settings

### Adding New Teams

To add new teams managed through this configuration:
1. Update the team configuration in your variables
2. Run `terraform plan` to review
3. Run `terraform apply` to create the teams
4. Configure team permissions as needed

### Managing Workspace Lifecycle

To add, modify, or remove workspaces:
1. Update the `workspaces` variable
2. Run `terraform plan` to review changes
3. Run `terraform apply` to implement changes
4. Verify in TFE UI that changes are correct

## Security Considerations

- **TFE Token**: Store securely, never commit to version control. Its duration cannot exceed the maximum token duration configured on the organization
- **SCIM Token**: Rotate regularly (it currently lasts at most 365 days), treat as highly sensitive
- **Azure Credentials**: Protect service principal credentials
- **Certificate**: Keep the Azure AD certificate secure and up to date
- **State File**: Ensure Terraform state is stored securely (preferably in TFE remote backend)
- **Access Control**: Limit who can approve and merge changes to this management configuration

## References

- [TFE Provider Documentation](https://registry.terraform.io/providers/hashicorp/tfe/latest/docs)
- [Azure AD SAML Configuration](https://learn.microsoft.com/en-us/azure/active-directory/saas-apps/terraform-cloud-tutorial)
- [Azure AD SCIM Provisioning](https://learn.microsoft.com/en-us/azure/active-directory/app-provisioning/use-scim-to-provision-users-and-groups)
- [GitOps Principles](https://www.gitops.tech/)

## Support

This project is offered as is and **no support is provided** (see the disclaimer at the top of this README and [SUPPORT](.github/SUPPORT.md)). For issues or questions, these resources are the best place to start:

- The README of each module used here, in [`tfe-tf-modules`](https://github.com/permilche/tfe-tf-modules)
- [TFE documentation](https://developer.hashicorp.com/terraform/enterprise)
- [TFE provider documentation](https://registry.terraform.io/providers/hashicorp/tfe/latest/docs)

## License

Licensed under the [Mozilla Public License 2.0](LICENSE). See also [CONTRIBUTING](.github/CONTRIBUTING.md), [SUPPORT](.github/SUPPORT.md) and [SECURITY](.github/SECURITY.md).
