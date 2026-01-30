# -----------------------------------------------------------------------------
# EC2 Capacity Module - Input Variables
# -----------------------------------------------------------------------------
# This file defines all input variables for the EC2 capacity module.
#
# Requirements: 5.2
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name to join"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for security group"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block for security group rules"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for EC2 instances"
  type        = list(string)
}

# -----------------------------------------------------------------------------
# Optional Variables with Defaults
# -----------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type (Graviton recommended)"
  type        = string
  default     = "m7g.xlarge"
}

variable "instance_count" {
  description = "Desired number of EC2 instances"
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Minimum number of instances in ASG"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of instances in ASG"
  type        = number
  default     = null # Will default to instance_count + 2 if not specified
}

variable "workload_type" {
  description = "Workload identifier for resource naming (main/benchmark)"
  type        = string
  default     = "main"

  validation {
    condition     = contains(["main", "benchmark"], var.workload_type)
    error_message = "workload_type must be either 'main' or 'benchmark'"
  }
}

variable "ebs_volume_size" {
  description = "EBS volume size in GB"
  type        = number
  default     = 50
}

variable "protect_from_scale_in" {
  description = "Enable scale-in protection for ASG instances"
  type        = bool
  default     = true
}

variable "scaling_step_size" {
  description = "Maximum scaling step size for managed scaling"
  type        = number
  default     = 2
}

variable "target_capacity" {
  description = "Target capacity percentage for managed scaling"
  type        = number
  default     = 100
}
