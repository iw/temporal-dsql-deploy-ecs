# -----------------------------------------------------------------------------
# DynamoDB Table for DSQL Distributed Rate Limiter
# -----------------------------------------------------------------------------
# This table is used by the DSQL plugin to coordinate connection rate limiting
# across all Temporal service instances. It ensures the cluster-wide DSQL
# connection rate limit (100/sec) is respected even with multiple services.
#
# Table Schema:
# - pk (String): Partition key in format "dsqlconnect#<endpoint>#<unix_second>"
# - count (Number): Number of connections in this second
# - ttl_epoch (Number): TTL for automatic cleanup (3 minutes after creation)
#
# The table uses on-demand billing, so costs are minimal when idle.
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "dsql_rate_limiter" {
  name         = "${var.project_name}-dsql-rate-limiter"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  # Enable TTL for automatic cleanup of old rate limit entries
  ttl {
    attribute_name = "ttl_epoch"
    enabled        = true
  }

  tags = {
    Name        = "${var.project_name}-dsql-rate-limiter"
    Purpose     = "DSQL connection rate limiting"
    Environment = var.project_name
  }
}

# Output the table name for reference
output "dsql_rate_limiter_table_name" {
  description = "DynamoDB table name for DSQL distributed rate limiter"
  value       = aws_dynamodb_table.dsql_rate_limiter.name
}

output "dsql_rate_limiter_table_arn" {
  description = "DynamoDB table ARN for DSQL distributed rate limiter"
  value       = aws_dynamodb_table.dsql_rate_limiter.arn
}
