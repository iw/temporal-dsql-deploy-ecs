# -----------------------------------------------------------------------------
# OpenSearch Provisioned Domain
# -----------------------------------------------------------------------------
# This file creates an OpenSearch Provisioned domain for Temporal visibility:
# - 3 × m6g.large.search nodes for production workloads
# - Single AZ deployment (3 nodes provides redundancy within AZ)
# - VPC deployment in private subnet
# - Encryption at rest and node-to-node encryption
# - HTTPS enforcement with TLS 1.2 minimum
# - IAM-based access policy for Temporal services
# 
# Requirements: 7.1, 7.2, 7.4, 7.5, 7.6, 7.7
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# OpenSearch Domain
# -----------------------------------------------------------------------------

resource "aws_opensearch_domain" "temporal" {
  domain_name    = "${var.project_name}-visibility"
  engine_version = "OpenSearch_2.11"

  # Production capacity: 3 × m6g.large.search nodes in single AZ
  # Single AZ for simplicity - 3 nodes provides redundancy within the AZ
  # Requirements: 7.1, 7.2
  cluster_config {
    instance_type            = "m6g.large.search"
    instance_count           = 3
    zone_awareness_enabled   = false
    dedicated_master_enabled = false
  }

  # 100 GiB gp3 storage per node
  # Requirements: 7.2
  ebs_options {
    ebs_enabled = true
    volume_size = 100
    volume_type = "gp3"
    iops        = 3000
    throughput  = 125
  }

  # VPC deployment in private subnet (single AZ)
  # Requirements: 7.4
  vpc_options {
    subnet_ids         = [aws_subnet.private[0].id]
    security_group_ids = [aws_security_group.opensearch.id]
  }

  # Encryption at rest
  # Requirements: 7.7
  encrypt_at_rest {
    enabled = true
  }

  # Node-to-node encryption
  # Requirements: 7.7
  node_to_node_encryption {
    enabled = true
  }

  # HTTPS enforcement with TLS 1.2 minimum
  # Requirements: 7.7
  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  # Access policy for Temporal task role and OpenSearch setup task role
  # Requirements: 7.6
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.temporal_task.arn,
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
# OpenSearch Schema Setup Task
# -----------------------------------------------------------------------------
# One-time ECS task to initialize the OpenSearch visibility index using
# temporal-elasticsearch-tool. This task runs once after OpenSearch domain
# creation and before starting Temporal services.
# 
# Requirements: 7.3
# -----------------------------------------------------------------------------

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
# Security Group for OpenSearch Setup Task
# -----------------------------------------------------------------------------

resource "aws_security_group" "opensearch_setup" {
  name        = "${var.project_name}-opensearch-setup"
  description = "Security group for OpenSearch setup task"
  vpc_id      = aws_vpc.main.id

  # Outbound to OpenSearch (HTTPS)
  egress {
    description     = "HTTPS to OpenSearch"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.opensearch.id]
  }

  # Outbound to VPC endpoints (for ECR, CloudWatch Logs, SSM)
  egress {
    description     = "HTTPS to VPC endpoints"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.vpc_endpoints.id]
  }

  # Outbound to S3 Gateway endpoint (for ECR image layers)
  # S3 Gateway endpoints use prefix lists, but we allow all HTTPS for simplicity
  egress {
    description = "HTTPS to S3 (ECR image layers)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-opensearch-setup-sg"
  }
}

# Allow OpenSearch to receive connections from setup task
resource "aws_security_group_rule" "opensearch_from_setup" {
  type                     = "ingress"
  description              = "HTTPS from OpenSearch setup task"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.opensearch_setup.id
  security_group_id        = aws_security_group.opensearch.id
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
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.opensearch_setup_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = "opensearch-setup"
      image     = var.temporal_admin_tools_image
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
          echo "Creating visibility index: ${var.opensearch_visibility_index}"
          temporal-elasticsearch-tool \
            --ep "https://${aws_opensearch_domain.temporal.endpoint}:443" \
            --aws-credentials aws-sdk-default \
            --tls \
            create-index --index "${var.opensearch_visibility_index}"
          
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

