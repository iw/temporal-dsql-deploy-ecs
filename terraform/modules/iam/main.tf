# -----------------------------------------------------------------------------
# IAM Module - Main Configuration
# -----------------------------------------------------------------------------
# This module creates IAM roles and policies for ECS services:
# - ECS Task Execution Role: For ECS agent operations (image pull, logging)
# - Temporal Task Role: For Temporal services (DSQL, OpenSearch, Prometheus, ECS Exec)
# - Grafana Task Role: For Grafana (Prometheus query, CloudWatch, ECS Exec)
# - Loki Task Role: For Loki (S3 storage, ECS Exec)
# - Temporal UI Task Role: For Temporal UI (ECS Exec only)
#
# Note: ECS Service-Linked Role (AWSServiceRoleForECS) is NOT managed here.
# It's a global account-level resource that AWS creates automatically when
# you first use ECS.
# Requirements: 11.1, 11.2, 11.3, 11.4, 17.4
# -----------------------------------------------------------------------------

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# ECS Task Execution Role
# -----------------------------------------------------------------------------
# Used by ECS agent for:
# - Pulling container images from ECR
# - Writing logs to CloudWatch
# - Retrieving secrets from Secrets Manager
# - Retrieving SSM parameters

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
        var.grafana_admin_secret_arn
      ]
    }]
  })
}

# Additional policy for SSM Parameter Store access (for ADOT and Loki config)
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
        "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/adot/*",
        "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/loki/*",
        "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/alloy/*"
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
# - DynamoDB access for distributed rate limiting

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

# SSM Parameter Store access for Alloy sidecar config
resource "aws_iam_role_policy" "temporal_ssm" {
  name = "ssm-parameter-access"
  role = aws_iam_role.temporal_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ]
      Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/alloy/*"
    }]
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
      Resource = var.prometheus_workspace_arn
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
      Resource = "${var.opensearch_domain_arn}/*"
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
      Resource = var.dynamodb_table_arn
    }]
  })
}

# DynamoDB access policy for DSQL distributed connection leasing
# Requirements: 17.4
resource "aws_iam_role_policy" "temporal_dynamodb_conn_lease" {
  count = var.conn_lease_enabled ? 1 : 0
  name  = "dynamodb-conn-lease"
  role  = aws_iam_role.temporal_task.id

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
      Resource = var.conn_lease_table_arn
    }]
  })
}

# -----------------------------------------------------------------------------
# Grafana Task Role
# -----------------------------------------------------------------------------
# Used by Grafana service for:
# - ECS Exec access (SSM Messages)
# - Amazon Managed Prometheus query permissions
# - CloudWatch read permissions for DSQL metrics

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
      Resource = var.prometheus_workspace_arn
    }]
  })
}

# CloudWatch read permissions for Grafana (DSQL metrics)
resource "aws_iam_role_policy" "grafana_cloudwatch" {
  name = "cloudwatch-read"
  role = aws_iam_role.grafana_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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
      }
    ]
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

# Alloy sidecar permissions for Temporal UI
resource "aws_iam_role_policy" "temporal_ui_alloy_sidecar" {
  name = "alloy-sidecar"
  role = aws_iam_role.temporal_ui_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/alloy/sidecar/temporal-ui"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Loki Task Role
# -----------------------------------------------------------------------------
# Used by Loki service for:
# - S3 access for chunk and index storage
# - ECS Exec access (SSM Messages)

resource "aws_iam_role" "loki_task" {
  name = "${var.project_name}-loki-task"

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
    Name = "${var.project_name}-loki-task"
  }
}

# S3 access policy for Loki storage
resource "aws_iam_role_policy" "loki_s3" {
  name = "s3-storage-access"
  role = aws_iam_role.loki_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        var.loki_s3_bucket_arn,
        "${var.loki_s3_bucket_arn}/*"
      ]
    }]
  })
}

# ECS Exec permissions for Loki
resource "aws_iam_role_policy" "loki_ecs_exec" {
  name = "ecs-exec"
  role = aws_iam_role.loki_task.id

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

# SSM Parameter Store access for Loki config
resource "aws_iam_role_policy" "loki_ssm" {
  name = "ssm-parameter-access"
  role = aws_iam_role.loki_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ]
      Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/loki/*"
    }]
  })
}
