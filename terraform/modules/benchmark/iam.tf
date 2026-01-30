# -----------------------------------------------------------------------------
# Benchmark IAM Roles and Policies
# -----------------------------------------------------------------------------
# Task role for benchmark runner with ECS Exec support and Prometheus access.
#
# Requirements: 10.1
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Benchmark Task Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "benchmark_task" {
  name = "${var.project_name}-benchmark-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-benchmark-task"
  }
}

# ECS Exec permissions for benchmark
resource "aws_iam_role_policy" "benchmark_ecs_exec" {
  name = "ecs-exec"
  role = aws_iam_role.benchmark_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# Amazon Managed Prometheus remote write policy for benchmark ADOT sidecar
resource "aws_iam_role_policy" "benchmark_prometheus" {
  name = "prometheus-remote-write"
  role = aws_iam_role.benchmark_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "aps:RemoteWrite",
        "aps:GetSeries",
        "aps:GetLabels",
        "aps:GetMetricMetadata"
      ]
      Resource = var.prometheus_workspace_arn
    }]
  })
}

# SSM Parameter read access for Alloy sidecar config
resource "aws_iam_role_policy" "benchmark_ssm" {
  name = "ssm-parameter-read"
  role = aws_iam_role.benchmark_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ]
      Resource = "arn:aws:ssm:${var.region}:*:parameter/${var.project_name}/alloy/sidecar/*"
    }]
  })
}

