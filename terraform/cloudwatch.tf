# -----------------------------------------------------------------------------
# CloudWatch Log Groups
# -----------------------------------------------------------------------------
# This file creates CloudWatch Log Groups for all services:
# - Temporal services (History, Matching, Frontend, Worker, UI)
# - Grafana
# 
# Note: ECS Exec log group is defined in ecs-cluster.tf
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Temporal Service Log Groups
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "temporal_history" {
  name              = "/ecs/${var.project_name}/temporal-history"
  retention_in_days = var.log_retention_days

  tags = {
    Name    = "${var.project_name}-temporal-history-logs"
    Service = "temporal-history"
  }
}

resource "aws_cloudwatch_log_group" "temporal_matching" {
  name              = "/ecs/${var.project_name}/temporal-matching"
  retention_in_days = var.log_retention_days

  tags = {
    Name    = "${var.project_name}-temporal-matching-logs"
    Service = "temporal-matching"
  }
}

resource "aws_cloudwatch_log_group" "temporal_frontend" {
  name              = "/ecs/${var.project_name}/temporal-frontend"
  retention_in_days = var.log_retention_days

  tags = {
    Name    = "${var.project_name}-temporal-frontend-logs"
    Service = "temporal-frontend"
  }
}

resource "aws_cloudwatch_log_group" "temporal_worker" {
  name              = "/ecs/${var.project_name}/temporal-worker"
  retention_in_days = var.log_retention_days

  tags = {
    Name    = "${var.project_name}-temporal-worker-logs"
    Service = "temporal-worker"
  }
}

resource "aws_cloudwatch_log_group" "temporal_ui" {
  name              = "/ecs/${var.project_name}/temporal-ui"
  retention_in_days = var.log_retention_days

  tags = {
    Name    = "${var.project_name}-temporal-ui-logs"
    Service = "temporal-ui"
  }
}

# -----------------------------------------------------------------------------
# Grafana Log Group
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "grafana" {
  name              = "/ecs/${var.project_name}/grafana"
  retention_in_days = var.log_retention_days

  tags = {
    Name    = "${var.project_name}-grafana-logs"
    Service = "grafana"
  }
}
