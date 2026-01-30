# -----------------------------------------------------------------------------
# Prod Environment - Module Instantiations
# -----------------------------------------------------------------------------
# This file instantiates all modules with appropriate variable values and
# wires module outputs to dependent module inputs.
#
# The prod environment excludes the benchmark module for production workloads.
#
# Requirements: 2.2, 2.3, 13.3
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------

locals {
  # Environment name for dynamic config selection
  environment_name = "prod"
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

# Reference externally-created Grafana admin secret
data "aws_secretsmanager_secret" "grafana_admin" {
  name = var.grafana_admin_secret_name
}

# =============================================================================
# INFRASTRUCTURE LAYER
# =============================================================================

# -----------------------------------------------------------------------------
# VPC Module
# -----------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  project_name         = var.project_name
  region               = var.region
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  enable_vpc_endpoints = var.enable_vpc_endpoints
}

# -----------------------------------------------------------------------------
# ECS Cluster Module
# -----------------------------------------------------------------------------
module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  project_name       = var.project_name
  log_retention_days = var.log_retention_days
}

# -----------------------------------------------------------------------------
# EC2 Capacity Module (Main Workload)
# -----------------------------------------------------------------------------
module "ec2_capacity" {
  source = "../../modules/ec2-capacity"

  project_name   = var.project_name
  cluster_name   = module.ecs_cluster.cluster_name
  vpc_id         = module.vpc.vpc_id
  vpc_cidr       = module.vpc.vpc_cidr
  subnet_ids     = module.vpc.private_subnet_ids
  instance_type  = var.ec2_instance_type
  instance_count = var.ec2_instance_count
  workload_type  = "main"
}

# -----------------------------------------------------------------------------
# ECS Cluster Capacity Provider Association
# -----------------------------------------------------------------------------
# Associates capacity providers with the ECS cluster. This is required for
# ECS services to use the capacity providers.
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = module.ecs_cluster.cluster_name

  capacity_providers = [module.ec2_capacity.capacity_provider_name]

  default_capacity_provider_strategy {
    capacity_provider = module.ec2_capacity.capacity_provider_name
    weight            = 100
    base              = 1
  }

  depends_on = [module.ec2_capacity]
}


# -----------------------------------------------------------------------------
# DynamoDB Module (DSQL Rate Limiter)
# -----------------------------------------------------------------------------
module "dynamodb" {
  source = "../../modules/dynamodb"

  project_name = var.project_name
}

# =============================================================================
# DATA LAYER
# =============================================================================

# -----------------------------------------------------------------------------
# OpenSearch Module
# -----------------------------------------------------------------------------
module "opensearch" {
  source = "../../modules/opensearch"

  project_name                    = var.project_name
  region                          = var.region
  vpc_id                          = module.vpc.vpc_id
  vpc_cidr                        = module.vpc.vpc_cidr
  subnet_ids                      = module.vpc.private_subnet_ids
  visibility_index_name           = var.opensearch_visibility_index
  execution_role_arn              = module.iam.execution_role_arn
  admin_tools_image               = var.temporal_admin_tools_image
  temporal_task_role_arn          = module.iam.temporal_task_role_arn
  instance_type                   = var.opensearch_instance_type
  instance_count                  = var.opensearch_instance_count
  log_retention_days              = var.log_retention_days
  vpc_endpoints_security_group_id = module.vpc.vpc_endpoints_security_group_id
}

# =============================================================================
# OBSERVABILITY LAYER
# =============================================================================

# -----------------------------------------------------------------------------
# Observability Module (Prometheus, Grafana, Loki)
# -----------------------------------------------------------------------------
module "observability" {
  source = "../../modules/observability"

  project_name                  = var.project_name
  region                        = var.region
  vpc_id                        = module.vpc.vpc_id
  vpc_cidr                      = module.vpc.vpc_cidr
  subnet_ids                    = module.vpc.private_subnet_ids
  cluster_id                    = module.ecs_cluster.cluster_id
  cluster_name                  = module.ecs_cluster.cluster_name
  capacity_provider_name        = module.ec2_capacity.capacity_provider_name
  instance_security_group_id    = module.ec2_capacity.instance_security_group_id
  service_connect_namespace_arn = module.ecs_cluster.service_connect_namespace_arn
  execution_role_arn            = module.iam.execution_role_arn
  grafana_task_role_arn         = module.iam.grafana_task_role_arn
  loki_task_role_arn            = module.iam.loki_task_role_arn
  loki_enabled                  = var.loki_enabled
  grafana_image                 = var.grafana_image
  grafana_cpu                   = var.grafana_cpu
  grafana_memory                = var.grafana_memory
  grafana_count                 = var.grafana_count
  grafana_admin_secret_name     = var.grafana_admin_secret_name
  loki_image                    = var.loki_image
  loki_cpu                      = var.loki_cpu
  loki_memory                   = var.loki_memory
  loki_count                    = var.loki_count
  loki_retention_days           = var.loki_retention_days
  log_retention_days            = var.log_retention_days
}

# =============================================================================
# IAM LAYER
# =============================================================================

# -----------------------------------------------------------------------------
# IAM Module
# -----------------------------------------------------------------------------
module "iam" {
  source = "../../modules/iam"

  project_name             = var.project_name
  region                   = var.region
  dsql_cluster_arn         = var.dsql_cluster_arn
  prometheus_workspace_arn = module.observability.prometheus_workspace_arn
  opensearch_domain_arn    = module.opensearch.domain_arn
  dynamodb_table_arn       = module.dynamodb.table_arn
  grafana_admin_secret_arn = data.aws_secretsmanager_secret.grafana_admin.arn
  loki_enabled             = var.loki_enabled
  loki_s3_bucket_arn       = module.observability.loki_s3_bucket_arn
}


# =============================================================================
# ALLOY SIDECAR MODULES
# =============================================================================
# These modules generate container definitions for Alloy sidecars that collect
# metrics and logs from Temporal services. Each service needs its own instance
# to properly label metrics with the service name.
#
# Note: We use predictable log group names (/ecs/{project}/temporal-{service})
# to avoid circular dependencies between alloy and temporal service modules.

# -----------------------------------------------------------------------------
# Alloy Sidecar for History Service
# -----------------------------------------------------------------------------
module "alloy_history" {
  source = "../../modules/alloy-sidecar"
  count  = var.loki_enabled ? 1 : 0

  project_name                     = var.project_name
  service_name                     = "history"
  prometheus_remote_write_endpoint = module.observability.prometheus_remote_write_endpoint
  loki_endpoint                    = "${module.observability.loki_endpoint}/loki/api/v1/push"
  region                           = var.region
  alloy_image                      = var.alloy_image
  log_group_name                   = "/ecs/${var.project_name}/temporal-history"
}

# -----------------------------------------------------------------------------
# Alloy Sidecar for Matching Service
# -----------------------------------------------------------------------------
module "alloy_matching" {
  source = "../../modules/alloy-sidecar"
  count  = var.loki_enabled ? 1 : 0

  project_name                     = var.project_name
  service_name                     = "matching"
  prometheus_remote_write_endpoint = module.observability.prometheus_remote_write_endpoint
  loki_endpoint                    = "${module.observability.loki_endpoint}/loki/api/v1/push"
  region                           = var.region
  alloy_image                      = var.alloy_image
  log_group_name                   = "/ecs/${var.project_name}/temporal-matching"
}

# -----------------------------------------------------------------------------
# Alloy Sidecar for Frontend Service
# -----------------------------------------------------------------------------
module "alloy_frontend" {
  source = "../../modules/alloy-sidecar"
  count  = var.loki_enabled ? 1 : 0

  project_name                     = var.project_name
  service_name                     = "frontend"
  prometheus_remote_write_endpoint = module.observability.prometheus_remote_write_endpoint
  loki_endpoint                    = "${module.observability.loki_endpoint}/loki/api/v1/push"
  region                           = var.region
  alloy_image                      = var.alloy_image
  log_group_name                   = "/ecs/${var.project_name}/temporal-frontend"
}

# -----------------------------------------------------------------------------
# Alloy Sidecar for Worker Service
# -----------------------------------------------------------------------------
module "alloy_worker" {
  source = "../../modules/alloy-sidecar"
  count  = var.loki_enabled ? 1 : 0

  project_name                     = var.project_name
  service_name                     = "worker"
  prometheus_remote_write_endpoint = module.observability.prometheus_remote_write_endpoint
  loki_endpoint                    = "${module.observability.loki_endpoint}/loki/api/v1/push"
  region                           = var.region
  alloy_image                      = var.alloy_image
  log_group_name                   = "/ecs/${var.project_name}/temporal-worker"
}


# =============================================================================
# APPLICATION LAYER - TEMPORAL SERVICES
# =============================================================================

# -----------------------------------------------------------------------------
# Temporal History Service
# -----------------------------------------------------------------------------
module "temporal_history" {
  source = "../../modules/temporal-service"

  project_name                  = var.project_name
  environment_name              = local.environment_name
  service_type                  = "history"
  region                        = var.region
  image                         = var.temporal_image
  cpu                           = var.temporal_history_cpu
  memory                        = var.temporal_history_memory
  desired_count                 = var.temporal_history_count
  cluster_id                    = module.ecs_cluster.cluster_id
  cluster_name                  = module.ecs_cluster.cluster_name
  vpc_id                        = module.vpc.vpc_id
  vpc_cidr                      = module.vpc.vpc_cidr
  subnet_ids                    = module.vpc.private_subnet_ids
  capacity_provider_name        = module.ec2_capacity.capacity_provider_name
  instance_security_group_id    = module.ec2_capacity.instance_security_group_id
  service_connect_namespace_arn = module.ecs_cluster.service_connect_namespace_arn
  execution_role_arn            = module.iam.execution_role_arn
  task_role_arn                 = module.iam.temporal_task_role_arn
  dsql_endpoint                 = var.dsql_cluster_endpoint
  dsql_rate_limiter_table       = module.dynamodb.table_name
  opensearch_endpoint           = module.opensearch.domain_endpoint
  opensearch_visibility_index   = var.opensearch_visibility_index
  history_shards                = var.temporal_history_shards
  log_retention_days            = var.log_retention_days
  loki_enabled                  = var.loki_enabled
  alloy_init_container          = var.loki_enabled ? module.alloy_history[0].init_container_definition : null
  alloy_sidecar_container       = var.loki_enabled ? module.alloy_history[0].sidecar_container_definition : null
}

# -----------------------------------------------------------------------------
# Temporal Matching Service
# -----------------------------------------------------------------------------
module "temporal_matching" {
  source = "../../modules/temporal-service"

  project_name                  = var.project_name
  environment_name              = local.environment_name
  service_type                  = "matching"
  region                        = var.region
  image                         = var.temporal_image
  cpu                           = var.temporal_matching_cpu
  memory                        = var.temporal_matching_memory
  desired_count                 = var.temporal_matching_count
  cluster_id                    = module.ecs_cluster.cluster_id
  cluster_name                  = module.ecs_cluster.cluster_name
  vpc_id                        = module.vpc.vpc_id
  vpc_cidr                      = module.vpc.vpc_cidr
  subnet_ids                    = module.vpc.private_subnet_ids
  capacity_provider_name        = module.ec2_capacity.capacity_provider_name
  instance_security_group_id    = module.ec2_capacity.instance_security_group_id
  service_connect_namespace_arn = module.ecs_cluster.service_connect_namespace_arn
  execution_role_arn            = module.iam.execution_role_arn
  task_role_arn                 = module.iam.temporal_task_role_arn
  dsql_endpoint                 = var.dsql_cluster_endpoint
  dsql_rate_limiter_table       = module.dynamodb.table_name
  opensearch_endpoint           = module.opensearch.domain_endpoint
  opensearch_visibility_index   = var.opensearch_visibility_index
  history_shards                = var.temporal_history_shards
  log_retention_days            = var.log_retention_days
  loki_enabled                  = var.loki_enabled
  alloy_init_container          = var.loki_enabled ? module.alloy_matching[0].init_container_definition : null
  alloy_sidecar_container       = var.loki_enabled ? module.alloy_matching[0].sidecar_container_definition : null
}


# -----------------------------------------------------------------------------
# Temporal Frontend Service
# -----------------------------------------------------------------------------
module "temporal_frontend" {
  source = "../../modules/temporal-service"

  project_name                  = var.project_name
  environment_name              = local.environment_name
  service_type                  = "frontend"
  region                        = var.region
  image                         = var.temporal_image
  cpu                           = var.temporal_frontend_cpu
  memory                        = var.temporal_frontend_memory
  desired_count                 = var.temporal_frontend_count
  cluster_id                    = module.ecs_cluster.cluster_id
  cluster_name                  = module.ecs_cluster.cluster_name
  vpc_id                        = module.vpc.vpc_id
  vpc_cidr                      = module.vpc.vpc_cidr
  subnet_ids                    = module.vpc.private_subnet_ids
  capacity_provider_name        = module.ec2_capacity.capacity_provider_name
  instance_security_group_id    = module.ec2_capacity.instance_security_group_id
  service_connect_namespace_arn = module.ecs_cluster.service_connect_namespace_arn
  execution_role_arn            = module.iam.execution_role_arn
  task_role_arn                 = module.iam.temporal_task_role_arn
  dsql_endpoint                 = var.dsql_cluster_endpoint
  dsql_rate_limiter_table       = module.dynamodb.table_name
  opensearch_endpoint           = module.opensearch.domain_endpoint
  opensearch_visibility_index   = var.opensearch_visibility_index
  history_shards                = var.temporal_history_shards
  log_retention_days            = var.log_retention_days
  loki_enabled                  = var.loki_enabled
  alloy_init_container          = var.loki_enabled ? module.alloy_frontend[0].init_container_definition : null
  alloy_sidecar_container       = var.loki_enabled ? module.alloy_frontend[0].sidecar_container_definition : null
}

# -----------------------------------------------------------------------------
# Temporal Worker Service
# -----------------------------------------------------------------------------
module "temporal_worker" {
  source = "../../modules/temporal-service"

  project_name                  = var.project_name
  environment_name              = local.environment_name
  service_type                  = "worker"
  region                        = var.region
  image                         = var.temporal_image
  cpu                           = var.temporal_worker_cpu
  memory                        = var.temporal_worker_memory
  desired_count                 = var.temporal_worker_count
  cluster_id                    = module.ecs_cluster.cluster_id
  cluster_name                  = module.ecs_cluster.cluster_name
  vpc_id                        = module.vpc.vpc_id
  vpc_cidr                      = module.vpc.vpc_cidr
  subnet_ids                    = module.vpc.private_subnet_ids
  capacity_provider_name        = module.ec2_capacity.capacity_provider_name
  instance_security_group_id    = module.ec2_capacity.instance_security_group_id
  service_connect_namespace_arn = module.ecs_cluster.service_connect_namespace_arn
  execution_role_arn            = module.iam.execution_role_arn
  task_role_arn                 = module.iam.temporal_task_role_arn
  dsql_endpoint                 = var.dsql_cluster_endpoint
  dsql_rate_limiter_table       = module.dynamodb.table_name
  opensearch_endpoint           = module.opensearch.domain_endpoint
  opensearch_visibility_index   = var.opensearch_visibility_index
  history_shards                = var.temporal_history_shards
  log_retention_days            = var.log_retention_days
  loki_enabled                  = var.loki_enabled
  alloy_init_container          = var.loki_enabled ? module.alloy_worker[0].init_container_definition : null
  alloy_sidecar_container       = var.loki_enabled ? module.alloy_worker[0].sidecar_container_definition : null
}


# -----------------------------------------------------------------------------
# Temporal UI Service
# -----------------------------------------------------------------------------
module "temporal_ui" {
  source = "../../modules/temporal-ui"

  project_name                  = var.project_name
  region                        = var.region
  cluster_id                    = module.ecs_cluster.cluster_id
  cluster_name                  = module.ecs_cluster.cluster_name
  vpc_id                        = module.vpc.vpc_id
  vpc_cidr                      = module.vpc.vpc_cidr
  subnet_ids                    = module.vpc.private_subnet_ids
  capacity_provider_name        = module.ec2_capacity.capacity_provider_name
  instance_security_group_id    = module.ec2_capacity.instance_security_group_id
  service_connect_namespace_arn = module.ecs_cluster.service_connect_namespace_arn
  execution_role_arn            = module.iam.execution_role_arn
  task_role_arn                 = module.iam.temporal_ui_task_role_arn
  image                         = var.temporal_ui_image
  cpu                           = var.temporal_ui_cpu
  memory                        = var.temporal_ui_memory
  desired_count                 = var.temporal_ui_count
  log_retention_days            = var.log_retention_days
}

# =============================================================================
# BENCHMARK LAYER (Disabled in Prod)
# =============================================================================
# The benchmark module is NOT instantiated in the prod environment.
# Benchmarking should be performed in the bench environment only.


# =============================================================================
# SECURITY GROUP RULES - CROSS-MODULE DEPENDENCIES
# =============================================================================
# These rules connect Temporal services to OpenSearch. They are defined here
# because they depend on security groups from multiple modules.

# -----------------------------------------------------------------------------
# OpenSearch Ingress from Temporal Services
# -----------------------------------------------------------------------------
# Allow Temporal services to connect to OpenSearch for visibility queries

resource "aws_security_group_rule" "opensearch_from_temporal_frontend" {
  type                     = "ingress"
  description              = "HTTPS from Temporal Frontend"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = module.temporal_frontend.security_group_id
  security_group_id        = module.opensearch.security_group_id
}

resource "aws_security_group_rule" "opensearch_from_temporal_history" {
  type                     = "ingress"
  description              = "HTTPS from Temporal History"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = module.temporal_history.security_group_id
  security_group_id        = module.opensearch.security_group_id
}

resource "aws_security_group_rule" "opensearch_from_temporal_matching" {
  type                     = "ingress"
  description              = "HTTPS from Temporal Matching"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = module.temporal_matching.security_group_id
  security_group_id        = module.opensearch.security_group_id
}

resource "aws_security_group_rule" "opensearch_from_temporal_worker" {
  type                     = "ingress"
  description              = "HTTPS from Temporal Worker"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = module.temporal_worker.security_group_id
  security_group_id        = module.opensearch.security_group_id
}
