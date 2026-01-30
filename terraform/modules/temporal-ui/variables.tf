# -----------------------------------------------------------------------------
# Temporal UI Module - Input Variables
# -----------------------------------------------------------------------------
# Requirements: 7.2
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Project Configuration
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
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
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block for security group rules"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for ECS tasks"
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
  description = "ECS task execution role ARN"
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role ARN for Temporal UI"
  type        = string
}

# -----------------------------------------------------------------------------
# Container Configuration
# -----------------------------------------------------------------------------

variable "image" {
  description = "Docker image URI for Temporal UI"
  type        = string
}

variable "cpu" {
  description = "CPU units for the task"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Memory in MB for the task"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 1
}

# -----------------------------------------------------------------------------
# Logging Configuration
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

# -----------------------------------------------------------------------------
# Observability Configuration
# -----------------------------------------------------------------------------

variable "alloy_init_container" {
  description = "Alloy init container definition (from alloy-sidecar module)"
  type        = any
}

variable "alloy_sidecar_container" {
  description = "Alloy sidecar container definition (from alloy-sidecar module)"
  type        = any
}
