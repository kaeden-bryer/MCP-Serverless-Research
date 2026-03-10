terraform {
  cloud {
    # Replace this with your HCP Terraform organization name (set up in CLAUDE.md Step 4).
    organization = "Kaedens-Space"

    workspaces {
      # The workspace name is set dynamically via the TF_WORKSPACE env var
      # in CI (derived from the branch name). Locally, export TF_WORKSPACE
      # before running terraform commands.
      # CI workflows create the workspace via the HCP Terraform API if it
      # doesn't already exist (see the "Ensure HCP Terraform workspace exists"
      # step in each workflow).
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
