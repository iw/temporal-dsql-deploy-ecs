# -----------------------------------------------------------------------------
# Temporal Matching Service
# -----------------------------------------------------------------------------
# This file creates the Temporal Matching service:
# - Task definition with ARM64 (Graviton) architecture
# - ECS service with Service Connect (client-server mode)
# - Port mappings: 7235 (gRPC), 6935 (membership), 9090 (metrics)
# 
# Configuration approach:
# - Persistence config template baked into Docker image
# - Dynamic config baked into Docker image at /etc/temporal/config/dynamicconfig
# - Environment variables for DSQL connection and Temporal settings
# - IAM authentication for DSQL (no password needed)
#
# Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.9, 5.1, 5.2, 5.3, 5.5, 5.7, 5.10
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Matching Task Definition
# -----------------------------------------------------------------------------
# Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.9

resource "aws_ecs_task_definition" "temporal_matching" {
  family                   = "${var.project_name}-temporal-matching"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = var.temporal_matching_cpu
  memory                   = var.temporal_matching_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.temporal_task.arn

  # ARM64 (Graviton) architecture for cost efficiency
  # Requirements: 4.2
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = "temporal-matching"
      image     = var.temporal_image
      essential = true

      # The runtime image entrypoint handles config rendering and server startup
      # No command override needed - SERVICES env var tells it which service to start

      # Port mappings for Matching service
      # Requirements: 4.4
      portMappings = [
        {
          containerPort = 7235
          protocol      = "tcp"
          name          = "grpc"
        },
        {
          containerPort = 6935
          protocol      = "tcp"
          name          = "membership"
        },
        {
          containerPort = 9090
          protocol      = "tcp"
          name          = "metrics"
        }
      ]

      # Environment variables for DSQL and Temporal configuration
      # Requirements: 4.6
      # These match the .env.example from temporal-dsql-deploy
      environment = [
        # Service identification
        { name = "SERVICES", value = "matching" },

        # DSQL Configuration (IAM Auth - no password needed)
        { name = "TEMPORAL_SQL_HOST", value = var.dsql_cluster_endpoint },
        { name = "TEMPORAL_SQL_PORT", value = "5432" },
        { name = "TEMPORAL_SQL_USER", value = "admin" },
        { name = "TEMPORAL_SQL_DATABASE", value = "postgres" },
        { name = "TEMPORAL_SQL_PLUGIN", value = "dsql" },
        { name = "TEMPORAL_SQL_PLUGIN_NAME", value = "dsql" },
        { name = "TEMPORAL_SQL_TLS_ENABLED", value = "true" },
        { name = "TEMPORAL_SQL_IAM_AUTH", value = "true" },

        # DSQL Connection Pool Settings (optimized for serverless)
        # Pool pre-warming fills to MaxConns on startup
        # MaxIdleConns should match MaxConns to avoid connection churn
        { name = "TEMPORAL_SQL_MAX_CONNS", value = "50" },
        { name = "TEMPORAL_SQL_MAX_IDLE_CONNS", value = "50" },
        { name = "TEMPORAL_SQL_CONNECTION_TIMEOUT", value = "30s" },
        { name = "TEMPORAL_SQL_MAX_CONN_LIFETIME", value = "55m" },

        # DSQL Connection Rate Limiting
        # Matching has moderate DB load - task queue operations
        # With 4 replicas at 6/sec each = 24/sec total for matching (100 WPS config)
        # Lower per-instance limit to stay within cluster budget when scaled up
        { name = "DSQL_CONNECTION_RATE_LIMIT", value = "6" },
        { name = "DSQL_CONNECTION_BURST_LIMIT", value = "30" },

        # DSQL Distributed Rate Limiter (DynamoDB-backed cluster-wide coordination)
        { name = "DSQL_DISTRIBUTED_RATE_LIMITER_ENABLED", value = "true" },
        { name = "DSQL_DISTRIBUTED_RATE_LIMITER_TABLE", value = aws_dynamodb_table.dsql_rate_limiter.name },
        { name = "DSQL_DISTRIBUTED_RATE_LIMITER_LIMIT", value = "100" },

        # OpenSearch Configuration (AWS Managed)
        # Matching needs visibility config for the shared persistence template
        { name = "TEMPORAL_ELASTICSEARCH_HOST", value = aws_opensearch_domain.temporal.endpoint },
        { name = "TEMPORAL_ELASTICSEARCH_PORT", value = "443" },
        { name = "TEMPORAL_ELASTICSEARCH_SCHEME", value = "https" },
        { name = "TEMPORAL_ELASTICSEARCH_VERSION", value = "v8" },
        { name = "TEMPORAL_ELASTICSEARCH_INDEX", value = var.opensearch_visibility_index },

        # AWS Configuration for DSQL IAM auth and OpenSearch SigV4
        # CRITICAL: On ECS on EC2, we must disable EC2 IMDS to force the SDK
        # to use ECS task role credentials instead of EC2 instance profile
        { name = "AWS_EC2_METADATA_DISABLED", value = "true" },
        { name = "AWS_REGION", value = var.region },
        { name = "TEMPORAL_SQL_AWS_REGION", value = var.region },

        # Persistence template location (baked into image)
        { name = "TEMPORAL_PERSISTENCE_TEMPLATE", value = "/etc/temporal/config/persistence-dsql-opensearch.template.yaml" },

        # Temporal Configuration
        { name = "TEMPORAL_LOG_LEVEL", value = "info" },
        { name = "TEMPORAL_HISTORY_SHARDS", value = tostring(var.temporal_history_shards) },

        # Prometheus metrics endpoint
        { name = "PROMETHEUS_ENDPOINT", value = "0.0.0.0:9090" }
      ]

      # CloudWatch Logs configuration
      # Requirements: 4.5
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.temporal_matching.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "temporal-matching"
          "awslogs-create-group"  = "true"
        }
      }

      # Enable ECS Exec by setting initProcessEnabled
      # Requirements: 4.9
      linuxParameters = {
        initProcessEnabled = true
      }
    }
  ])

  tags = {
    Name    = "${var.project_name}-temporal-matching"
    Service = "temporal-matching"
  }
}


# -----------------------------------------------------------------------------
# Matching ECS Service
# -----------------------------------------------------------------------------
# Requirements: 5.1, 5.2, 5.3, 5.5, 5.7, 5.10

resource "aws_ecs_service" "temporal_matching" {
  name            = "${var.project_name}-temporal-matching"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.temporal_matching.arn
  desired_count   = var.temporal_matching_count

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

  ordered_placement_strategy {
    type  = "spread"
    field = "instanceId"
  }

  # Network configuration - private subnets only, no public IP
  # Requirements: 5.3
  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_instances.id, aws_security_group.temporal_matching.id]
    assign_public_ip = false
  }

  # Enable ECS Exec for debugging
  # Requirements: 5.5
  enable_execute_command = true

  # Service Connect configuration - client-server mode with discoverable endpoint
  # Requirements: 5.7
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn

    service {
      port_name      = "grpc"
      discovery_name = "temporal-matching"
      client_alias {
        port     = 7235
        dns_name = "temporal-matching"
      }
    }

    # Expose metrics port for ADOT scraping
    service {
      port_name      = "metrics"
      discovery_name = "temporal-matching-metrics"
      client_alias {
        port     = 9090
        dns_name = "temporal-matching-metrics"
      }
    }
  }

  # Ensure task definition is created first
  depends_on = [
    aws_ecs_task_definition.temporal_matching,
    aws_ecs_cluster_capacity_providers.main
  ]

  tags = {
    Name    = "${var.project_name}-temporal-matching"
    Service = "temporal-matching"
  }
}
