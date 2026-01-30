# ECS Cluster Module

## Purpose

Creates an ECS cluster with Service Connect namespace and Container Insights enabled. This module provides the compute orchestration layer for running Temporal services and supporting infrastructure.

## Inputs

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| project_name | string | Project name for resource naming | required |
| log_retention_days | number | CloudWatch log retention | 7 |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| cluster_id | string | ID of ECS cluster |
| cluster_arn | string | ARN of ECS cluster |
| cluster_name | string | Name of ECS cluster |
| service_connect_namespace_arn | string | ARN of Service Connect namespace |
| ecs_exec_log_group_name | string | Name of ECS Exec log group |

## Usage Example

```hcl
module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  project_name       = "temporal-dev"
  log_retention_days = 7
}
```
