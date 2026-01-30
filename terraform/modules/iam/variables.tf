# -----------------------------------------------------------------------------
# IAM Module - Input Variables
# -----------------------------------------------------------------------------
# Requirements: 11.2, 17.4
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "region" {
  description = "AWS region for constructing ARNs"
  type        = string
}

variable "dsql_cluster_arn" {
  description = "ARN of the Aurora DSQL cluster for IAM authentication"
  type        = string
}

variable "prometheus_workspace_arn" {
  description = "ARN of the Amazon Managed Prometheus workspace"
  type        = string
}

variable "opensearch_domain_arn" {
  description = "ARN of the OpenSearch domain for visibility"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for distributed rate limiting"
  type        = string
}

variable "conn_lease_table_arn" {
  description = "ARN of the DynamoDB table for distributed connection leasing (optional)"
  type        = string
  default     = ""
}

variable "conn_lease_enabled" {
  description = "Whether distributed connection leasing is enabled (determines if conn_lease IAM policy is created)"
  type        = bool
  default     = false
}

variable "grafana_admin_secret_arn" {
  description = "ARN of the Secrets Manager secret containing Grafana admin credentials"
  type        = string
}

variable "loki_s3_bucket_arn" {
  description = "ARN of the S3 bucket for Loki storage"
  type        = string
}
