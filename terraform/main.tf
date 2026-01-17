# -----------------------------------------------------------------------------
# Temporal ECS Fargate Deployment - Provider Configuration
# -----------------------------------------------------------------------------
# This Terraform module deploys Temporal on AWS ECS Fargate with:
# - Multi-service architecture (History, Matching, Frontend, Worker, UI)
# - ECS Service Connect for inter-service communication
# - Aurora DSQL for persistence (IAM authentication)
# - OpenSearch Provisioned for visibility
# - Amazon Managed Prometheus for metrics
# - Grafana on ECS for dashboards
# - Private-only networking with VPC endpoints
# - Graviton (ARM64) architecture for cost efficiency
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "development"
      ManagedBy   = "terraform"
    }
  }
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}
