terraform {
  cloud {
    # Replace this with your HCP Terraform organization name (set up in CLAUDE.md Step 4).
    organization = "Kaedens-Space"

    workspaces {
      # The workspace name is set dynamically via the TF_WORKSPACE env var
      # in CI (derived from the branch name). Locally, export TF_WORKSPACE
      # before running terraform commands.
      # HCP Terraform auto-creates the workspace on first init.
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
