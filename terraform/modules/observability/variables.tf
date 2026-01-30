# -----------------------------------------------------------------------------
# Observability Module - Input Variables
# -----------------------------------------------------------------------------
# Requirements: 8.2
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# General Configuration
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "region" {
  description = "AWS region for deployment"
  type        = string
}

# -----------------------------------------------------------------------------
# VPC Configuration
# -----------------------------------------------------------------------------

variable "vpc_id" {
  description = "VPC ID for security groups"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block for security group rules"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for ECS services"
  type        = list(string)
}

# -----------------------------------------------------------------------------
# ECS Configuration
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

variable "instance_security_group_id" {
  description = "Security group ID for ECS instances"
  type        = string
}

variable "service_connect_namespace_arn" {
  description = "Service Connect namespace ARN"
  type        = string
}

# -----------------------------------------------------------------------------
# IAM Configuration
# -----------------------------------------------------------------------------

variable "execution_role_arn" {
  description = "ECS task execution role ARN"
  type        = string
}

variable "grafana_task_role_arn" {
  description = "Grafana task role ARN"
  type        = string
}

variable "loki_task_role_arn" {
  description = "Loki task role ARN (required when loki_enabled is true)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Grafana Configuration
# -----------------------------------------------------------------------------

variable "grafana_image" {
  description = "Grafana Docker image URI"
  type        = string
  default     = "grafana/grafana-oss:latest"
}

variable "grafana_cpu" {
  description = "CPU units for Grafana service"
  type        = number
  default     = 256
}

variable "grafana_memory" {
  description = "Memory in MB for Grafana service"
  type        = number
  default     = 512
}

variable "grafana_count" {
  description = "Desired task count for Grafana service"
  type        = number
  default     = 0
}

variable "grafana_admin_secret_name" {
  description = "Name of the Secrets Manager secret containing Grafana admin credentials"
  type        = string
}


# -----------------------------------------------------------------------------
# Loki Configuration
# -----------------------------------------------------------------------------

variable "loki_image" {
  description = "Loki Docker image URI"
  type        = string
  default     = "grafana/loki:3.6.4"
}

variable "loki_cpu" {
  description = "CPU units for Loki service"
  type        = number
  default     = 512
}

variable "loki_memory" {
  description = "Memory in MB for Loki service"
  type        = number
  default     = 1024
}

variable "loki_count" {
  description = "Desired task count for Loki service"
  type        = number
  default     = 0
}

variable "loki_retention_days" {
  description = "Log retention period in days for Loki"
  type        = number
  default     = 7
}

# -----------------------------------------------------------------------------
# Logging Configuration
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 7
}
