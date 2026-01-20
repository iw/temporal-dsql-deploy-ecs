# -----------------------------------------------------------------------------
# IAM Roles and Policies
# -----------------------------------------------------------------------------
# This file defines IAM roles for ECS tasks:
# - ECS Task Execution Role: For ECS agent operations (image pull, logging)
# - Temporal Task Role: For Temporal services (DSQL, OpenSearch, Prometheus, ECS Exec)
# - Grafana Task Role: For Grafana (Prometheus query, ECS Exec)
#
# Note: ECS Service-Linked Role (AWSServiceRoleForECS) is NOT managed here.
# It's a global account-level resource that AWS creates automatically when
# you first use ECS. If it doesn't exist, create it manually before deploying:
#   aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# ECS Task Execution Role
# -----------------------------------------------------------------------------
# Used by ECS agent for:
# - Pulling container images from ECR
# - Writing logs to CloudWatch
# - Retrieving secrets from Secrets Manager
# Requirements: 11.1, 11.2, 13.3

resource "aws_iam_role" "ecs_execution" {
  name = "${var.project_name}-ecs-execution"

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
    Name = "${var.project_name}-ecs-execution"
  }
}

# Attach the AWS managed ECS Task Execution policy
resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for Secrets Manager access (for Grafana admin credentials)
resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "secrets-manager-access"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue"
      ]
      Resource = [
        data.aws_secretsmanager_secret.grafana_admin.arn
      ]
    }]
  })
}

# Additional policy for SSM Parameter Store access (for ADOT config)
resource "aws_iam_role_policy" "ecs_execution_ssm" {
  name = "ssm-parameter-access"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ]
      Resource = [
        "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/adot/*"
      ]
    }]
  })
}


# -----------------------------------------------------------------------------
# Temporal Task Role
# -----------------------------------------------------------------------------
# Used by Temporal services (History, Matching, Frontend, Worker) for:
# - ECS Exec access (SSM Messages)
# - Aurora DSQL access (IAM authentication)
# - Amazon Managed Prometheus remote write
# - OpenSearch access for visibility
# Requirements: 11.3, 11.4, 11.5, 11.6

resource "aws_iam_role" "temporal_task" {
  name = "${var.project_name}-temporal-task"

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
    Name = "${var.project_name}-temporal-task"
  }
}

# ECS Exec permissions for Temporal services
resource "aws_iam_role_policy" "temporal_ecs_exec" {
  name = "ecs-exec"
  role = aws_iam_role.temporal_task.id

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

# Aurora DSQL access policy (IAM authentication)
resource "aws_iam_role_policy" "temporal_dsql" {
  name = "dsql-access"
  role = aws_iam_role.temporal_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dsql:DbConnect",
        "dsql:DbConnectAdmin"
      ]
      Resource = var.dsql_cluster_arn
    }]
  })
}

# Amazon Managed Prometheus remote write policy
resource "aws_iam_role_policy" "temporal_prometheus" {
  name = "prometheus-remote-write"
  role = aws_iam_role.temporal_task.id

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
      Resource = aws_prometheus_workspace.main.arn
    }]
  })
}

# OpenSearch access policy for visibility
resource "aws_iam_role_policy" "temporal_opensearch" {
  name = "opensearch-access"
  role = aws_iam_role.temporal_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "es:ESHttpGet",
        "es:ESHttpHead",
        "es:ESHttpPost",
        "es:ESHttpPut",
        "es:ESHttpDelete"
      ]
      Resource = "arn:aws:es:${var.region}:${data.aws_caller_identity.current.account_id}:domain/${var.project_name}-visibility/*"
    }]
  })
}

# DynamoDB access policy for DSQL distributed rate limiter
resource "aws_iam_role_policy" "temporal_dynamodb" {
  name = "dynamodb-rate-limiter"
  role = aws_iam_role.temporal_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem"
      ]
      Resource = aws_dynamodb_table.dsql_rate_limiter.arn
    }]
  })
}


# -----------------------------------------------------------------------------
# Grafana Task Role
# -----------------------------------------------------------------------------
# Used by Grafana service for:
# - ECS Exec access (SSM Messages)
# - Amazon Managed Prometheus query permissions
# Requirements: 11.7

resource "aws_iam_role" "grafana_task" {
  name = "${var.project_name}-grafana-task"

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
    Name = "${var.project_name}-grafana-task"
  }
}

# ECS Exec permissions for Grafana
resource "aws_iam_role_policy" "grafana_ecs_exec" {
  name = "ecs-exec"
  role = aws_iam_role.grafana_task.id

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

# Amazon Managed Prometheus query permissions for Grafana
resource "aws_iam_role_policy" "grafana_prometheus" {
  name = "prometheus-query"
  role = aws_iam_role.grafana_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "aps:QueryMetrics",
        "aps:GetSeries",
        "aps:GetLabels",
        "aps:GetMetricMetadata"
      ]
      Resource = aws_prometheus_workspace.main.arn
    }]
  })
}

# CloudWatch read permissions for Grafana (DSQL metrics)
resource "aws_iam_role_policy" "grafana_cloudwatch" {
  name = "cloudwatch-read"
  role = aws_iam_role.grafana_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "cloudwatch:DescribeAlarmsForMetric",
        "cloudwatch:DescribeAlarmHistory",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:ListMetrics",
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:GetInsightRuleReport"
      ]
      Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:GetLogGroupFields",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "tag:GetResources"
        Resource = "*"
    }]
  })
}

# -----------------------------------------------------------------------------
# Temporal UI Task Role
# -----------------------------------------------------------------------------
# Used by Temporal UI service for:
# - ECS Exec access (SSM Messages)
# Note: UI only needs to connect to Frontend via Service Connect, no AWS service access

resource "aws_iam_role" "temporal_ui_task" {
  name = "${var.project_name}-temporal-ui-task"

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
    Name = "${var.project_name}-temporal-ui-task"
  }
}

# ECS Exec permissions for Temporal UI
resource "aws_iam_role_policy" "temporal_ui_ecs_exec" {
  name = "ecs-exec"
  role = aws_iam_role.temporal_ui_task.id

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
