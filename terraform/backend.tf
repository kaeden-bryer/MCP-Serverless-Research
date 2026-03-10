terraform {
  cloud {
    # Replace this with your HCP Terraform organization name (set up in CLAUDE.md Step 4).
    organization = "Kaedens-Space"

    workspaces {
      # "tags" mode lets each person create their own workspace via:
      #   terraform workspace new <name>
      # All workspaces tagged "mcp-server" appear in this HCP project.
      tags = ["mcp-server"]
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
