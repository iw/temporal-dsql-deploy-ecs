# -----------------------------------------------------------------------------
# Temporal Service Module - Input Variables
# -----------------------------------------------------------------------------
# This module creates a single Temporal service (History, Matching, Frontend,
# or Worker). The service_type variable determines the port mappings,
# environment variables, and Service Connect configuration.
#
# Requirements: 6.2, 6.3, 17.2, 17.3
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment_name" {
  description = "Environment name for dynamic config selection (dev, bench, prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "bench", "prod"], var.environment_name)
    error_message = "environment_name must be one of: dev, bench, prod"
  }
}

variable "service_type" {
  description = "Type of Temporal service (history, matching, frontend, worker)"
  type        = string

  validation {
    condition     = contains(["history", "matching", "frontend", "worker"], var.service_type)
    error_message = "service_type must be one of: history, matching, frontend, worker"
  }
}

variable "region" {
  description = "AWS region for CloudWatch logs and IAM auth"
  type        = string
}

# -----------------------------------------------------------------------------
# Container Configuration
# -----------------------------------------------------------------------------

variable "image" {
  description = "Docker image URI for Temporal service"
  type        = string
}

variable "cpu" {
  description = "CPU units for the task (1024 = 1 vCPU)"
  type        = number
  default     = 1024
}

variable "memory" {
  description = "Memory in MB for the task"
  type        = number
  default     = 2048
}

variable "desired_count" {
  description = "Number of task instances to run"
  type        = number
  default     = 0
}

# -----------------------------------------------------------------------------
# ECS Cluster Configuration
# -----------------------------------------------------------------------------

variable "cluster_id" {
  description = "ECS cluster ID"
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "capacity_provider_name" {
  description = "ECS capacity provider name"
  type        = string
}

variable "service_connect_namespace_arn" {
  description = "Service Connect namespace ARN"
  type        = string
}

# -----------------------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------------------

variable "vpc_id" {
  description = "VPC ID for security group"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block for security group egress rules"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for ECS service"
  type        = list(string)
}

variable "instance_security_group_id" {
  description = "Security group ID for ECS instances"
  type        = string
}

# -----------------------------------------------------------------------------
# IAM Configuration
# -----------------------------------------------------------------------------

variable "execution_role_arn" {
  description = "ECS execution role ARN"
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role ARN"
  type        = string
}

# -----------------------------------------------------------------------------
# DSQL Configuration
# -----------------------------------------------------------------------------

variable "dsql_endpoint" {
  description = "Aurora DSQL cluster endpoint"
  type        = string
}

variable "dsql_rate_limiter_table" {
  description = "DynamoDB table name for distributed DSQL rate limiting"
  type        = string
}

variable "dsql_max_conns" {
  description = "Maximum database connections per service instance"
  type        = number
  default     = 50
}

variable "dsql_max_idle_conns" {
  description = "Maximum idle database connections (should match dsql_max_conns)"
  type        = number
  default     = 50
}

variable "dsql_connection_rate_limit" {
  description = "Per-instance connection rate limit (connections/second)"
  type        = number
  default     = 8
}

variable "dsql_connection_burst_limit" {
  description = "Per-instance connection burst limit"
  type        = number
  default     = 40
}

# -----------------------------------------------------------------------------
# DSQL Connection Reservoir Configuration
# -----------------------------------------------------------------------------
# The Connection Reservoir is a channel-based buffer of pre-created connections
# that eliminates rate limit pressure in the request path. It's recommended for
# production deployments.
# Requirements: 17.2

variable "dsql_reservoir_enabled" {
  description = "Enable DSQL connection reservoir for rate-limit-aware connection management"
  type        = bool
  default     = false
}

variable "dsql_reservoir_target_ready" {
  description = "Target number of connections to maintain in the reservoir"
  type        = number
  default     = 50
}

variable "dsql_reservoir_base_lifetime" {
  description = "Base lifetime for connections in the reservoir (e.g., '11m')"
  type        = string
  default     = "11m"
}

variable "dsql_reservoir_lifetime_jitter" {
  description = "Random jitter range for connection lifetime (e.g., '2m')"
  type        = string
  default     = "2m"
}

variable "dsql_reservoir_guard_window" {
  description = "Guard window before connection expiry to discard connections (e.g., '45s')"
  type        = string
  default     = "45s"
}

# -----------------------------------------------------------------------------
# DSQL Distributed Connection Leasing Configuration
# -----------------------------------------------------------------------------
# For multi-service deployments, distributed connection leasing coordinates
# the global connection count across all service instances using DynamoDB.
# Requirements: 17.3

variable "dsql_distributed_conn_lease_enabled" {
  description = "Enable distributed connection leasing via DynamoDB"
  type        = bool
  default     = false
}

variable "dsql_conn_lease_table" {
  description = "DynamoDB table name for distributed connection leasing"
  type        = string
  default     = ""
}

variable "dsql_distributed_conn_limit" {
  description = "Global connection limit across all service instances"
  type        = number
  default     = 10000
}

# -----------------------------------------------------------------------------
# OpenSearch Configuration
# -----------------------------------------------------------------------------

variable "opensearch_endpoint" {
  description = "OpenSearch domain endpoint"
  type        = string
}

variable "opensearch_visibility_index" {
  description = "OpenSearch visibility index name"
  type        = string
}

# -----------------------------------------------------------------------------
# Temporal Configuration
# -----------------------------------------------------------------------------

variable "history_shards" {
  description = "Number of history shards"
  type        = number
  default     = 4096
}

variable "log_level" {
  description = "Temporal log level"
  type        = string
  default     = "info"
}

# -----------------------------------------------------------------------------
# Observability Configuration
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

variable "alloy_init_container" {
  description = "Alloy init container definition (from alloy-sidecar module)"
  type        = any
}

variable "alloy_sidecar_container" {
  description = "Alloy sidecar container definition (from alloy-sidecar module)"
  type        = any
}
