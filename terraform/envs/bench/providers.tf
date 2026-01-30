# -----------------------------------------------------------------------------
# AWS Provider Configuration - Bench Environment
# -----------------------------------------------------------------------------
# Requirements: 2.2
# -----------------------------------------------------------------------------

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "bench"
      ManagedBy   = "terraform"
    }
  }
}

# Data source for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
