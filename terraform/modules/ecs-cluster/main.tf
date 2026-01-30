# -----------------------------------------------------------------------------
# ECS Cluster Module - Main Configuration
# -----------------------------------------------------------------------------
# This module creates the ECS cluster infrastructure:
# - Service Connect HTTP namespace for inter-service communication
# - ECS cluster with Container Insights enabled
# - Execute command logging for ECS Exec audit trail
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Service Connect Namespace
# -----------------------------------------------------------------------------
# HTTP namespace for ECS Service Connect - provides service mesh capabilities
# with automatic Envoy sidecar proxy for faster failover than DNS-based discovery

resource "aws_service_discovery_http_namespace" "main" {
  name        = var.project_name
  description = "Service Connect namespace for ${var.project_name} Temporal services"

  tags = {
    Name = "${var.project_name}-namespace"
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for ECS Exec
# -----------------------------------------------------------------------------
# Captures ECS Exec session logs for audit trail

resource "aws_cloudwatch_log_group" "ecs_exec" {
  name              = "/ecs/${var.project_name}/ecs-exec"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-ecs-exec-logs"
  }
}

# -----------------------------------------------------------------------------
# ECS Cluster
# -----------------------------------------------------------------------------

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  # Note: Requires ECS service-linked role (AWSServiceRoleForECS) to exist.
  # If cluster creation fails with "ECS Service Linked Role is not ready",
  # create the role manually: aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com

  # Enable Container Insights for monitoring and logging
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  # Configure execute command logging for ECS Exec audit trail
  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"

      log_configuration {
        cloud_watch_log_group_name = aws_cloudwatch_log_group.ecs_exec.name
      }
    }
  }

  # Set Service Connect defaults to use our namespace
  service_connect_defaults {
    namespace = aws_service_discovery_http_namespace.main.arn
  }

  tags = {
    Name = "${var.project_name}-cluster"
  }
}
