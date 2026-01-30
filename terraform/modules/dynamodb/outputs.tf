# -----------------------------------------------------------------------------
# DynamoDB Module - Outputs
# -----------------------------------------------------------------------------
# Requirements: 11.3, 17.6
# -----------------------------------------------------------------------------

output "table_name" {
  description = "DynamoDB table name for DSQL distributed rate limiter"
  value       = aws_dynamodb_table.dsql_rate_limiter.name
}

output "table_arn" {
  description = "DynamoDB table ARN for DSQL distributed rate limiter"
  value       = aws_dynamodb_table.dsql_rate_limiter.arn
}

output "conn_lease_table_name" {
  description = "DynamoDB table name for DSQL distributed connection leasing"
  value       = var.conn_lease_enabled ? aws_dynamodb_table.dsql_conn_lease[0].name : ""
}

output "conn_lease_table_arn" {
  description = "DynamoDB table ARN for DSQL distributed connection leasing"
  value       = var.conn_lease_enabled ? aws_dynamodb_table.dsql_conn_lease[0].arn : ""
}
