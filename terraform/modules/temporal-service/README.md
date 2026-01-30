# Temporal Service Module

## Purpose

Creates a single Temporal service (History, Matching, Frontend, or Worker). This reusable module encapsulates task definition, ECS service, security group, and CloudWatch log group for any Temporal service type, enabling consistent configuration patterns across all services.

The module uses the `service_type` variable to configure:
- Port mappings (gRPC, membership, metrics)
- Service Connect endpoints
- Security group rules
- Container naming

## Service Types and Ports

| Service Type | gRPC Port | Membership Port | Metrics Port |
|--------------|-----------|-----------------|--------------|
| history      | 7234      | 6934            | 9090         |
| matching     | 7235      | 6935            | 9090         |
| frontend     | 7233      | 6933            | 9090         |
| worker       | 7239      | 6939            | 9090         |

## Inputs

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| project_name | string | Project name for resource naming | required |
| service_type | string | Service type (history/matching/frontend/worker) | required |
| region | string | AWS region | required |
| image | string | Docker image URI | required |
| cpu | number | CPU units (1024 = 1 vCPU) | 1024 |
| memory | number | Memory in MB | 2048 |
| desired_count | number | Task count | 0 |
| cluster_id | string | ECS cluster ID | required |
| cluster_name | string | ECS cluster name | required |
| capacity_provider_name | string | Capacity provider name | required |
| service_connect_namespace_arn | string | Service Connect namespace ARN | required |
| vpc_id | string | VPC ID | required |
| vpc_cidr | string | VPC CIDR block | required |
| subnet_ids | list(string) | Subnet IDs | required |
| instance_security_group_id | string | Instance SG ID | required |
| execution_role_arn | string | ECS execution role ARN | required |
| task_role_arn | string | Task role ARN | required |
| dsql_endpoint | string | DSQL cluster endpoint | required |
| dsql_rate_limiter_table | string | DynamoDB table for rate limiting | required |
| dsql_max_conns | number | Max DB connections | 50 |
| dsql_max_idle_conns | number | Max idle DB connections | 50 |
| dsql_connection_rate_limit | number | Connection rate limit/sec | 8 |
| dsql_connection_burst_limit | number | Connection burst limit | 40 |
| opensearch_endpoint | string | OpenSearch endpoint | required |
| opensearch_visibility_index | string | Visibility index name | required |
| history_shards | number | Number of history shards | 4096 |
| log_level | string | Temporal log level | "info" |
| log_retention_days | number | Log retention | 7 |
| alloy_init_container | any | Alloy init container definition | required |
| alloy_sidecar_container | any | Alloy sidecar container definition | required |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| service_name | string | ECS service name |
| service_arn | string | ECS service ARN |
| task_definition_arn | string | Task definition ARN |
| task_definition_family | string | Task definition family name |
| security_group_id | string | Service security group ID |
| log_group_name | string | CloudWatch log group name |
| log_group_arn | string | CloudWatch log group ARN |
| grpc_port | number | gRPC port for this service |
| membership_port | number | Membership port for cluster communication |
| metrics_port | number | Prometheus metrics port |
| service_type | string | Type of Temporal service |

## Usage Example

```hcl
# Create Alloy sidecar configuration for observability
module "alloy_history" {
  source = "../../modules/alloy-sidecar"

  project_name                     = var.project_name
  service_name                     = "history"
  prometheus_remote_write_endpoint = module.observability.prometheus_remote_write_endpoint
  loki_endpoint                    = "${module.observability.loki_endpoint}/loki/api/v1/push"
  region                           = var.region
  alloy_image                      = var.alloy_image
}

# Create Temporal History service
module "temporal_history" {
  source = "../../modules/temporal-service"

  project_name                  = var.project_name
  service_type                  = "history"
  region                        = var.region
  image                         = var.temporal_image
  cpu                           = 4096
  memory                        = 8192
  desired_count                 = 8
  cluster_id                    = module.ecs_cluster.cluster_id
  cluster_name                  = module.ecs_cluster.cluster_name
  capacity_provider_name        = module.ec2_capacity.capacity_provider_name
  service_connect_namespace_arn = module.ecs_cluster.service_connect_namespace_arn
  vpc_id                        = module.vpc.vpc_id
  vpc_cidr                      = module.vpc.vpc_cidr
  subnet_ids                    = module.vpc.private_subnet_ids
  instance_security_group_id    = module.ec2_capacity.instance_security_group_id
  execution_role_arn            = module.iam.execution_role_arn
  task_role_arn                 = module.iam.temporal_task_role_arn
  dsql_endpoint                 = var.dsql_cluster_endpoint
  dsql_rate_limiter_table       = module.dynamodb.table_name
  dsql_max_conns                = 500
  dsql_connection_rate_limit    = 8
  dsql_connection_burst_limit   = 40
  opensearch_endpoint           = module.opensearch.domain_endpoint
  opensearch_visibility_index   = var.opensearch_visibility_index
  history_shards                = var.temporal_history_shards
  alloy_init_container          = module.alloy_history.init_container_definition
  alloy_sidecar_container       = module.alloy_history.sidecar_container_definition
}
```

## Inter-Service Communication

The module creates a security group with:
- Self-referencing ingress rule for membership port (cluster communication)
- VPC egress for internal communication
- HTTPS egress for AWS services
- PostgreSQL egress for DSQL

Inter-service communication rules (e.g., Frontend -> History gRPC) should be defined in the environment's main.tf using `aws_security_group_rule` resources to avoid circular dependencies:

```hcl
# Frontend -> History (gRPC port 7234)
resource "aws_security_group_rule" "history_from_frontend" {
  type                     = "ingress"
  description              = "gRPC from Frontend service"
  from_port                = module.temporal_history.grpc_port
  to_port                  = module.temporal_history.grpc_port
  protocol                 = "tcp"
  source_security_group_id = module.temporal_frontend.security_group_id
  security_group_id        = module.temporal_history.security_group_id
}
```

## Service Connect

The module configures Service Connect with:
- gRPC endpoint (exposed for history, matching, frontend; not for worker)
- Metrics endpoint (exposed for all services)

Worker is a client-only service that connects to Frontend but doesn't expose discoverable gRPC endpoints.
