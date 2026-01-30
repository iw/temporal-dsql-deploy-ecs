# -----------------------------------------------------------------------------
# Terraform Configuration - Bench Environment
# -----------------------------------------------------------------------------
# This file defines Terraform version constraints and required providers.
#
# Requirements: 2.1, 2.2
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # Backend configuration should be provided via backend config file or CLI
  # Example: terraform init -backend-config=backend.hcl
  #
  # backend "s3" {
  #   bucket       = "your-terraform-state-bucket"
  #   key          = "temporal-dsql/bench/terraform.tfstate"
  #   region       = "eu-west-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}
