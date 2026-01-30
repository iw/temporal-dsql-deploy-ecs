# Temporal UI Module

## Purpose

Creates the Temporal UI service for web-based workflow management. This module encapsulates the task definition, ECS service, security group, and CloudWatch log group for the Temporal web interface, configured to discover the temporal-frontend service via Service Connect.

The UI is a client-only service - it connects to Frontend but doesn't expose discoverable endpoints for other services.

## Inputs

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| project_name | string | Project name for resource naming | required |
| region | string | AWS region | required |
| cluster_id | string | ECS cluster ID | required |
| cluster_name | string | ECS cluster name | required |
| capacity_provider_name | string | ECS capacity provider name | required |
| service_connect_namespace_arn | string | Service Connect namespace ARN | required |
| vpc_id | string | VPC ID | required |
| vpc_cidr | string | VPC CIDR block for security group rules | required |
| subnet_ids | list(string) | Subnet IDs for ECS tasks | required |
| instance_security_group_id | string | Security group ID for ECS instances | required |
| execution_role_arn | string | ECS task execution role ARN | required |
| task_role_arn | string | ECS task role ARN for Temporal UI | required |
| image | string | Docker image URI for Temporal UI | required |
| cpu | number | CPU units for the task | 256 |
| memory | number | Memory in MB for the task | 512 |
| desired_count | number | Desired number of tasks | 1 |
| log_retention_days | number | CloudWatch log retention in days | 7 |
| alloy_init_container | any | Alloy init container definition | required |
| alloy_sidecar_container | any | Alloy sidecar container definition | required |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| service_name | string | ECS service name |
| task_definition_arn | string | Task definition ARN |
| security_group_id | string | Security group ID for the UI service |
| log_group_name | string | CloudWatch log group name |

## Usage Example

```hcl
# Create Alloy sidecar for UI
module "alloy_ui" {
  source = "../../modules/alloy-sidecar"

  project_name                     = var.project_name
  service_name                     = "temporal-ui"
  prometheus_remote_write_endpoint = module.observability.prometheus_remote_write_endpoint
  loki_endpoint                    = "${module.observability.loki_endpoint}/loki/api/v1/push"
  region                           = var.region
  alloy_image                      = var.alloy_image
}

module "temporal_ui" {
  source = "../../modules/temporal-ui"

  project_name                  = "temporal-dev"
  region                        = "eu-west-1"
  cluster_id                    = module.ecs_cluster.cluster_id
  cluster_name                  = module.ecs_cluster.cluster_name
  capacity_provider_name        = module.ec2_capacity.capacity_provider_name
  service_connect_namespace_arn = module.ecs_cluster.service_connect_namespace_arn
  vpc_id                        = module.vpc.vpc_id
  vpc_cidr                      = module.vpc.vpc_cidr
  subnet_ids                    = module.vpc.private_subnet_ids
  instance_security_group_id    = module.ec2_capacity.instance_security_group_id
  execution_role_arn            = module.iam.execution_role_arn
  task_role_arn                 = module.iam.temporal_ui_task_role_arn
  image                         = "temporalio/ui:latest"
  cpu                           = 256
  memory                        = 512
  desired_count                 = 1
  log_retention_days            = 7
  alloy_init_container          = module.alloy_ui.init_container_definition
  alloy_sidecar_container       = module.alloy_ui.sidecar_container_definition
}
```

## Architecture

The Temporal UI service:
- Runs on ARM64 (Graviton) architecture for cost efficiency
- Uses Service Connect in client-only mode to discover temporal-frontend
- Has no public access - use SSM port forwarding for remote access
- Includes health checks for HTTP endpoint monitoring
- Supports ECS Exec for debugging

## Access

Since the UI has no public access, use SSM port forwarding to access it:

```bash
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<task-ip>"],"portNumber":["8080"],"localPortNumber":["8080"]}'
```

Then access the UI at http://localhost:8080
