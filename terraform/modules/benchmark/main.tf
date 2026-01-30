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

  container_definitions = jsonencode(concat([
    {
      name      = "benchmark"
      image     = var.benchmark_image != "" ? var.benchmark_image : "public.ecr.aws/amazonlinux/amazonlinux:2023-minimal"
      essential = true
      # Reserve CPU/memory for Alloy sidecar (init: 64 CPU, 128 MB + sidecar: 128 CPU, 256 MB = 192 CPU, 384 MB)
      cpu    = var.cpu - 192
      memory = var.memory - 384

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

      # No log configuration - logs collected by Alloy sidecar

      # Enable ECS Exec
      linuxParameters = {
        initProcessEnabled = true
      }
    },
    var.alloy_init_container,
    var.alloy_sidecar_container
  ]))

  tags = {
    Name    = "${var.project_name}-benchmark"
    Service = "benchmark"
  }
}

