# DynamoDB Module

## Purpose

Creates a DynamoDB table for distributed DSQL connection rate limiting. This module provisions an on-demand DynamoDB table with TTL enabled for automatic cleanup of rate limit entries, enabling cluster-wide coordination of connection creation across all service instances.

## Inputs

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| project_name | string | Project name for resource naming | required |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| table_name | string | DynamoDB table name |
| table_arn | string | DynamoDB table ARN |

## Usage Example

```hcl
module "dynamodb" {
  source = "../../modules/dynamodb"

  project_name = "temporal-dev"
}
```
