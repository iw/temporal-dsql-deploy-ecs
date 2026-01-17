# -----------------------------------------------------------------------------
# Temporal UI Service
# -----------------------------------------------------------------------------
# This file creates the Temporal UI service:
# - Task definition with ARM64 (Graviton) architecture
# - ECS service with Service Connect (client-only mode)
# - Port mapping: 8080 (HTTP)
# 
# Configuration approach:
# - Uses official temporalio/ui image
# - Connects to Frontend service via Service Connect (temporal-frontend:7233)
# - No public access - use SSM port forwarding for remote access
#
# UI is a client-only service - it connects to Frontend but doesn't
# expose discoverable endpoints for other services.
#
# Requirements: 4.1, 4.2, 4.4, 4.5, 4.9, 4.10, 4.11, 5.1, 5.2, 5.3, 5.5, 5.8, 5.10
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# UI Task Definition
# -----------------------------------------------------------------------------
# Requirements: 4.1, 4.2, 4.4, 4.5, 4.9, 4.10, 4.11

resource "aws_ecs_task_definition" "temporal_ui" {
  family                   = "${var.project_name}-temporal-ui"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = var.temporal_ui_cpu
  memory                   = var.temporal_ui_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.temporal_ui_task.arn

  # ARM64 (Graviton) architecture for cost efficiency
  # Requirements: 4.2
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = "temporal-ui"
      image     = var.temporal_ui_image # Official temporalio/ui image
      essential = true

      # Port mapping for UI HTTP service
      # Requirements: 4.4
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
          name          = "http"
        }
      ]

      # Environment variables for Temporal UI configuration
      # Requirements: 4.10, 4.11
      # Service Connect provides 'temporal-frontend' DNS name
      environment = [
        # Temporal Frontend address via Service Connect
        { name = "TEMPORAL_ADDRESS", value = "temporal-frontend:7233" },

        # CORS configuration for local port forwarding access
        { name = "TEMPORAL_CORS_ORIGINS", value = "http://localhost:8080" },

        # UI configuration
        { name = "TEMPORAL_UI_PORT", value = "8080" }
      ]

      # CloudWatch Logs configuration
      # Requirements: 4.5
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.temporal_ui.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "temporal-ui"
          "awslogs-create-group"  = "true"
        }
      }

      # Enable ECS Exec by setting initProcessEnabled
      # Requirements: 4.9
      linuxParameters = {
        initProcessEnabled = true
      }

      # Health check for HTTP endpoint
      # Requirements: 5.10
      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:8080 || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    }
  ])

  tags = {
    Name    = "${var.project_name}-temporal-ui"
    Service = "temporal-ui"
  }
}

# -----------------------------------------------------------------------------
# UI ECS Service
# -----------------------------------------------------------------------------
# Requirements: 5.1, 5.2, 5.3, 5.5, 5.8, 5.10

resource "aws_ecs_service" "temporal_ui" {
  name            = "${var.project_name}-temporal-ui"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.temporal_ui.arn
  desired_count   = var.temporal_ui_count

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
  # Requirements: 5.3
  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_instances.id, aws_security_group.temporal_ui.id]
    assign_public_ip = false
  }

  # Enable ECS Exec for debugging and port forwarding
  # Requirements: 5.5
  enable_execute_command = true

  # Service Connect configuration - client-only mode
  # UI connects to Frontend but doesn't expose discoverable endpoints
  # Requirements: 5.8
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn
    # Client-only: no service block, only consumes other services
  }

  # Ensure task definition is created first
  depends_on = [
    aws_ecs_task_definition.temporal_ui,
    aws_ecs_cluster_capacity_providers.main
  ]

  tags = {
    Name    = "${var.project_name}-temporal-ui"
    Service = "temporal-ui"
  }
}
