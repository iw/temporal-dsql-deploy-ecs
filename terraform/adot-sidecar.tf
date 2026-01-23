# -----------------------------------------------------------------------------
# ADOT Sidecar Configuration
# -----------------------------------------------------------------------------
# This file defines the ADOT sidecar container that runs alongside each
# Temporal service to collect and push metrics to Amazon Managed Prometheus.
#
# Benefits of sidecar approach:
# - Scrapes ALL replicas (not just one via load balancer)
# - Automatic scaling with service replicas
# - No service discovery complexity
# - Reliable metrics collection per task
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# SSM Parameters for Sidecar Configs
# -----------------------------------------------------------------------------
# Each service gets its own config with the correct service_name label

resource "aws_ssm_parameter" "adot_sidecar_history" {
  name = "/${var.project_name}/adot/sidecar/history"
  type = "String"
  value = templatefile("${path.module}/templates/adot-sidecar-config.yaml", {
    service_name              = "history"
    amp_remote_write_endpoint = "${aws_prometheus_workspace.main.prometheus_endpoint}api/v1/remote_write"
    aws_region                = var.region
  })

  tags = {
    Name    = "${var.project_name}-adot-sidecar-history"
    Service = "history"
  }
}

resource "aws_ssm_parameter" "adot_sidecar_matching" {
  name = "/${var.project_name}/adot/sidecar/matching"
  type = "String"
  value = templatefile("${path.module}/templates/adot-sidecar-config.yaml", {
    service_name              = "matching"
    amp_remote_write_endpoint = "${aws_prometheus_workspace.main.prometheus_endpoint}api/v1/remote_write"
    aws_region                = var.region
  })

  tags = {
    Name    = "${var.project_name}-adot-sidecar-matching"
    Service = "matching"
  }
}

resource "aws_ssm_parameter" "adot_sidecar_frontend" {
  name = "/${var.project_name}/adot/sidecar/frontend"
  type = "String"
  value = templatefile("${path.module}/templates/adot-sidecar-config.yaml", {
    service_name              = "frontend"
    amp_remote_write_endpoint = "${aws_prometheus_workspace.main.prometheus_endpoint}api/v1/remote_write"
    aws_region                = var.region
  })

  tags = {
    Name    = "${var.project_name}-adot-sidecar-frontend"
    Service = "frontend"
  }
}

resource "aws_ssm_parameter" "adot_sidecar_worker" {
  name = "/${var.project_name}/adot/sidecar/worker"
  type = "String"
  value = templatefile("${path.module}/templates/adot-sidecar-config.yaml", {
    service_name              = "worker"
    amp_remote_write_endpoint = "${aws_prometheus_workspace.main.prometheus_endpoint}api/v1/remote_write"
    aws_region                = var.region
  })

  tags = {
    Name    = "${var.project_name}-adot-sidecar-worker"
    Service = "worker"
  }
}

resource "aws_ssm_parameter" "adot_sidecar_benchmark_worker" {
  name = "/${var.project_name}/adot/sidecar/benchmark-worker"
  type = "String"
  value = templatefile("${path.module}/templates/adot-sidecar-config.yaml", {
    service_name              = "benchmark-worker"
    amp_remote_write_endpoint = "${aws_prometheus_workspace.main.prometheus_endpoint}api/v1/remote_write"
    aws_region                = var.region
  })

  tags = {
    Name    = "${var.project_name}-adot-sidecar-benchmark-worker"
    Service = "benchmark-worker"
  }
}

# -----------------------------------------------------------------------------
# Local Values for Sidecar Container Definition
# -----------------------------------------------------------------------------

locals {
  # ADOT sidecar container definition template
  # This is added to each Temporal service task definition
  adot_sidecar_container = {
    name      = "adot-collector"
    image     = "public.ecr.aws/aws-observability/aws-otel-collector:v0.40.0"
    essential = false # Don't kill the task if collector fails
    cpu       = 128
    memory    = 256

    command = ["--config", "env:ADOT_CONFIG"]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.project_name}/adot-sidecar"
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "adot"
        "awslogs-create-group"  = "true"
      }
    }
  }

  # Function to create sidecar with service-specific config
  adot_sidecar_history = merge(local.adot_sidecar_container, {
    secrets = [
      {
        name      = "ADOT_CONFIG"
        valueFrom = aws_ssm_parameter.adot_sidecar_history.arn
      }
    ]
  })

  adot_sidecar_matching = merge(local.adot_sidecar_container, {
    secrets = [
      {
        name      = "ADOT_CONFIG"
        valueFrom = aws_ssm_parameter.adot_sidecar_matching.arn
      }
    ]
  })

  adot_sidecar_frontend = merge(local.adot_sidecar_container, {
    secrets = [
      {
        name      = "ADOT_CONFIG"
        valueFrom = aws_ssm_parameter.adot_sidecar_frontend.arn
      }
    ]
  })

  adot_sidecar_worker = merge(local.adot_sidecar_container, {
    secrets = [
      {
        name      = "ADOT_CONFIG"
        valueFrom = aws_ssm_parameter.adot_sidecar_worker.arn
      }
    ]
  })

  adot_sidecar_benchmark_worker = merge(local.adot_sidecar_container, {
    secrets = [
      {
        name      = "ADOT_CONFIG"
        valueFrom = aws_ssm_parameter.adot_sidecar_benchmark_worker.arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for ADOT Sidecars
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "adot_sidecar" {
  name              = "/ecs/${var.project_name}/adot-sidecar"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-adot-sidecar-logs"
  }
}
