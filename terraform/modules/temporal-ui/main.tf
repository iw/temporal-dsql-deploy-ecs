# -----------------------------------------------------------------------------
# Temporal UI Module - Main Configuration
# -----------------------------------------------------------------------------
# This module creates the Temporal UI service:
# - Task definition with ARM64 (Graviton) architecture
# - ECS service with Service Connect (client-only mode)
# - Security group for UI service
# - CloudWatch log group
#
# Configuration approach:
# - Uses official temporalio/ui image
# - Connects to Frontend service via Service Connect (temporal-frontend:7233)
# - No public access - use SSM port forwarding for remote access
#
# UI is a client-only service - it connects to Frontend but doesn't
# expose discoverable endpoints for other services.
#
# Requirements: 7.1, 7.3
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------

locals {
  service_name   = "temporal-ui"
  container_name = "temporal-ui"
  http_port      = 8080

  # Sidecar resource allocation (init: 64 CPU, 128 MB + sidecar: 128 CPU, 256 MB)
  sidecar_cpu    = 192
  sidecar_memory = 384

  # Main container resources (reserve space for sidecar)
  main_cpu    = var.cpu - local.sidecar_cpu
  main_memory = var.memory - local.sidecar_memory
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "ui" {
  name              = "/ecs/${var.project_name}/${local.service_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name    = "${var.project_name}-${local.service_name}-logs"
    Service = local.service_name
  }
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "ui" {
  name        = "${var.project_name}-${local.service_name}"
  description = "Security group for Temporal UI service"
  vpc_id      = var.vpc_id

  # No ingress from internet - access via SSM port forwarding only

  # Egress to VPC for internal communication (to Frontend)
  egress {
    description = "Allow all traffic within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # HTTPS egress for AWS services
  egress {
    description = "HTTPS for AWS services"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${local.service_name}-sg"
  }
}


# -----------------------------------------------------------------------------
# Task Definition
# -----------------------------------------------------------------------------
# Requirements: 7.1

resource "aws_ecs_task_definition" "ui" {
  family                   = "${var.project_name}-${local.service_name}"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  # ARM64 (Graviton) architecture for cost efficiency
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  # Docker socket volume for Alloy log collection
  volume {
    name      = "docker-socket"
    host_path = "/var/run/docker.sock"
  }

  # Alloy config volume (populated by init container)
  volume {
    name = "alloy-config"
  }

  container_definitions = jsonencode([
    {
      name      = local.container_name
      image     = var.image
      essential = true
      cpu       = local.main_cpu
      memory    = local.main_memory

      # Port mapping for UI HTTP service
      portMappings = [
        {
          containerPort = local.http_port
          protocol      = "tcp"
          name          = "http"
        }
      ]

      # Environment variables for Temporal UI configuration
      # Service Connect provides 'temporal-frontend' DNS name
      environment = [
        # Temporal Frontend address via Service Connect
        { name = "TEMPORAL_ADDRESS", value = "temporal-frontend:7233" },

        # CORS configuration for local port forwarding access
        { name = "TEMPORAL_CORS_ORIGINS", value = "http://localhost:8080" },

        # UI configuration
        { name = "TEMPORAL_UI_PORT", value = tostring(local.http_port) }
      ]

      # No log configuration - logs collected by Alloy sidecar

      # Enable ECS Exec by setting initProcessEnabled
      linuxParameters = {
        initProcessEnabled = true
      }

      # Health check for HTTP endpoint
      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:${local.http_port} || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    },
    var.alloy_init_container,
    var.alloy_sidecar_container
  ])

  tags = {
    Name    = "${var.project_name}-${local.service_name}"
    Service = local.service_name
  }
}

# -----------------------------------------------------------------------------
# ECS Service
# -----------------------------------------------------------------------------
# Requirements: 7.3

resource "aws_ecs_service" "ui" {
  name            = "${var.project_name}-${local.service_name}"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.ui.arn
  desired_count   = var.desired_count

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
  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.instance_security_group_id, aws_security_group.ui.id]
    assign_public_ip = false
  }

  # Enable ECS Exec for debugging and port forwarding
  enable_execute_command = true

  # Service Connect configuration - client-only mode
  # UI connects to Frontend but doesn't expose discoverable endpoints
  service_connect_configuration {
    enabled   = true
    namespace = var.service_connect_namespace_arn
    # Client-only: no service block, only consumes other services
  }

  depends_on = [
    aws_ecs_task_definition.ui
  ]

  tags = {
    Name    = "${var.project_name}-${local.service_name}"
    Service = local.service_name
  }
}
