# -----------------------------------------------------------------------------
# DynamoDB Module - Main Configuration
# -----------------------------------------------------------------------------
# This module creates DynamoDB tables for DSQL distributed rate limiting and
# connection leasing. The tables are used by the DSQL plugin to coordinate
# connection management across all Temporal service instances.
#
# Rate Limiter Table Schema:
# - pk (String): Partition key in format "dsqlconnect#<endpoint>#<unix_second>"
# - count (Number): Number of connections in this second
# - ttl_epoch (Number): TTL for automatic cleanup (3 minutes after creation)
#
# Connection Lease Table Schema:
# - pk (String): Partition key for connection lease entries
# - ttl_epoch (Number): TTL for automatic cleanup
#
# Both tables use on-demand billing, so costs are minimal when idle.
# Requirements: 11.1, 17.1, 17.6
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

# -----------------------------------------------------------------------------
# Connection Lease Table
# -----------------------------------------------------------------------------
# This table is used for distributed connection count limiting across all
# Temporal service instances. It ensures the cluster doesn't exceed DSQL's
# 10,000 max connections limit.
#
# Requirements: 17.1, 17.6
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "dsql_conn_lease" {
  count = var.conn_lease_enabled ? 1 : 0

  name         = "${var.project_name}-dsql-conn-lease"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  # Enable TTL for automatic cleanup of expired connection leases
  ttl {
    attribute_name = "ttl_epoch"
    enabled        = true
  }

  tags = {
    Name        = "${var.project_name}-dsql-conn-lease"
    Purpose     = "DSQL distributed connection leasing"
    Environment = var.project_name
  }
}
