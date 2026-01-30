# -----------------------------------------------------------------------------
# Benchmark Module - Main Configuration
# -----------------------------------------------------------------------------
# This module creates the benchmark runner ECS task definition.
# The benchmark runner is a one-shot task (not a long-running service) that:
# - Executes configurable workflow patterns against Temporal
# - Collects metrics and exposes them on port 9090
# - Reports results in JSON format
#
# Key features:
# - ARM64 architecture for Graviton instances
# - awsvpc networking for Service Connect
# - Client-only Service Connect mode (consumes temporal-frontend)
# - Configurable via environment variables
# - Alloy sidecar for log collection to Loki
#
# Requirements: 10.1
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Benchmark Task Definition
# -----------------------------------------------------------------------------
# Requirements: 10.1

resource "aws_ecs_task_definition" "benchmark" {
  family                   = "${var.project_name}-benchmark"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = aws_iam_role.benchmark_task.arn

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

  container_definitions = jsonencode(concat(
    [
      {
        name      = "benchmark"
        image     = var.benchmark_image != "" ? var.benchmark_image : "public.ecr.aws/amazonlinux/amazonlinux:2023-minimal"
        essential = true
        # Reserve CPU/memory for Alloy sidecar when enabled (init: 64 CPU, 128 MB + sidecar: 128 CPU, 256 MB = 192 CPU, 384 MB)
        cpu    = var.alloy_sidecar_container != null ? var.cpu - 192 : var.cpu
        memory = var.alloy_sidecar_container != null ? var.memory - 384 : var.memory

        # Port mapping for Prometheus metrics
        portMappings = [
          {
            containerPort = 9090
            protocol      = "tcp"
            name          = "metrics"
          }
        ]

        # Default environment variables - can be overridden at runtime
        environment = [
          { name = "TEMPORAL_ADDRESS", value = "temporal-frontend:7233" },
          { name = "BENCHMARK_NAMESPACE", value = "benchmark" },
          { name = "BENCHMARK_WORKFLOW_TYPE", value = "multi-activity" },
          { name = "BENCHMARK_TARGET_RATE", value = "100" },
          { name = "BENCHMARK_DURATION", value = "5m" },
          { name = "BENCHMARK_RAMP_UP", value = "30s" },
          { name = "BENCHMARK_WORKER_COUNT", value = "4" },
          { name = "BENCHMARK_ITERATIONS", value = "1" },
          { name = "BENCHMARK_MAX_P99_LATENCY", value = "5s" },
          { name = "BENCHMARK_MIN_THROUGHPUT", value = "50" }
        ]

        # No logConfiguration - logs collected by Alloy sidecar

        # Enable ECS Exec
        linuxParameters = {
          initProcessEnabled = true
        }
      }
    ],
    var.alloy_init_container != null ? [var.alloy_init_container] : [],
    var.alloy_sidecar_container != null ? [var.alloy_sidecar_container] : []
  ))

  tags = {
    Name    = "${var.project_name}-benchmark"
    Service = "benchmark"
  }
}



# -----------------------------------------------------------------------------
# Benchmark Generator ECS Service
# -----------------------------------------------------------------------------
# The generator runs as a service (not a one-shot task) to get:
# - Service Connect for temporal-frontend discovery
# - Alloy sidecar log collection to Loki
# - Proper lifecycle management
#
# Scale to 0 when not running benchmarks, scale to 1 to run a benchmark.
# Use environment variable overrides to configure the benchmark parameters.

resource "aws_ecs_service" "benchmark_generator" {
  name            = "${var.project_name}-benchmark-generator"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.benchmark.arn
  desired_count   = 0 # Scale to 1 to run a benchmark

  # Use dedicated benchmark capacity provider
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.benchmark.name
    weight            = 1
    base              = 0
  }

  force_new_deployment = true

  enable_execute_command = true

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.instance_security_group_id, aws_security_group.benchmark.id]
    assign_public_ip = false
  }

  # Service Connect for accessing Temporal Frontend
  service_connect_configuration {
    enabled   = true
    namespace = var.service_connect_namespace_arn

    # Client-only mode - consumes services but doesn't expose any
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 0 # Allow scaling to 0

  tags = {
    Name    = "${var.project_name}-benchmark-generator"
    Service = "benchmark-generator"
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}
