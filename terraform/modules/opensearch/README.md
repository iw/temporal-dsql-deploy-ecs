# OpenSearch Module

## Purpose

Creates an OpenSearch domain for Temporal visibility store functionality. This module provisions the OpenSearch cluster with VPC access, security groups, and includes a one-time schema setup task definition for initializing the visibility index.

## Features

- OpenSearch Provisioned domain with configurable instance type and count
- Single AZ deployment with VPC access
- Encryption at rest and node-to-node encryption
- HTTPS enforcement with TLS 1.2 minimum
- IAM-based access policy for Temporal services
- One-time schema setup task definition using temporal-elasticsearch-tool
- Security groups for domain and setup task

## Inputs

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| project_name | string | Project name for resource naming | required |
| region | string | AWS region for constructing ARNs | required |
| vpc_id | string | VPC ID for OpenSearch domain | required |
| vpc_cidr | string | VPC CIDR block for security group egress | required |
| subnet_ids | list(string) | Subnet IDs (first used for single-AZ) | required |
| visibility_index_name | string | Visibility index name to create | required |
| execution_role_arn | string | ECS execution role ARN for setup task | required |
| admin_tools_image | string | Temporal admin tools Docker image | required |
| temporal_task_role_arn | string | Temporal task role ARN for access policy | required |
| instance_type | string | OpenSearch instance type | "m6g.large.search" |
| instance_count | number | Number of OpenSearch instances | 3 |
| engine_version | string | OpenSearch engine version | "OpenSearch_2.11" |
| volume_size | number | EBS volume size in GiB per node | 100 |
| volume_iops | number | EBS volume IOPS (for gp3) | 3000 |
| volume_throughput | number | EBS volume throughput in MiB/s | 125 |
| log_retention_days | number | CloudWatch log retention in days | 7 |
| vpc_endpoints_security_group_id | string | VPC endpoints security group ID | "" |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| domain_endpoint | string | OpenSearch domain endpoint |
| domain_arn | string | OpenSearch domain ARN |
| security_group_id | string | OpenSearch domain security group ID |
| setup_task_definition_arn | string | Schema setup task definition ARN |
| setup_security_group_id | string | Setup task security group ID |
| setup_task_role_arn | string | Setup task IAM role ARN |
| log_group_name | string | CloudWatch log group name |

## Usage Example

```hcl
module "opensearch" {
  source = "../../modules/opensearch"

  project_name           = var.project_name
  region                 = var.region
  vpc_id                 = module.vpc.vpc_id
  vpc_cidr               = module.vpc.vpc_cidr
  subnet_ids             = module.vpc.private_subnet_ids
  visibility_index_name  = var.opensearch_visibility_index
  execution_role_arn     = module.iam.execution_role_arn
  admin_tools_image      = var.temporal_admin_tools_image
  temporal_task_role_arn = module.iam.temporal_task_role_arn

  # Optional overrides
  instance_type  = "m6g.large.search"
  instance_count = 3
}

# Add security group rules for Temporal services to access OpenSearch
resource "aws_security_group_rule" "opensearch_from_history" {
  type                     = "ingress"
  description              = "HTTPS from History service"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = module.temporal_history.security_group_id
  security_group_id        = module.opensearch.security_group_id
}

resource "aws_security_group_rule" "opensearch_from_frontend" {
  type                     = "ingress"
  description              = "HTTPS from Frontend service"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = module.temporal_frontend.security_group_id
  security_group_id        = module.opensearch.security_group_id
}
```

## Running the Setup Task

After deploying the OpenSearch domain, run the setup task to initialize the schema:

```bash
aws ecs run-task \
  --cluster <cluster-name> \
  --task-definition <setup-task-definition-arn> \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[<subnet-id>],securityGroups=[<setup-security-group-id>],assignPublicIp=DISABLED}"
```

## Notes

- The module creates a single-AZ deployment using the first subnet in the provided list
- Security group ingress rules from Temporal services must be created separately in the environment configuration
- The setup task uses Fargate with ARM64 architecture
- IAM authentication is used for OpenSearch access (no username/password)
