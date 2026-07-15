terraform {
  required_version = ">= 1.6.0"

  # State is stored locally and gitignored. Back it up before making changes,
  # and migrate to a remote backend (e.g. HCP Terraform) if more than one
  # person manages this environment.
  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
