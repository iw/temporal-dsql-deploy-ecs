# -----------------------------------------------------------------------------
# OpenSearch Module - Main Configuration
# -----------------------------------------------------------------------------
# This module creates an OpenSearch domain for Temporal visibility:
# - OpenSearch Provisioned domain with configurable instance type and count
# - Single AZ deployment with VPC access
# - Encryption at rest and node-to-node encryption
# - HTTPS enforcement with TLS 1.2 minimum
# - IAM-based access policy for Temporal services
# - One-time schema setup task definition
#
# Requirements: 9.1, 9.2, 9.3
# -----------------------------------------------------------------------------

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# OpenSearch Domain
# -----------------------------------------------------------------------------

resource "aws_opensearch_domain" "temporal" {
  domain_name    = "${var.project_name}-visibility"
  engine_version = var.engine_version

  # Cluster configuration with parameterized instance type and count
  cluster_config {
    instance_type            = var.instance_type
    instance_count           = var.instance_count
    zone_awareness_enabled   = false
    dedicated_master_enabled = false
  }

  # EBS storage configuration
  ebs_options {
    ebs_enabled = true
    volume_size = var.volume_size
    volume_type = "gp3"
    iops        = var.volume_iops
    throughput  = var.volume_throughput
  }

  # VPC deployment in private subnet (single AZ)
  vpc_options {
    subnet_ids         = [var.subnet_ids[0]]
    security_group_ids = [aws_security_group.opensearch.id]
  }

  # Encryption at rest
  encrypt_at_rest {
    enabled = true
  }

  # Node-to-node encryption
  node_to_node_encryption {
    enabled = true
  }

  # HTTPS enforcement with TLS 1.2 minimum
  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  # Access policy for Temporal task role and OpenSearch setup task role
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = [
            var.temporal_task_role_arn,
            aws_iam_role.opensearch_setup_task.arn
          ]
        }
        Action   = "es:ESHttp*"
        Resource = "arn:aws:es:${var.region}:${data.aws_caller_identity.current.account_id}:domain/${var.project_name}-visibility/*"
      }
    ]
  })

  # Advanced options for compatibility
  advanced_options = {
    "rest.action.multi.allow_explicit_index" = "true"
  }

  tags = {
    Name    = "${var.project_name}-opensearch"
    Service = "opensearch"
  }

  # Ensure IAM role exists before creating domain
  depends_on = [
    aws_iam_role.opensearch_setup_task
  ]
}

# -----------------------------------------------------------------------------
# IAM Role for OpenSearch Setup Task
# -----------------------------------------------------------------------------

resource "aws_iam_role" "opensearch_setup_task" {
  name = "${var.project_name}-opensearch-setup-task"

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
    Name = "${var.project_name}-opensearch-setup-task"
  }
}

# OpenSearch access policy for setup task
resource "aws_iam_role_policy" "opensearch_setup_access" {
  name = "opensearch-access"
  role = aws_iam_role.opensearch_setup_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "es:ESHttp*"
        Resource = "arn:aws:es:${var.region}:${data.aws_caller_identity.current.account_id}:domain/${var.project_name}-visibility/*"
      }
    ]
  })
}

# ECS Exec permissions for setup task (for debugging if needed)
resource "aws_iam_role_policy" "opensearch_setup_ecs_exec" {
  name = "ecs-exec"
  role = aws_iam_role.opensearch_setup_task.id

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

# -----------------------------------------------------------------------------
# CloudWatch Log Group for OpenSearch Setup
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "opensearch_setup" {
  name              = "/ecs/${var.project_name}/opensearch-setup"
  retention_in_days = var.log_retention_days

  tags = {
    Name    = "${var.project_name}-opensearch-setup-logs"
    Service = "opensearch-setup"
  }
}

# -----------------------------------------------------------------------------
# OpenSearch Schema Setup Task Definition
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "opensearch_setup" {
  family                   = "${var.project_name}-opensearch-setup"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = aws_iam_role.opensearch_setup_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = "opensearch-setup"
      image     = var.admin_tools_image
      essential = true

      # Run the setup script and exit
      command = [
        "/bin/sh", "-c",
        <<-EOT
          set -x
          echo "=== OpenSearch Schema Setup ==="
          echo "Endpoint: https://${aws_opensearch_domain.temporal.endpoint}:443"
          echo "AWS_REGION: $AWS_REGION"
          
          # Wait for OpenSearch to be ready using temporal-elasticsearch-tool with AWS auth
          echo "Waiting for OpenSearch..."
          max_attempts=30
          attempt=0
          until temporal-elasticsearch-tool \
            --ep "https://${aws_opensearch_domain.temporal.endpoint}:443" \
            --aws-credentials aws-sdk-default \
            --tls \
            ping; do
            attempt=$((attempt + 1))
            if [ $attempt -ge $max_attempts ]; then
              echo "OpenSearch not ready after $max_attempts attempts"
              exit 1
            fi
            echo "Waiting... ($attempt/$max_attempts)"
            sleep 10
          done
          echo "OpenSearch is ready"
          
          # Setup schema using temporal-elasticsearch-tool with AWS auth
          echo "Setting up OpenSearch schema..."
          temporal-elasticsearch-tool \
            --ep "https://${aws_opensearch_domain.temporal.endpoint}:443" \
            --aws-credentials aws-sdk-default \
            --tls \
            setup-schema
          
          # Create visibility index
          echo "Creating visibility index: ${var.visibility_index_name}"
          temporal-elasticsearch-tool \
            --ep "https://${aws_opensearch_domain.temporal.endpoint}:443" \
            --aws-credentials aws-sdk-default \
            --tls \
            create-index --index "${var.visibility_index_name}"
          
          echo "OpenSearch setup completed successfully"
        EOT
      ]

      environment = [
        { name = "AWS_REGION", value = var.region }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.opensearch_setup.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "opensearch-setup"
          "awslogs-create-group"  = "true"
        }
      }

      linuxParameters = {
        initProcessEnabled = true
      }
    }
  ])

  tags = {
    Name    = "${var.project_name}-opensearch-setup"
    Service = "opensearch-setup"
  }
}
