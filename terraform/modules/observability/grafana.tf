# -----------------------------------------------------------------------------
# Grafana Service
# -----------------------------------------------------------------------------
# This file creates the Grafana service for metrics visualization:
# - Task definition with ARM64 (Graviton) architecture
# - ECS service in private subnets with ECS Exec enabled
# - Port mapping: 3000 (HTTP)
# 
# Configuration approach:
# - Uses grafana/grafana-oss:latest image
# - Admin credentials retrieved from Secrets Manager using JSON key extraction
# - Connects to Amazon Managed Prometheus as data source
# - No public access - use SSM port forwarding for remote access
#
# Requirements: 8.1, 8.5
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Grafana Admin Secret Data Source
# -----------------------------------------------------------------------------

data "aws_secretsmanager_secret" "grafana_admin" {
  name = var.grafana_admin_secret_name
}

# -----------------------------------------------------------------------------
# Grafana CloudWatch Log Group
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "grafana" {
  name              = "/ecs/${var.project_name}/grafana"
  retention_in_days = var.log_retention_days

  tags = {
    Name    = "${var.project_name}-grafana-logs"
    Service = "grafana"
  }
}

# -----------------------------------------------------------------------------
# Grafana Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "grafana" {
  name        = "${var.project_name}-grafana"
  description = "Security group for Grafana service"
  vpc_id      = var.vpc_id

  # No ingress from internet - access via SSM port forwarding only

  # Egress to VPC for internal communication (to Prometheus endpoint)
  egress {
    description = "Allow all traffic within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # HTTPS egress for AWS services (Prometheus, etc.)
  egress {
    description = "HTTPS for AWS services"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-grafana-sg"
  }
}


# -----------------------------------------------------------------------------
# Grafana Task Definition
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "grafana" {
  family                   = "${var.project_name}-grafana"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = var.grafana_cpu
  memory                   = var.grafana_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.grafana_task_role_arn

  # ARM64 (Graviton) architecture for cost efficiency
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = "grafana"
      image     = var.grafana_image
      essential = true

      # Port mapping for Grafana HTTP service
      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
          name          = "http"
        }
      ]

      # Environment variables for Grafana configuration
      environment = [
        # Grafana server configuration
        { name = "GF_SERVER_HTTP_PORT", value = "3000" },

        # Enable AWS SigV4 authentication for Amazon Managed Prometheus
        { name = "GF_AUTH_SIGV4_AUTH_ENABLED", value = "true" },
        { name = "AWS_SDK_LOAD_CONFIG", value = "true" },

        # Amazon Managed Prometheus endpoint for datasource provisioning
        { name = "AMP_ENDPOINT", value = aws_prometheus_workspace.main.prometheus_endpoint },
        { name = "AWS_REGION", value = var.region },

        # Disable anonymous access
        { name = "GF_AUTH_ANONYMOUS_ENABLED", value = "false" },

        # Logging configuration
        { name = "GF_LOG_MODE", value = "console" },
        { name = "GF_LOG_LEVEL", value = "info" }
      ]

      # Secrets from AWS Secrets Manager using JSON key extraction
      secrets = [
        {
          name      = "GF_SECURITY_ADMIN_USER"
          valueFrom = "${data.aws_secretsmanager_secret.grafana_admin.arn}:admin_user::"
        },
        {
          name      = "GF_SECURITY_ADMIN_PASSWORD"
          valueFrom = "${data.aws_secretsmanager_secret.grafana_admin.arn}:admin_password::"
        }
      ]

      # CloudWatch Logs configuration
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.grafana.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "grafana"
          "awslogs-create-group"  = "true"
        }
      }

      # Enable ECS Exec by setting initProcessEnabled
      linuxParameters = {
        initProcessEnabled = true
      }

      # Health check for HTTP endpoint
      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3000/api/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = {
    Name    = "${var.project_name}-grafana"
    Service = "grafana"
  }
}

# -----------------------------------------------------------------------------
# Grafana ECS Service
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "grafana" {
  name            = "${var.project_name}-grafana"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = var.grafana_count

  # Force new deployment when capacity provider strategy changes
  force_new_deployment = true

  # Use EC2 capacity provider
  capacity_provider_strategy {
    capacity_provider = var.capacity_provider_name
    weight            = 100
    base              = 1
  }

  # Spread tasks across availability zones for high availability
  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  # Network configuration - private subnets only, no public IP
  # Include Loki security group for log queries
  network_configuration {
    subnets = var.subnet_ids
    security_groups = [
      var.instance_security_group_id,
      aws_security_group.grafana.id,
      aws_security_group.loki.id
    ]
    assign_public_ip = false
  }

  # Enable ECS Exec for debugging and port forwarding
  enable_execute_command = true

  # Service Connect configuration - client mode to consume Loki service
  service_connect_configuration {
    enabled   = true
    namespace = var.service_connect_namespace_arn
    # Client-only mode - no services exposed, just consumes other services
  }

  # Ensure task definition is created first
  # Also depend on Loki service so Service Connect can discover it
  depends_on = [
    aws_ecs_task_definition.grafana,
    aws_ecs_service.loki
  ]

  tags = {
    Name    = "${var.project_name}-grafana"
    Service = "grafana"
  }
}
