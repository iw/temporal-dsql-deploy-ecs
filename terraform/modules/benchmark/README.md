# Benchmark Module

## Purpose

Creates dedicated benchmark infrastructure for performance testing Temporal deployments. This module includes the benchmark task definition, benchmark worker service, and a separate EC2 capacity provider with scale-from-zero capability to avoid resource contention with production workloads.

## Architecture

The benchmark system uses a separated generator/worker architecture:
- **Generator Task**: One-shot ECS task that submits workflows at the target rate
- **Worker Service**: Long-running ECS service that processes benchmark workflows

This separation allows independent scaling of workers to handle high WPS loads without resource contention.

## Inputs

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| project_name | string | Project name | required |
| cluster_id | string | ECS cluster ID | required |
| cluster_name | string | ECS cluster name | required |
| vpc_id | string | VPC ID | required |
| vpc_cidr | string | VPC CIDR block | required |
| subnet_ids | list(string) | Subnet IDs | required |
| service_connect_namespace_arn | string | Service Connect namespace ARN | required |
| execution_role_arn | string | ECS execution role ARN | required |
| prometheus_workspace_arn | string | Prometheus workspace ARN | required |
| frontend_security_group_id | string | Frontend service security group ID | required |
| instance_security_group_id | string | ECS instances security group ID | required |
| instance_profile_arn | string | IAM instance profile ARN | required |
| benchmark_image | string | Benchmark Docker image | "" |
| cpu | number | CPU units for generator | 4096 |
| memory | number | Memory in MB for generator | 8192 |
| worker_cpu | number | CPU units for worker | 4096 |
| worker_memory | number | Memory in MB for worker | 4096 |
| worker_count | number | Number of worker tasks | 0 |
| instance_type | string | EC2 instance type | "m7g.xlarge" |
| max_instances | number | Maximum benchmark EC2 instances | 8 |
| log_retention_days | number | Log retention | 7 |
| alloy_init_container | any | Alloy init container definition | required |
| alloy_sidecar_container | any | Alloy sidecar container definition | required |
| alloy_worker_init_container | any | Alloy worker init container definition | required |
| alloy_worker_sidecar_container | any | Alloy worker sidecar container definition | required |
| region | string | AWS region | required |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| task_definition_arn | string | Benchmark generator task definition ARN |
| task_definition_family | string | Benchmark generator task definition family |
| worker_task_definition_arn | string | Benchmark worker task definition ARN |
| capacity_provider_name | string | Benchmark capacity provider name |
| asg_name | string | Benchmark Auto Scaling Group name |
| worker_service_name | string | Benchmark worker service name |
| security_group_id | string | Benchmark security group ID |
| task_role_arn | string | Benchmark task role ARN |
| log_group_name | string | Benchmark log group name |
| worker_log_group_name | string | Benchmark worker log group name |

## Usage Example

```hcl
module "benchmark" {
  source = "../../modules/benchmark"

  project_name                  = "temporal-bench"
  cluster_id                    = module.ecs_cluster.cluster_id
  cluster_name                  = module.ecs_cluster.cluster_name
  vpc_id                        = module.vpc.vpc_id
  vpc_cidr                      = module.vpc.vpc_cidr
  subnet_ids                    = module.vpc.private_subnet_ids
  service_connect_namespace_arn = module.ecs_cluster.service_connect_namespace_arn
  execution_role_arn            = module.iam.execution_role_arn
  prometheus_workspace_arn      = module.observability.prometheus_workspace_arn
  frontend_security_group_id    = module.temporal_frontend.security_group_id
  instance_security_group_id    = module.ec2_capacity.instance_security_group_id
  instance_profile_arn          = module.ec2_capacity.instance_profile_arn
  benchmark_image               = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/benchmark:latest"
  cpu                           = 4096
  memory                        = 8192
  worker_cpu                    = 4096
  worker_memory                 = 4096
  worker_count                  = 0
  max_instances                 = 8
  log_retention_days            = 7
  region                        = "eu-west-1"
}
```

## Scale-from-Zero

The benchmark EC2 capacity provider is configured to scale from zero:
- No instances running when benchmarks are idle
- ECS managed scaling provisions instances when benchmark tasks are scheduled
- Instances are terminated when no longer needed

This minimizes costs when benchmarks are not running.

## Worker Scaling Recommendations

| Target WPS | Workers | Notes |
|------------|---------|-------|
| 100 | 30 | Conservative |
| 200 | 40 | Moderate |
| 400 | 51 | Max with current quota |

