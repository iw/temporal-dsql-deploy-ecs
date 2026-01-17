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
# Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 13.2, 13.3
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Grafana Task Definition
# -----------------------------------------------------------------------------
# Requirements: 9.1, 9.2, 9.5, 9.6, 13.2, 13.3

resource "aws_ecs_task_definition" "grafana" {
  family                   = "${var.project_name}-grafana"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = var.grafana_cpu
  memory                   = var.grafana_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.grafana_task.arn

  # ARM64 (Graviton) architecture for cost efficiency
  # Requirements: 9.1
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = "grafana"
      image     = var.grafana_image # grafana/grafana-oss:latest
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
      # Requirements: 9.2
      environment = [
        # Grafana server configuration
        { name = "GF_SERVER_HTTP_PORT", value = "3000" },

        # Enable AWS SigV4 authentication for Amazon Managed Prometheus
        # This enables the SigV4 auth option in the Prometheus data source configuration
        { name = "GF_AUTH_SIGV4_AUTH_ENABLED", value = "true" },
        { name = "AWS_SDK_LOAD_CONFIG", value = "true" },

        # Disable anonymous access
        { name = "GF_AUTH_ANONYMOUS_ENABLED", value = "false" },

        # Logging configuration
        { name = "GF_LOG_MODE", value = "console" },
        { name = "GF_LOG_LEVEL", value = "info" }
      ]

      # Secrets from AWS Secrets Manager using JSON key extraction
      # Requirements: 9.5, 13.2, 13.3
      # Format: ${secret_arn}:json_key::
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
      # Requirements: 9.6
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
# Requirements: 9.3, 9.4

resource "aws_ecs_service" "grafana" {
  name            = "${var.project_name}-grafana"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = var.grafana_count

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
  # Requirements: 9.3
  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_instances.id, aws_security_group.grafana.id]
    assign_public_ip = false
  }

  # Enable ECS Exec for debugging and port forwarding
  # Requirements: 9.4
  enable_execute_command = true

  # Ensure task definition and EC2 capacity provider are created first
  depends_on = [
    aws_ecs_task_definition.grafana,
    aws_ecs_cluster_capacity_providers.main
  ]

  tags = {
    Name    = "${var.project_name}-grafana"
    Service = "grafana"
  }
}
