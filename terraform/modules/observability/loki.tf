# -----------------------------------------------------------------------------
# Loki Service
# -----------------------------------------------------------------------------
# This file creates the Loki log aggregation service:
# - Task definition with ARM64 (Graviton) architecture
# - ECS service in private subnets with ECS Exec enabled
# - Port mapping: 3100 (HTTP API)
# - S3 storage backend for chunks and index (TSDB mode)
# 
# Configuration approach:
# - Uses grafana/loki:3.0.0 image
# - Config stored in SSM Parameter Store
# - Connects to S3 for storage via gateway endpoint
# - No public access - internal service only
#
# Requirements: 8.1, 8.4
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Loki Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "loki" {
  name        = "${var.project_name}-loki"
  description = "Security group for Loki log aggregation service"
  vpc_id      = var.vpc_id

  # Egress to VPC for internal communication
  egress {
    description = "Allow all traffic within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # HTTPS egress for S3 access (via gateway endpoint)
  egress {
    description = "HTTPS for AWS services (S3)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-loki-sg"
  }
}

# -----------------------------------------------------------------------------
# Loki Ingress Rules
# -----------------------------------------------------------------------------
# Loki receives log pushes from Alloy sidecars and queries from Grafana.
# -----------------------------------------------------------------------------

# Grafana -> Loki (HTTP port 3100)
resource "aws_security_group_rule" "loki_from_grafana" {
  type                     = "ingress"
  description              = "HTTP from Grafana for log queries"
  from_port                = 3100
  to_port                  = 3100
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.grafana.id
  security_group_id        = aws_security_group.loki.id
}

# -----------------------------------------------------------------------------
# Loki Configuration in SSM Parameter Store
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "loki_config" {
  name = "/${var.project_name}/loki/config"
  type = "String"
  value = templatefile("${path.module}/templates/loki-config.yaml", {
    s3_bucket_name  = aws_s3_bucket.loki.id
    aws_region      = var.region
    retention_hours = var.loki_retention_days * 24
  })

  tags = {
    Name    = "${var.project_name}-loki-config"
    Service = "loki"
  }
}

# -----------------------------------------------------------------------------
# Loki CloudWatch Log Group
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "loki" {
  name              = "/ecs/${var.project_name}/loki"
  retention_in_days = var.log_retention_days

  tags = {
    Name    = "${var.project_name}-loki-logs"
    Service = "loki"
  }
}


# -----------------------------------------------------------------------------
# Loki Task Definition
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "loki" {
  family                   = "${var.project_name}-loki"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = var.loki_cpu
  memory                   = var.loki_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.loki_task_role_arn

  # ARM64 (Graviton) architecture for cost efficiency
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  # Volume for Loki config from SSM
  volume {
    name = "loki-config"
  }

  # Volume for Loki data (local cache)
  volume {
    name = "loki-data"
  }

  container_definitions = jsonencode([
    # Init container to fetch config from SSM
    {
      name       = "config-init"
      image      = "amazon/aws-cli:latest"
      essential  = false
      entryPoint = ["/bin/sh", "-c"]
      command = [
        "aws ssm get-parameter --name '/${var.project_name}/loki/config' --query 'Parameter.Value' --output text --region ${var.region} > /etc/loki/config.yaml"
      ]
      mountPoints = [
        {
          sourceVolume  = "loki-config"
          containerPath = "/etc/loki"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.loki.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "config-init"
        }
      }
    },
    # Main Loki container
    {
      name      = "loki"
      image     = var.loki_image
      essential = true

      # Wait for config init to complete
      dependsOn = [
        {
          containerName = "config-init"
          condition     = "SUCCESS"
        }
      ]

      # Loki command with config file
      command = ["-config.file=/etc/loki/config.yaml"]

      # Port mapping for Loki HTTP API
      portMappings = [
        {
          containerPort = 3100
          protocol      = "tcp"
          name          = "http"
        }
      ]

      # Environment variables
      environment = [
        { name = "AWS_REGION", value = var.region }
      ]

      # Mount config and data volumes
      mountPoints = [
        {
          sourceVolume  = "loki-config"
          containerPath = "/etc/loki"
          readOnly      = true
        },
        {
          sourceVolume  = "loki-data"
          containerPath = "/loki"
        }
      ]

      # CloudWatch Logs configuration
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.loki.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "loki"
        }
      }

      # Enable ECS Exec
      linuxParameters = {
        initProcessEnabled = true
      }

      # Health check for /ready endpoint
      # Note: Loki image is minimal, use /bin/loki with -version as a simple liveness check
      # The actual readiness is handled by Service Connect health checks
      healthCheck = {
        command     = ["CMD", "/usr/bin/loki", "-version"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    }
  ])

  tags = {
    Name    = "${var.project_name}-loki"
    Service = "loki"
  }
}

# -----------------------------------------------------------------------------
# Loki ECS Service
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "loki" {
  name            = "${var.project_name}-loki"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.loki.arn
  desired_count   = var.loki_count

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
    security_groups  = [var.instance_security_group_id, aws_security_group.loki.id]
    assign_public_ip = false
  }

  # Enable ECS Exec for debugging
  enable_execute_command = true

  # Service Connect configuration - server mode with discoverable endpoint
  service_connect_configuration {
    enabled   = true
    namespace = var.service_connect_namespace_arn

    service {
      port_name      = "http"
      discovery_name = "loki"
      client_alias {
        port     = 3100
        dns_name = "loki"
      }
    }
  }

  depends_on = [
    aws_ecs_task_definition.loki
  ]

  tags = {
    Name    = "${var.project_name}-loki"
    Service = "loki"
  }
}
