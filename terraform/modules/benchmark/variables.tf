# -----------------------------------------------------------------------------
# Benchmark Module - Input Variables
# -----------------------------------------------------------------------------
# This file defines all input variables for the benchmark module.
#
# Requirements: 10.2
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "cluster_id" {
  description = "ECS cluster ID"
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block for security group rules"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for benchmark tasks and instances"
  type        = list(string)
}

variable "service_connect_namespace_arn" {
  description = "Service Connect namespace ARN"
  type        = string
}

variable "execution_role_arn" {
  description = "ECS execution role ARN"
  type        = string
}

variable "prometheus_workspace_arn" {
  description = "Amazon Managed Prometheus workspace ARN"
  type        = string
}

variable "frontend_security_group_id" {
  description = "Temporal Frontend service security group ID"
  type        = string
}

variable "instance_security_group_id" {
  description = "ECS instances security group ID"
  type        = string
}

variable "instance_profile_arn" {
  description = "IAM instance profile ARN for EC2 instances"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

# -----------------------------------------------------------------------------
# Benchmark Image Configuration
# -----------------------------------------------------------------------------

variable "benchmark_image" {
  description = "Docker image URI for the benchmark runner (must be ARM64 compatible)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Benchmark Task Configuration
# -----------------------------------------------------------------------------

variable "cpu" {
  description = "CPU units for benchmark generator task"
  type        = number
  default     = 4096

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.cpu)
    error_message = "CPU must be a valid ECS CPU value: 256, 512, 1024, 2048, or 4096."
  }
}

variable "memory" {
  description = "Memory in MB for benchmark generator task"
  type        = number
  default     = 8192

  validation {
    condition     = var.memory >= 512 && var.memory <= 30720
    error_message = "Memory must be between 512 MB and 30720 MB."
  }
}

# -----------------------------------------------------------------------------
# Benchmark Worker Configuration
# -----------------------------------------------------------------------------

variable "worker_cpu" {
  description = "CPU units for benchmark worker task"
  type        = number
  default     = 4096

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.worker_cpu)
    error_message = "CPU must be a valid ECS CPU value."
  }
}

variable "worker_memory" {
  description = "Memory in MB for benchmark worker task"
  type        = number
  default     = 4096

  validation {
    condition     = var.worker_memory >= 512 && var.worker_memory <= 30720
    error_message = "Memory must be between 512 MB and 30720 MB."
  }
}

variable "worker_count" {
  description = "Number of benchmark worker tasks to run (0 to disable). Max 51 with 13 benchmark instances."
  type        = number
  default     = 0

  validation {
    condition     = var.worker_count >= 0 && var.worker_count <= 51
    error_message = "Worker count must be between 0 and 51."
  }
}

# -----------------------------------------------------------------------------
# EC2 Capacity Configuration
# -----------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type for benchmark nodes (Graviton recommended)"
  type        = string
  default     = "m8g.xlarge"
}

variable "max_instances" {
  description = "Maximum number of EC2 instances for benchmark workloads (scales from 0)"
  type        = number
  default     = 8

  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 20
    error_message = "Benchmark max instances must be between 1 and 20."
  }
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
  description = "Alloy init container definition for benchmark generator (from alloy-sidecar module)"
  type        = any
}

variable "alloy_sidecar_container" {
  description = "Alloy sidecar container definition for benchmark generator (from alloy-sidecar module)"
  type        = any
}

variable "alloy_worker_init_container" {
  description = "Alloy init container definition for benchmark worker (from alloy-sidecar module)"
  type        = any
}

variable "alloy_worker_sidecar_container" {
  description = "Alloy sidecar container definition for benchmark worker (from alloy-sidecar module)"
  type        = any
}

