# -----------------------------------------------------------------------------
# Temporal Service Module - Main Configuration
# -----------------------------------------------------------------------------
# This module creates a single Temporal service (History, Matching, Frontend,
# or Worker). The service_type variable determines the port mappings,
# environment variables, and Service Connect configuration.
#
# Configuration approach:
# - Persistence config template baked into Docker image
# - Dynamic config baked into Docker image at /etc/temporal/config/dynamicconfig
# - Environment variables for DSQL connection and Temporal settings
# - IAM authentication for DSQL (no password needed)
# - OpenSearch for visibility store
# - Logs collected by Alloy sidecar and sent to Loki (when enabled)
#
# Requirements: 6.1, 6.5, 6.6, 17.2, 17.3
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Local Values for Service-Specific Configuration
# -----------------------------------------------------------------------------

locals {
  # Service-specific port mappings
  service_ports = {
    history = {
      grpc       = 7234
      membership = 6934
    }
    matching = {
      grpc       = 7235
      membership = 6935
    }
    frontend = {
      grpc       = 7233
      membership = 6933
    }
    worker = {
      grpc       = 7239
      membership = 6939
    }
  }

  # Get ports for this service type
  grpc_port       = local.service_ports[var.service_type].grpc
  membership_port = local.service_ports[var.service_type].membership
  metrics_port    = 9090

  # Service name for resource naming
  service_name = "temporal-${var.service_type}"

  # Container name
  container_name = local.service_name

  # Sidecar resource allocation (init: 64 CPU, 128 MB + sidecar: 128 CPU, 256 MB)
  sidecar_cpu    = 192
  sidecar_memory = 384

  # Main container resources (reserve space for sidecar)
  main_cpu    = var.cpu - local.sidecar_cpu
  main_memory = var.memory - local.sidecar_memory

  # Health check configuration (only for frontend)
  health_check = var.service_type == "frontend" ? {
    command     = ["CMD-SHELL", "nc -z localhost ${local.grpc_port} || exit 1"]
    interval    = 30
    timeout     = 5
    retries     = 3
    startPeriod = 60
  } : null

  # DSQL Connection Reservoir environment variables (Requirements: 17.2)
  reservoir_env_vars = var.dsql_reservoir_enabled ? [
    { name = "DSQL_RESERVOIR_ENABLED", value = "true" },
    { name = "DSQL_RESERVOIR_TARGET_READY", value = tostring(var.dsql_reservoir_target_ready) },
    { name = "DSQL_RESERVOIR_BASE_LIFETIME", value = var.dsql_reservoir_base_lifetime },
    { name = "DSQL_RESERVOIR_LIFETIME_JITTER", value = var.dsql_reservoir_lifetime_jitter },
    { name = "DSQL_RESERVOIR_GUARD_WINDOW", value = var.dsql_reservoir_guard_window }
  ] : []

  # DSQL Distributed Connection Lease environment variables (Requirements: 17.3)
  conn_lease_env_vars = var.dsql_distributed_conn_lease_enabled ? [
    { name = "DSQL_DISTRIBUTED_CONN_LEASE_ENABLED", value = "true" },
    { name = "DSQL_DISTRIBUTED_CONN_LEASE_TABLE", value = var.dsql_conn_lease_table },
    { name = "DSQL_DISTRIBUTED_CONN_LIMIT", value = tostring(var.dsql_distributed_conn_limit) }
  ] : []
}

# -----------------------------------------------------------------------------
# Task Definition
# -----------------------------------------------------------------------------
# Requirements: 6.1, 6.5

resource "aws_ecs_task_definition" "service" {
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

      portMappings = [
        {
          containerPort = local.grpc_port
          protocol      = "tcp"
          name          = "grpc"
        },
        {
          containerPort = local.membership_port
          protocol      = "tcp"
          name          = "membership"
        },
        {
          containerPort = local.metrics_port
          protocol      = "tcp"
          name          = "metrics"
        }
      ]

      environment = concat([
        # Service identification
        { name = "SERVICES", value = var.service_type },

        # Environment for dynamic config selection
        # Note: Use DEPLOY_ENVIRONMENT instead of TEMPORAL_ENVIRONMENT to avoid conflict
        # with temporal-server CLI which interprets TEMPORAL_ENVIRONMENT as --env flag
        { name = "DEPLOY_ENVIRONMENT", value = var.environment_name },

        # DSQL Configuration (IAM Auth - no password needed)
        { name = "TEMPORAL_SQL_HOST", value = var.dsql_endpoint },
        { name = "TEMPORAL_SQL_PORT", value = "5432" },
        { name = "TEMPORAL_SQL_USER", value = "admin" },
        { name = "TEMPORAL_SQL_DATABASE", value = "postgres" },
        { name = "TEMPORAL_SQL_PLUGIN", value = "dsql" },
        { name = "TEMPORAL_SQL_PLUGIN_NAME", value = "dsql" },
        { name = "TEMPORAL_SQL_TLS_ENABLED", value = "true" },
        { name = "TEMPORAL_SQL_IAM_AUTH", value = "true" },

        # DSQL Connection Pool Settings
        { name = "TEMPORAL_SQL_MAX_CONNS", value = tostring(var.dsql_max_conns) },
        { name = "TEMPORAL_SQL_MAX_IDLE_CONNS", value = tostring(var.dsql_max_idle_conns) },
        { name = "TEMPORAL_SQL_CONNECTION_TIMEOUT", value = "30s" },
        { name = "TEMPORAL_SQL_MAX_CONN_LIFETIME", value = "55m" },

        # DSQL Connection Rate Limiting
        { name = "DSQL_CONNECTION_RATE_LIMIT", value = tostring(var.dsql_connection_rate_limit) },
        { name = "DSQL_CONNECTION_BURST_LIMIT", value = tostring(var.dsql_connection_burst_limit) },

        # DSQL Distributed Rate Limiter (DynamoDB-backed)
        { name = "DSQL_DISTRIBUTED_RATE_LIMITER_ENABLED", value = "true" },
        { name = "DSQL_DISTRIBUTED_RATE_LIMITER_TABLE", value = var.dsql_rate_limiter_table },
        { name = "DSQL_DISTRIBUTED_RATE_LIMITER_LIMIT", value = "100" },

        # OpenSearch Configuration (AWS Managed)
        { name = "TEMPORAL_ELASTICSEARCH_HOST", value = var.opensearch_endpoint },
        { name = "TEMPORAL_ELASTICSEARCH_PORT", value = "443" },
        { name = "TEMPORAL_ELASTICSEARCH_SCHEME", value = "https" },
        { name = "TEMPORAL_ELASTICSEARCH_VERSION", value = "v8" },
        { name = "TEMPORAL_ELASTICSEARCH_INDEX", value = var.opensearch_visibility_index },

        # AWS Configuration for DSQL IAM auth and OpenSearch SigV4
        { name = "AWS_EC2_METADATA_DISABLED", value = "true" },
        { name = "AWS_REGION", value = var.region },
        { name = "TEMPORAL_SQL_AWS_REGION", value = var.region },

        # Persistence template location (baked into image)
        { name = "TEMPORAL_PERSISTENCE_TEMPLATE", value = "/etc/temporal/config/persistence-dsql-opensearch.template.yaml" },

        # Temporal Configuration
        { name = "TEMPORAL_LOG_LEVEL", value = var.log_level },
        { name = "TEMPORAL_HISTORY_SHARDS", value = tostring(var.history_shards) },

        # Prometheus metrics endpoint
        { name = "PROMETHEUS_ENDPOINT", value = "0.0.0.0:${local.metrics_port}" }
      ], local.reservoir_env_vars, local.conn_lease_env_vars)

      # No log configuration - logs collected by Alloy sidecar

      linuxParameters = {
        initProcessEnabled = true
      }

      # Health check only for frontend service
      healthCheck = local.health_check
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
# Requirements: 6.6

resource "aws_ecs_service" "service" {
  name            = "${var.project_name}-${local.service_name}"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.service.arn
  desired_count   = var.desired_count

  force_new_deployment = true

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

  ordered_placement_strategy {
    type  = "spread"
    field = "instanceId"
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.instance_security_group_id, aws_security_group.service.id]
    assign_public_ip = false
  }

  enable_execute_command = true

  # Service Connect configuration
  # Worker is client-only (no gRPC endpoint exposed), others expose gRPC
  service_connect_configuration {
    enabled   = true
    namespace = var.service_connect_namespace_arn

    # gRPC endpoint (not exposed for worker)
    dynamic "service" {
      for_each = var.service_type != "worker" ? [1] : []
      content {
        port_name      = "grpc"
        discovery_name = local.service_name
        client_alias {
          port     = local.grpc_port
          dns_name = local.service_name
        }
      }
    }

    # Metrics endpoint for all services
    service {
      port_name      = "metrics"
      discovery_name = "${local.service_name}-metrics"
      client_alias {
        port     = local.metrics_port
        dns_name = "${local.service_name}-metrics"
      }
    }
  }

  depends_on = [
    aws_ecs_task_definition.service
  ]

  tags = {
    Name    = "${var.project_name}-${local.service_name}"
    Service = local.service_name
  }
}
