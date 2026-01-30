# -----------------------------------------------------------------------------
# Environment Variables - Dev Environment
# -----------------------------------------------------------------------------
# This file defines all variables needed by modules with dev-appropriate defaults.
# Dev environment uses minimal resources for cost-effective development.
#
# Requirements: 2.2, 2.4, 13.1
# -----------------------------------------------------------------------------

# =============================================================================
# GENERAL CONFIGURATION
# =============================================================================

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "temporal-dev"
}

variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "eu-west-1"
}

# =============================================================================
# VPC CONFIGURATION
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones for subnet distribution (minimum 2 for high availability)"
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones must be specified for high availability."
  }
}

variable "enable_vpc_endpoints" {
  description = "Create VPC endpoints for AWS services (ECR, SSM, Logs, etc.)"
  type        = bool
  default     = true
}

# =============================================================================
# EC2 INSTANCE CONFIGURATION
# =============================================================================

variable "ec2_instance_type" {
  description = "EC2 instance type for ECS cluster (ARM64 Graviton). Dev uses smaller instances."
  type        = string
  default     = "m8g.xlarge"

  validation {
    condition     = can(regex("^[a-z][0-9][a-z]?g?\\.[a-z0-9]+$", var.ec2_instance_type))
    error_message = "Instance type must be a valid EC2 instance type."
  }
}

variable "ec2_instance_count" {
  description = "Number of EC2 instances in the ECS cluster. Dev uses minimal instances."
  type        = number
  default     = 4

  validation {
    condition     = var.ec2_instance_count >= 1 && var.ec2_instance_count <= 20
    error_message = "Instance count must be between 1 and 20."
  }
}

# =============================================================================
# AURORA DSQL CONFIGURATION
# =============================================================================

variable "dsql_cluster_endpoint" {
  description = "Aurora DSQL cluster endpoint (created externally). Format: cluster-id.dsql.region.on.aws"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+\\.dsql\\.[a-z0-9-]+\\.on\\.aws$", var.dsql_cluster_endpoint))
    error_message = "DSQL cluster endpoint must be in format: cluster-id.dsql.region.on.aws"
  }
}

variable "dsql_cluster_arn" {
  description = "Aurora DSQL cluster ARN for IAM policy configuration. Format: arn:aws:dsql:region:account:cluster/cluster-id"
  type        = string

  validation {
    condition     = can(regex("^arn:aws:dsql:[a-z0-9-]+:[0-9]+:cluster/[a-z0-9-]+$", var.dsql_cluster_arn))
    error_message = "DSQL cluster ARN must be in format: arn:aws:dsql:region:account:cluster/cluster-id"
  }
}

# =============================================================================
# TEMPORAL IMAGE CONFIGURATION
# =============================================================================

variable "temporal_image" {
  description = "Custom Temporal Docker image URI (must be ARM64 compatible)"
  type        = string
}

variable "temporal_admin_tools_image" {
  description = "Custom Temporal admin-tools Docker image URI (must be ARM64 compatible)"
  type        = string
}

# =============================================================================
# TEMPORAL HISTORY SERVICE CONFIGURATION
# =============================================================================

variable "temporal_history_cpu" {
  description = "CPU units for History service. Dev uses smaller allocation."
  type        = number
  default     = 2048

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.temporal_history_cpu)
    error_message = "CPU must be a valid ECS CPU value: 256, 512, 1024, 2048, or 4096."
  }
}

variable "temporal_history_memory" {
  description = "Memory in MB for History service. Dev uses smaller allocation."
  type        = number
  default     = 4096

  validation {
    condition     = var.temporal_history_memory >= 512 && var.temporal_history_memory <= 30720
    error_message = "Memory must be between 512 MB and 30720 MB (30 GB)."
  }
}

variable "temporal_history_count" {
  description = "Desired task count for History service. Dev uses WPS 50 configuration."
  type        = number
  default     = 3

  validation {
    condition     = var.temporal_history_count >= 0
    error_message = "Task count must be 0 or greater."
  }
}

variable "temporal_history_shards" {
  description = "Number of history shards for Temporal cluster"
  type        = number
  default     = 2048

  validation {
    condition     = var.temporal_history_shards >= 1 && var.temporal_history_shards <= 16384
    error_message = "History shards must be between 1 and 16384."
  }
}

# =============================================================================
# TEMPORAL MATCHING SERVICE CONFIGURATION
# =============================================================================

variable "temporal_matching_cpu" {
  description = "CPU units for Matching service. Dev uses smaller allocation."
  type        = number
  default     = 1024

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.temporal_matching_cpu)
    error_message = "CPU must be a valid ECS CPU value: 256, 512, 1024, 2048, or 4096."
  }
}

variable "temporal_matching_memory" {
  description = "Memory in MB for Matching service. Dev uses smaller allocation."
  type        = number
  default     = 2048

  validation {
    condition     = var.temporal_matching_memory >= 512 && var.temporal_matching_memory <= 30720
    error_message = "Memory must be between 512 MB and 30720 MB (30 GB)."
  }
}

variable "temporal_matching_count" {
  description = "Desired task count for Matching service. Dev uses WPS 50 configuration."
  type        = number
  default     = 2

  validation {
    condition     = var.temporal_matching_count >= 0
    error_message = "Task count must be 0 or greater."
  }
}

# =============================================================================
# TEMPORAL FRONTEND SERVICE CONFIGURATION
# =============================================================================

variable "temporal_frontend_cpu" {
  description = "CPU units for Frontend service. Dev uses smaller allocation."
  type        = number
  default     = 1024

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.temporal_frontend_cpu)
    error_message = "CPU must be a valid ECS CPU value: 256, 512, 1024, 2048, or 4096."
  }
}

variable "temporal_frontend_memory" {
  description = "Memory in MB for Frontend service. Dev uses smaller allocation."
  type        = number
  default     = 2048

  validation {
    condition     = var.temporal_frontend_memory >= 512 && var.temporal_frontend_memory <= 30720
    error_message = "Memory must be between 512 MB and 30720 MB (30 GB)."
  }
}

variable "temporal_frontend_count" {
  description = "Desired task count for Frontend service. Dev uses WPS 50 configuration."
  type        = number
  default     = 2

  validation {
    condition     = var.temporal_frontend_count >= 0
    error_message = "Task count must be 0 or greater."
  }
}

# =============================================================================
# TEMPORAL WORKER SERVICE CONFIGURATION
# =============================================================================

variable "temporal_worker_cpu" {
  description = "CPU units for Worker service. Dev uses smaller allocation."
  type        = number
  default     = 512

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.temporal_worker_cpu)
    error_message = "CPU must be a valid ECS CPU value: 256, 512, 1024, 2048, or 4096."
  }
}

variable "temporal_worker_memory" {
  description = "Memory in MB for Worker service. Dev uses smaller allocation."
  type        = number
  default     = 1024

  validation {
    condition     = var.temporal_worker_memory >= 512 && var.temporal_worker_memory <= 30720
    error_message = "Memory must be between 512 MB and 30720 MB (30 GB)."
  }
}

variable "temporal_worker_count" {
  description = "Desired task count for Worker service. Dev uses WPS 50 configuration."
  type        = number
  default     = 2

  validation {
    condition     = var.temporal_worker_count >= 0
    error_message = "Task count must be 0 or greater."
  }
}

# =============================================================================
# TEMPORAL UI SERVICE CONFIGURATION
# =============================================================================

variable "temporal_ui_image" {
  description = "Temporal UI Docker image URI"
  type        = string
  default     = "temporalio/ui:latest"
}

variable "temporal_ui_cpu" {
  description = "CPU units for UI service"
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.temporal_ui_cpu)
    error_message = "CPU must be a valid ECS CPU value: 256, 512, 1024, 2048, or 4096."
  }
}

variable "temporal_ui_memory" {
  description = "Memory in MB for UI service"
  type        = number
  default     = 512

  validation {
    condition     = var.temporal_ui_memory >= 512 && var.temporal_ui_memory <= 30720
    error_message = "Memory must be between 512 MB and 30720 MB (30 GB)."
  }
}

variable "temporal_ui_count" {
  description = "Desired task count for UI service"
  type        = number
  default     = 1

  validation {
    condition     = var.temporal_ui_count >= 0
    error_message = "Task count must be 0 or greater."
  }
}

# =============================================================================
# OPENSEARCH CONFIGURATION
# =============================================================================

variable "opensearch_visibility_index" {
  description = "OpenSearch visibility index name"
  type        = string
  default     = "temporal_visibility_v1_dev"
}

variable "opensearch_instance_type" {
  description = "OpenSearch instance type. Dev uses smaller instances."
  type        = string
  default     = "m6g.large.search"
}

variable "opensearch_instance_count" {
  description = "Number of OpenSearch instances. Dev uses minimal count."
  type        = number
  default     = 2

  validation {
    condition     = var.opensearch_instance_count >= 1 && var.opensearch_instance_count <= 10
    error_message = "OpenSearch instance count must be between 1 and 10."
  }
}

# =============================================================================
# OBSERVABILITY CONFIGURATION
# =============================================================================

variable "loki_image" {
  description = "Loki Docker image URI (ARM64 compatible)"
  type        = string
  default     = "grafana/loki:3.6.4"
}

variable "loki_cpu" {
  description = "CPU units for Loki service"
  type        = number
  default     = 512

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.loki_cpu)
    error_message = "CPU must be a valid ECS CPU value: 256, 512, 1024, 2048, or 4096."
  }
}

variable "loki_memory" {
  description = "Memory in MB for Loki service"
  type        = number
  default     = 1024

  validation {
    condition     = var.loki_memory >= 512 && var.loki_memory <= 30720
    error_message = "Memory must be between 512 MB and 30720 MB (30 GB)."
  }
}

variable "loki_count" {
  description = "Desired task count for Loki service"
  type        = number
  default     = 1

  validation {
    condition     = var.loki_count >= 0
    error_message = "Task count must be 0 or greater."
  }
}

variable "loki_retention_days" {
  description = "Log retention period in days for Loki"
  type        = number
  default     = 7

  validation {
    condition     = var.loki_retention_days >= 1 && var.loki_retention_days <= 365
    error_message = "Retention days must be between 1 and 365."
  }
}

variable "alloy_image" {
  description = "Grafana Alloy Docker image URI (ARM64 compatible)"
  type        = string
  default     = "grafana/alloy:v1.12.2"
}

# =============================================================================
# GRAFANA CONFIGURATION
# =============================================================================

variable "grafana_admin_secret_name" {
  description = "Name of the Secrets Manager secret containing Grafana admin credentials"
  type        = string
  default     = "grafana/admin"
}

variable "grafana_image" {
  description = "Grafana Docker image URI"
  type        = string
  default     = "grafana/grafana-oss:latest"
}

variable "grafana_cpu" {
  description = "CPU units for Grafana service"
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.grafana_cpu)
    error_message = "CPU must be a valid ECS CPU value: 256, 512, 1024, 2048, or 4096."
  }
}

variable "grafana_memory" {
  description = "Memory in MB for Grafana service"
  type        = number
  default     = 512

  validation {
    condition     = var.grafana_memory >= 512 && var.grafana_memory <= 30720
    error_message = "Memory must be between 512 MB and 30720 MB (30 GB)."
  }
}

variable "grafana_count" {
  description = "Desired task count for Grafana service"
  type        = number
  default     = 1

  validation {
    condition     = var.grafana_count >= 0
    error_message = "Task count must be 0 or greater."
  }
}

# =============================================================================
# LOGGING CONFIGURATION
# =============================================================================

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch Logs retention period."
  }
}

# =============================================================================
# BENCHMARK CONFIGURATION
# =============================================================================

variable "benchmark_enabled" {
  description = "Enable benchmark infrastructure. Enabled in dev for testing at lower WPS targets."
  type        = bool
  default     = true
}

variable "benchmark_image" {
  description = "Docker image URI for the benchmark runner (must be ARM64 compatible)"
  type        = string
  default     = ""
}

variable "benchmark_cpu" {
  description = "CPU units for benchmark task. Dev uses smaller allocation."
  type        = number
  default     = 2048

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.benchmark_cpu)
    error_message = "CPU must be a valid ECS CPU value: 256, 512, 1024, 2048, or 4096."
  }
}

variable "benchmark_memory" {
  description = "Memory in MB for benchmark task. Dev uses smaller allocation."
  type        = number
  default     = 4096

  validation {
    condition     = var.benchmark_memory >= 512 && var.benchmark_memory <= 30720
    error_message = "Memory must be between 512 MB and 30720 MB (30 GB)."
  }
}

variable "benchmark_max_instances" {
  description = "Maximum number of EC2 instances for benchmark workloads. Dev uses minimal instances."
  type        = number
  default     = 4

  validation {
    condition     = var.benchmark_max_instances >= 1 && var.benchmark_max_instances <= 20
    error_message = "Benchmark max instances must be between 1 and 20."
  }
}

variable "benchmark_instance_type" {
  description = "EC2 instance type for benchmark nodes (ARM64 Graviton)"
  type        = string
  default     = "m8g.xlarge"

  validation {
    condition     = can(regex("^[a-z][0-9][a-z]?g?\\.[a-z0-9]+$", var.benchmark_instance_type))
    error_message = "Instance type must be a valid EC2 instance type."
  }
}

# =============================================================================
# DSQL CONNECTION RESERVOIR CONFIGURATION
# =============================================================================
# The Connection Reservoir is a channel-based buffer of pre-created connections
# that eliminates rate limit pressure in the request path. Enabled by default
# for consistent behavior across all environments.
# Requirements: 17.5

variable "dsql_reservoir_enabled" {
  description = "Enable DSQL connection reservoir for rate-limit-aware connection management."
  type        = bool
  default     = true
}

variable "dsql_reservoir_target_ready" {
  description = "Target number of connections to maintain in the reservoir"
  type        = number
  default     = 50

  validation {
    condition     = var.dsql_reservoir_target_ready >= 1 && var.dsql_reservoir_target_ready <= 200
    error_message = "Reservoir target ready must be between 1 and 200."
  }
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

# =============================================================================
# DSQL DISTRIBUTED CONNECTION LEASING CONFIGURATION
# =============================================================================
# For multi-service deployments, distributed connection leasing coordinates
# the global connection count across all service instances using DynamoDB.
# Enabled by default for consistent behavior across all environments.
# Requirements: 17.5

variable "dsql_distributed_conn_lease_enabled" {
  description = "Enable distributed connection leasing via DynamoDB."
  type        = bool
  default     = true
}

variable "dsql_distributed_conn_limit" {
  description = "Global connection limit across all service instances"
  type        = number
  default     = 10000

  validation {
    condition     = var.dsql_distributed_conn_limit >= 100 && var.dsql_distributed_conn_limit <= 20000
    error_message = "Distributed connection limit must be between 100 and 20000."
  }
}
