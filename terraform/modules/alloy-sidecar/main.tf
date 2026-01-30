# -----------------------------------------------------------------------------
# Alloy Sidecar Module - Main Configuration
# -----------------------------------------------------------------------------
# This module generates Alloy sidecar container definitions for metrics and log
# collection. Each service that needs observability instantiates this module
# with its service_name to get properly configured container definitions.
#
# The module creates:
# - SSM parameter with service-specific Alloy configuration
# - Init container definition to fetch config from SSM
# - Sidecar container definition for the Alloy collector
#
# Note: Containers use default Docker json-file log driver (no logConfiguration)
# so that Alloy can read logs from Docker and forward them to Loki.
#
# Requirements: 12.1, 12.4
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# SSM Parameter for Alloy Sidecar Config
# -----------------------------------------------------------------------------
# Each service gets its own config with the correct service_name label
# The config is stored in SSM and fetched by the init container at runtime

resource "aws_ssm_parameter" "alloy_config" {
  name = "/${var.project_name}/alloy/sidecar/${var.service_name}"
  type = "String"
  tier = "Advanced"
  value = templatefile("${path.module}/templates/alloy-sidecar-config.alloy", {
    service_name              = var.service_name
    cluster_name              = var.project_name
    amp_remote_write_endpoint = var.prometheus_remote_write_endpoint
    loki_endpoint             = var.loki_endpoint
    aws_region                = var.region
  })

  tags = {
    Name    = "${var.project_name}-alloy-sidecar-${var.service_name}"
    Service = var.service_name
  }
}

# -----------------------------------------------------------------------------
# Local Values for Container Definitions
# -----------------------------------------------------------------------------
# These locals define the container configurations that can be included
# in any ECS task definition

locals {
  # Docker socket volume definition - required for log collection
  docker_socket_volume = {
    name = "docker-socket"
    host = {
      sourcePath = "/var/run/docker.sock"
    }
  }

  # Alloy config volume definition - shared between init and sidecar containers
  alloy_config_volume = {
    name = "alloy-config"
  }

  # Alloy config init container - fetches config from SSM
  # This runs before the main Alloy container starts
  # No logConfiguration - uses default Docker json-file driver so Alloy can read logs
  init_container_definition = {
    name       = "alloy-config-init"
    image      = "amazon/aws-cli:latest"
    essential  = false
    cpu        = 64
    memory     = 128
    entryPoint = ["/bin/sh", "-c"]

    command = [
      "aws ssm get-parameter --name '/${var.project_name}/alloy/sidecar/${var.service_name}' --query 'Parameter.Value' --output text --region ${var.region} > /etc/alloy/config.alloy"
    ]

    mountPoints = [
      {
        sourceVolume  = "alloy-config"
        containerPath = "/etc/alloy"
      }
    ]
  }

  # Alloy sidecar container definition
  # This is added to each service task definition for metrics and log collection
  # essential=false ensures the main container continues if Alloy fails
  # No logConfiguration - uses default Docker json-file driver so Alloy can read logs
  sidecar_container_definition = {
    name      = "alloy-collector"
    image     = var.alloy_image
    essential = false
    cpu       = 128
    memory    = 256

    # Alloy run command - path is positional argument, not a flag
    command = ["run", "/etc/alloy/config.alloy", "--stability.level=generally-available"]

    # Environment variables for Alloy
    environment = [
      { name = "AWS_REGION", value = var.region },
      { name = "SERVICE_NAME", value = var.service_name }
    ]

    # Dependency on init container to ensure config is available
    dependsOn = [
      {
        containerName = "alloy-config-init"
        condition     = "SUCCESS"
      }
    ]

    # Mount Docker socket for log collection and config volume
    mountPoints = [
      {
        sourceVolume  = "docker-socket"
        containerPath = "/var/run/docker.sock"
        readOnly      = true
      },
      {
        sourceVolume  = "alloy-config"
        containerPath = "/etc/alloy"
        readOnly      = true
      }
    ]

    # Enable ECS Exec for debugging
    linuxParameters = {
      initProcessEnabled = true
    }
  }
}
