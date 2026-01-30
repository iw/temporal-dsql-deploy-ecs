# IAM Module

## Purpose

Creates IAM roles and policies for ECS services. This module provisions the ECS execution role, Temporal task role, Grafana task role, Loki task role, and Temporal UI task role with least-privilege policies based on required AWS service access.

## Inputs

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| project_name | string | Project name for resource naming | required |
| region | string | AWS region | required |
| dsql_cluster_arn | string | DSQL cluster ARN | required |
| prometheus_workspace_arn | string | Prometheus workspace ARN | required |
| opensearch_domain_arn | string | OpenSearch domain ARN | required |
| dynamodb_table_arn | string | DynamoDB table ARN | required |
| conn_lease_table_arn | string | Connection lease table ARN | "" |
| conn_lease_enabled | bool | Enable connection lease IAM | false |
| grafana_admin_secret_arn | string | Grafana secret ARN | required |
| loki_s3_bucket_arn | string | Loki S3 bucket ARN | required |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| execution_role_arn | string | ECS execution role ARN |
| temporal_task_role_arn | string | Temporal task role ARN |
| grafana_task_role_arn | string | Grafana task role ARN |
| loki_task_role_arn | string | Loki task role ARN |
| temporal_ui_task_role_arn | string | Temporal UI task role ARN |

## Usage Example

```hcl
module "iam" {
  source = "../../modules/iam"

  project_name             = "temporal-dev"
  region                   = "eu-west-1"
  dsql_cluster_arn         = var.dsql_cluster_arn
  prometheus_workspace_arn = module.observability.prometheus_workspace_arn
  opensearch_domain_arn    = module.opensearch.domain_arn
  dynamodb_table_arn       = module.dynamodb.table_arn
  conn_lease_table_arn     = module.dynamodb.conn_lease_table_arn
  conn_lease_enabled       = var.dsql_distributed_conn_lease_enabled
  grafana_admin_secret_arn = data.aws_secretsmanager_secret.grafana_admin.arn
  loki_s3_bucket_arn       = module.observability.loki_s3_bucket_arn
}
```
