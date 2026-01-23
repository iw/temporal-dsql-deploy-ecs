# -----------------------------------------------------------------------------
# Input Variables
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# General Configuration
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# VPC Configuration
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# Temporal Image Configuration
# -----------------------------------------------------------------------------

variable "temporal_image" {
  description = "Custom Temporal Docker image URI (must be ARM64 compatible)"
  type        = string
}

variable "temporal_admin_tools_image" {
  description = "Custom Temporal admin-tools Docker image URI (must be ARM64 compatible, contains temporal-elasticsearch-tool)"
  type        = string
}

# -----------------------------------------------------------------------------
# Temporal History Service Configuration
# -----------------------------------------------------------------------------

variable "temporal_history_cpu" {
  description = "CPU units for History service (256, 512, 1024, 2048, 4096). Recommended: 4096 for high throughput (150+ WPS)"
  type        = number
  default     = 4096

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.temporal_history_cpu)
    error_message = "CPU must be a valid Fargate CPU value: 256, 512, 1024, 2048, or 4096."
  }
}

variable "temporal_history_memory" {
  description = "Memory in MB for History service (must be compatible with CPU value). Recommended: 8192 for high throughput"
  type        = number
  default     = 8192

  validation {
    condition     = var.temporal_history_memory >= 512 && var.temporal_history_memory <= 30720
    error_message = "Memory must be between 512 MB and 30720 MB (30 GB)."
  }
}

variable "temporal_history_count" {
  description = "Desired task count for History service (set to 0 initially, scale up after schema setup)"
  type        = number
  default     = 0

  validation {
    condition     = var.temporal_history_count >= 0
    error_message = "Task count must be 0 or greater."
  }
}

variable "temporal_history_shards" {
  description = "Number of history shards for Temporal cluster"
  type        = number
  default     = 4096

  validation {
    condition     = var.temporal_history_shards >= 1 && var.temporal_history_shards <= 16384
    error_message = "History shards must be between 1 and 16384."
  }
}


# -----------------------------------------------------------------------------
# Temporal Matching Service Configuration
# -----------------------------------------------------------------------------

variable "temporal_matching_cpu" {
  description = "CPU units for Matching service (256, 512, 1024, 2048, 4096). Recommended: 2048 for high-activity workloads"
  type        = number
  default     = 2048

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.temporal_matching_cpu)
    error_message = "CPU must be a valid Fargate CPU value: 256, 512, 1024, 2048, or 4096."
  }
}

variable "temporal_matching_memory" {
  description = "Memory in MB for Matching service (must be compatible with CPU value). Recommended: 4096 for high-activity workloads"
  type        = number
  default     = 4096

  validation {
    condition     = var.temporal_matching_memory >= 512 && var.temporal_matching_memory <= 30720
    error_message = "Memory must be between 512 MB and 30720 MB (30 GB)."
  }
}

variable "temporal_matching_count" {
  description = "Desired task count for Matching service (set to 0 initially, scale up after schema setup)"
  type        = number
  default     = 0

  validation {
    condition     = var.temporal_matching_count >= 0
    error_message = "Task count must be 0 or greater."
  }
}

# -----------------------------------------------------------------------------
# Temporal Frontend Service Configuration
# -----------------------------------------------------------------------------

variable "temporal_frontend_cpu" {
  description = "CPU units for Frontend service (256, 512, 1024, 2048, 4096). Recommended: 2048 for high throughput (150+ WPS)"
  type        = number
  default     = 2048

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.temporal_frontend_cpu)
    error_message = "CPU must be a valid Fargate CPU value: 256, 512, 1024, 2048, or 4096."
  }
}

variable "temporal_frontend_memory" {
  description = "Memory in MB for Frontend service (must be compatible with CPU value). Recommended: 4096 for high throughput"
  type        = number
  default     = 4096

  validation {
    condition     = var.temporal_frontend_memory >= 512 && var.temporal_frontend_memory <= 30720
    error_message = "Memory must be between 512 MB and 30720 MB (30 GB)."
  }
}

variable "temporal_frontend_count" {
  description = "Desired task count for Frontend service (set to 0 initially, scale up after schema setup)"
  type        = number
  default     = 0

  validation {
    condition     = var.temporal_frontend_count >= 0
    error_message = "Task count must be 0 or greater."
  }
}

# -----------------------------------------------------------------------------
# Temporal Worker Service Configuration
# -----------------------------------------------------------------------------

variable "temporal_worker_cpu" {
  description = "CPU units for Worker service (256, 512, 1024, 2048, 4096). Recommended: 512 for system workflows"
  type        = number
  default     = 512

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.temporal_worker_cpu)
    error_message = "CPU must be a valid Fargate CPU value: 256, 512, 1024, 2048, or 4096."
  }
}

variable "temporal_worker_memory" {
  description = "Memory in MB for Worker service (must be compatible with CPU value). Recommended: 1024 for system workflows"
  type        = number
  default     = 1024

  validation {
    condition     = var.temporal_worker_memory >= 512 && var.temporal_worker_memory <= 30720
    error_message = "Memory must be between 512 MB and 30720 MB (30 GB)."
  }
}

variable "temporal_worker_count" {
  description = "Desired task count for Worker service (set to 0 initially, scale up after schema setup)"
  type        = number
  default     = 0

  validation {
    condition     = var.temporal_worker_count >= 0
    error_message = "Task count must be 0 or greater."
  }
}

# -----------------------------------------------------------------------------
# Temporal UI Service Configuration
# -----------------------------------------------------------------------------

variable "temporal_ui_cpu" {
  description = "CPU units for UI service (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.temporal_ui_cpu)
    error_message = "CPU must be a valid Fargate CPU value: 256, 512, 1024, 2048, or 4096."
  }
}

variable "temporal_ui_memory" {
  description = "Memory in MB for UI service (must be compatible with CPU value)"
  type        = number
  default     = 512

  validation {
    condition     = var.temporal_ui_memory >= 512 && var.temporal_ui_memory <= 30720
    error_message = "Memory must be between 512 MB and 30720 MB (30 GB)."
  }
}

variable "temporal_ui_count" {
  description = "Desired task count for UI service (set to 0 initially, scale up after schema setup)"
  type        = number
  default     = 0

  validation {
    condition     = var.temporal_ui_count >= 0
    error_message = "Task count must be 0 or greater."
  }
}

variable "temporal_ui_image" {
  description = "Temporal UI Docker image URI"
  type        = string
  default     = "temporalio/ui:latest"
}

# -----------------------------------------------------------------------------
# Aurora DSQL Configuration
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# OpenSearch Configuration
# -----------------------------------------------------------------------------

variable "opensearch_visibility_index" {
  description = "OpenSearch visibility index name"
  type        = string
  default     = "temporal_visibility_v1_dev"
}

# -----------------------------------------------------------------------------
# Grafana Configuration
# -----------------------------------------------------------------------------

variable "grafana_admin_secret_name" {
  description = "Name of the Secrets Manager secret containing Grafana admin credentials (created externally)"
  type        = string
  default     = "grafana/admin"
}

variable "grafana_cpu" {
  description = "CPU units for Grafana service (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.grafana_cpu)
    error_message = "CPU must be a valid Fargate CPU value: 256, 512, 1024, 2048, or 4096."
  }
}

variable "grafana_memory" {
  description = "Memory in MB for Grafana service (must be compatible with CPU value)"
  type        = number
  default     = 512

  validation {
    condition     = var.grafana_memory >= 512 && var.grafana_memory <= 30720
    error_message = "Memory must be between 512 MB and 30720 MB (30 GB)."
  }
}

variable "grafana_count" {
  description = "Desired task count for Grafana service (set to 0 initially, scale up after schema setup)"
  type        = number
  default     = 0

  validation {
    condition     = var.grafana_count >= 0
    error_message = "Task count must be 0 or greater."
  }
}

variable "grafana_image" {
  description = "Grafana Docker image URI"
  type        = string
  default     = "grafana/grafana-oss:latest"
}

# -----------------------------------------------------------------------------
# Logging Configuration
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch Logs retention period (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, or 3653 days)."
  }
}

# -----------------------------------------------------------------------------
# tmpfs Configuration (ECS Fargate tmpfs mounts - January 2026 feature)
# -----------------------------------------------------------------------------

variable "temporal_dynamicconfig_tmpfs_size" {
  description = "Size in MiB for the dynamic config tmpfs mount. tmpfs provides memory-backed storage for faster config access and enhanced security (data doesn't persist after task stops)."
  type        = number
  default     = 1

  validation {
    condition     = var.temporal_dynamicconfig_tmpfs_size >= 1 && var.temporal_dynamicconfig_tmpfs_size <= 10
    error_message = "tmpfs size must be between 1 and 10 MiB for config files."
  }
}

# -----------------------------------------------------------------------------
# ADOT Collector Configuration
# -----------------------------------------------------------------------------

variable "adot_cpu" {
  description = "CPU units for ADOT Collector service (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.adot_cpu)
    error_message = "CPU must be a valid Fargate CPU value: 256, 512, 1024, 2048, or 4096."
  }
}

variable "adot_memory" {
  description = "Memory in MB for ADOT Collector service (must be compatible with CPU value)"
  type        = number
  default     = 512

  validation {
    condition     = var.adot_memory >= 512 && var.adot_memory <= 30720
    error_message = "Memory must be between 512 MB and 30720 MB (30 GB)."
  }
}


# -----------------------------------------------------------------------------
# EC2 Instance Configuration
# -----------------------------------------------------------------------------

variable "ec2_instance_type" {
  description = "EC2 instance type for ECS cluster (ARM64 Graviton recommended). m7g.xlarge provides 4 vCPUs, 16 GiB RAM, and 4 ENIs."
  type        = string
  default     = "m7g.xlarge"

  validation {
    condition     = can(regex("^[a-z][0-9][a-z]?g?\\.[a-z0-9]+$", var.ec2_instance_type))
    error_message = "Instance type must be a valid EC2 instance type."
  }
}

variable "ec2_instance_count" {
  description = "Number of EC2 instances in the ECS cluster. Recommended: 10 for 6k st/s golden config (14 History + 8 Matching + 6 Frontend + 3 Worker + UI/Grafana/ADOT = 34 tasks, needs 40 ENIs)"
  type        = number
  default     = 10

  validation {
    condition     = var.ec2_instance_count >= 1 && var.ec2_instance_count <= 20
    error_message = "Instance count must be between 1 and 20."
  }
}

variable "use_ec2_capacity" {
  description = "Use EC2 capacity provider instead of Fargate. When true, tasks run on EC2 instances."
  type        = bool
  default     = true
}


# -----------------------------------------------------------------------------
# Benchmark Configuration
# -----------------------------------------------------------------------------

variable "benchmark_image" {
  description = "Docker image URI for the benchmark runner (must be ARM64 compatible)"
  type        = string
  default     = ""
}

variable "benchmark_max_instances" {
  description = "Maximum number of EC2 instances for benchmark workloads (scales from 0). 15 instances with m8g.4xlarge = 240 vCPU for 60 workers."
  type        = number
  default     = 8

  validation {
    condition     = var.benchmark_max_instances >= 1 && var.benchmark_max_instances <= 20
    error_message = "Benchmark max instances must be between 1 and 20."
  }
}

variable "benchmark_cpu" {
  description = "CPU units for benchmark task (256, 512, 1024, 2048, 4096). For 100 WPS with embedded worker, use 4096."
  type        = number
  default     = 4096

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.benchmark_cpu)
    error_message = "CPU must be a valid ECS CPU value: 256, 512, 1024, 2048, or 4096."
  }
}

variable "benchmark_memory" {
  description = "Memory in MB for benchmark task (must be compatible with CPU value). For 100 WPS with embedded worker, use 8192."
  type        = number
  default     = 8192

  validation {
    condition     = var.benchmark_memory >= 512 && var.benchmark_memory <= 30720
    error_message = "Memory must be between 512 MB and 30720 MB (30 GB)."
  }
}
