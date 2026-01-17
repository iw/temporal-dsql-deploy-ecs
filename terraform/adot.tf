# -----------------------------------------------------------------------------
# AWS Distro for OpenTelemetry (ADOT) Collector
# -----------------------------------------------------------------------------
# This file creates the ADOT Collector service for scraping Temporal metrics
# and remote writing to Amazon Managed Prometheus.
#
# Architecture:
# - Runs as a dedicated ECS service (not sidecar)
# - Uses Service Connect to discover Temporal services by DNS name
# - Scrapes Prometheus metrics from all 4 Temporal services on port 9090
# - Remote writes to AMP using SigV4 authentication
#
# Requirements: 20.1, 20.2, 20.3, 20.4, 20.5, 20.6, 20.7, 20.8, 20.9
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# SSM Parameter Store for ADOT Configuration
# -----------------------------------------------------------------------------
# Requirements: 20.8

resource "aws_ssm_parameter" "adot_config" {
  name = "/${var.project_name}/adot/collector-config"
  type = "String"
  tier = "Advanced"
  value = templatefile("${path.module}/templates/adot-config.yaml", {
    amp_remote_write_endpoint = "${aws_prometheus_workspace.main.prometheus_endpoint}api/v1/remote_write"
    aws_region                = var.region
  })

  tags = {
    Name = "${var.project_name}-adot-config"
  }
}

# -----------------------------------------------------------------------------
# ADOT IAM Role and Policies
# -----------------------------------------------------------------------------
# Requirements: 20.5, 20.7

resource "aws_iam_role" "adot_task" {
  name = "${var.project_name}-adot-task"

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
    Name = "${var.project_name}-adot-task"
  }
}


# Prometheus remote write permissions for ADOT
resource "aws_iam_role_policy" "adot_prometheus" {
  name = "prometheus-remote-write"
  role = aws_iam_role.adot_task.id

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

# EC2 service discovery permissions for ADOT
# Required for discovering benchmark runner tasks via EC2 tags
# Requirements: 3.1.8
resource "aws_iam_role_policy" "adot_ec2_discovery" {
  name = "ec2-service-discovery"
  role = aws_iam_role.adot_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:DescribeInstances"
      ]
      Resource = "*"
    }]
  })
}

# ECS Exec permissions for ADOT
resource "aws_iam_role_policy" "adot_ecs_exec" {
  name = "ecs-exec"
  role = aws_iam_role.adot_task.id

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

# SSM Parameter read permissions for ADOT config
resource "aws_iam_role_policy" "adot_ssm" {
  name = "ssm-parameter-read"
  role = aws_iam_role.adot_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ]
      Resource = aws_ssm_parameter.adot_config.arn
    }]
  })
}

# -----------------------------------------------------------------------------
# ADOT CloudWatch Log Group
# -----------------------------------------------------------------------------
# Requirements: 20.6

resource "aws_cloudwatch_log_group" "adot" {
  name              = "/ecs/${var.project_name}/adot"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-adot-logs"
  }
}


# -----------------------------------------------------------------------------
# ADOT Task Definition
# -----------------------------------------------------------------------------
# Requirements: 20.1, 20.6, 20.7

resource "aws_ecs_task_definition" "adot" {
  family                   = "${var.project_name}-adot"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = var.adot_cpu
  memory                   = var.adot_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.adot_task.arn

  # ARM64 (Graviton) architecture for cost efficiency
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = "adot-collector"
      image     = "public.ecr.aws/aws-observability/aws-otel-collector:latest"
      essential = true

      # Use SSM Parameter Store for configuration
      # The --config flag reads from the AOT_CONFIG_CONTENT environment variable
      command = ["--config", "env:AOT_CONFIG_CONTENT"]

      environment = [
        { name = "AWS_REGION", value = var.region }
      ]

      secrets = [
        {
          name      = "AOT_CONFIG_CONTENT"
          valueFrom = aws_ssm_parameter.adot_config.arn
        }
      ]

      # CloudWatch Logs configuration
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.adot.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "adot"
          "awslogs-create-group"  = "true"
        }
      }

      # Enable ECS Exec
      linuxParameters = {
        initProcessEnabled = true
      }
    }
  ])

  tags = {
    Name    = "${var.project_name}-adot"
    Service = "adot-collector"
  }
}


# -----------------------------------------------------------------------------
# ADOT Security Group
# -----------------------------------------------------------------------------
# Requirements: 20.9

resource "aws_security_group" "adot" {
  name        = "${var.project_name}-adot"
  description = "Security group for ADOT Collector"
  vpc_id      = aws_vpc.main.id

  # No ingress - ADOT only scrapes metrics, doesn't receive traffic

  # Egress to VPC endpoints (APS, SSM, Logs) and NAT Gateway
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS to AWS services via VPC endpoints and NAT"
  }

  # Egress to Temporal services for metrics scraping (port 9090)
  # Using VPC CIDR to allow Service Connect Envoy proxy communication
  egress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Prometheus metrics scraping from Temporal services"
  }

  tags = {
    Name = "${var.project_name}-adot"
  }
}

# -----------------------------------------------------------------------------
# Security Group Rules for Temporal Services (Metrics Ingress from ADOT)
# -----------------------------------------------------------------------------
# Requirements: 20.9

resource "aws_security_group_rule" "temporal_frontend_metrics_from_adot" {
  type                     = "ingress"
  from_port                = 9090
  to_port                  = 9090
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.adot.id
  security_group_id        = aws_security_group.temporal_frontend.id
  description              = "Prometheus metrics from ADOT Collector"
}

resource "aws_security_group_rule" "temporal_history_metrics_from_adot" {
  type                     = "ingress"
  from_port                = 9090
  to_port                  = 9090
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.adot.id
  security_group_id        = aws_security_group.temporal_history.id
  description              = "Prometheus metrics from ADOT Collector"
}

resource "aws_security_group_rule" "temporal_matching_metrics_from_adot" {
  type                     = "ingress"
  from_port                = 9090
  to_port                  = 9090
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.adot.id
  security_group_id        = aws_security_group.temporal_matching.id
  description              = "Prometheus metrics from ADOT Collector"
}

resource "aws_security_group_rule" "temporal_worker_metrics_from_adot" {
  type                     = "ingress"
  from_port                = 9090
  to_port                  = 9090
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.adot.id
  security_group_id        = aws_security_group.temporal_worker.id
  description              = "Prometheus metrics from ADOT Collector"
}


# -----------------------------------------------------------------------------
# ADOT ECS Service
# -----------------------------------------------------------------------------
# Requirements: 20.4, 20.7

resource "aws_ecs_service" "adot" {
  name            = "${var.project_name}-adot"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.adot.arn
  desired_count   = 1

  # Force new deployment when capacity provider strategy changes
  force_new_deployment = true

  # Use EC2 capacity provider
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 100
    base              = 1
  }

  # Spread tasks across availability zones for high availability
  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  # Network configuration - private subnets only, no public IP
  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_instances.id, aws_security_group.adot.id]
    assign_public_ip = false
  }

  # Enable ECS Exec for debugging
  enable_execute_command = true

  # Client-only Service Connect - consumes Temporal services via DNS names
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn
    # No service block - client-only mode (only consumes, doesn't expose)
  }

  # Wait for Temporal services to be available before starting ADOT
  depends_on = [
    aws_ecs_service.temporal_frontend,
    aws_ecs_service.temporal_history,
    aws_ecs_service.temporal_matching,
    aws_ecs_service.temporal_worker,
    aws_ecs_cluster_capacity_providers.main
  ]

  tags = {
    Name    = "${var.project_name}-adot"
    Service = "adot-collector"
  }
}
