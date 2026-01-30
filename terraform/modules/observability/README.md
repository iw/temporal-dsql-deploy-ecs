# Observability Module

## Purpose

Creates the observability stack including Amazon Managed Prometheus workspace, Grafana ECS service, and Loki ECS service for log aggregation. This module provides comprehensive monitoring and visualization capabilities for the Temporal deployment.

## Components

- **Amazon Managed Prometheus**: Metrics collection and storage
- **Grafana**: Metrics visualization and dashboards
- **Loki**: Log aggregation with S3 storage backend

## Inputs

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| project_name | string | Project name for resource naming | required |
| region | string | AWS region | required |
| vpc_id | string | VPC ID | required |
| vpc_cidr | string | VPC CIDR block | required |
| subnet_ids | list(string) | Subnet IDs | required |
| cluster_id | string | ECS cluster ID | required |
| cluster_name | string | ECS cluster name | required |
| capacity_provider_name | string | Capacity provider name | required |
| instance_security_group_id | string | Instance SG ID | required |
| service_connect_namespace_arn | string | Service Connect namespace ARN | required |
| execution_role_arn | string | ECS execution role ARN | required |
| grafana_task_role_arn | string | Grafana task role ARN | required |
| loki_task_role_arn | string | Loki task role ARN | required |
| grafana_image | string | Grafana image | "grafana/grafana-oss:latest" |
| grafana_cpu | number | Grafana CPU units | 256 |
| grafana_memory | number | Grafana memory MB | 512 |
| grafana_count | number | Grafana task count | 0 |
| grafana_admin_secret_name | string | Secrets Manager secret name | required |
| loki_image | string | Loki image | "grafana/loki:3.6.4" |
| loki_cpu | number | Loki CPU units | 512 |
| loki_memory | number | Loki memory MB | 1024 |
| loki_count | number | Loki task count | 0 |
| loki_retention_days | number | Loki retention | 7 |
| log_retention_days | number | CloudWatch log retention | 7 |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| prometheus_workspace_arn | string | Prometheus workspace ARN |
| prometheus_remote_write_endpoint | string | Remote write endpoint |
| prometheus_query_endpoint | string | Query endpoint |
| loki_endpoint | string | Loki HTTP endpoint |
| loki_s3_bucket_name | string | Loki S3 bucket name |
| loki_s3_bucket_arn | string | Loki S3 bucket ARN |
| loki_security_group_id | string | Loki security group ID |
| grafana_service_name | string | Grafana ECS service name |
| grafana_security_group_id | string | Grafana security group ID |

## Usage Example

```hcl
module "observability" {
  source = "../../modules/observability"

  project_name                  = "temporal-dev"
  region                        = "eu-west-1"
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
  grafana_admin_secret_name     = "temporal-dev/grafana-admin"
  log_retention_days            = 7
}
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    OBSERVABILITY STACK                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐                    │
│  │     Grafana     │───▶│   Prometheus    │                    │
│  │   (ECS Service) │    │   (AMP)         │                    │
│  └────────┬────────┘    └─────────────────┘                    │
│           │                                                     │
│           │ log queries                                         │
│           ▼                                                     │
│  ┌─────────────────┐    ┌─────────────────┐                    │
│  │      Loki       │───▶│       S3        │                    │
│  │   (ECS Service) │    │   (Storage)     │                    │
│  └─────────────────┘    └─────────────────┘                    │
│           ▲                                                     │
│           │ log push                                            │
│  ┌────────┴────────┐                                           │
│  │  Alloy Sidecars │                                           │
│  │  (per service)  │                                           │
│  └─────────────────┘                                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Security Groups

The module creates security groups for:
- **Grafana**: Allows HTTPS egress for AWS services, includes Loki security group for log queries
- **Loki**: Allows ingress from Grafana on port 3100
