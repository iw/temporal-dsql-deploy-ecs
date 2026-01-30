# -----------------------------------------------------------------------------
# OpenSearch Module - Input Variables
# -----------------------------------------------------------------------------
# Requirements: 9.2
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "region" {
  description = "AWS region for constructing ARNs and log configuration"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for OpenSearch domain and security groups"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block for security group egress rules"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for OpenSearch domain (first subnet will be used for single-AZ deployment)"
  type        = list(string)
}

variable "visibility_index_name" {
  description = "Name of the visibility index to create in OpenSearch"
  type        = string
}

variable "execution_role_arn" {
  description = "ARN of the ECS execution role for the setup task"
  type        = string
}

variable "admin_tools_image" {
  description = "Docker image URI for Temporal admin tools (used for schema setup)"
  type        = string
}

variable "temporal_task_role_arn" {
  description = "ARN of the Temporal task role for OpenSearch access policy"
  type        = string
}

# -----------------------------------------------------------------------------
# Optional Variables with Defaults
# -----------------------------------------------------------------------------

variable "instance_type" {
  description = "OpenSearch instance type"
  type        = string
  default     = "m6g.large.search"
}

variable "instance_count" {
  description = "Number of OpenSearch instances"
  type        = number
  default     = 3
}

variable "engine_version" {
  description = "OpenSearch engine version"
  type        = string
  default     = "OpenSearch_2.11"
}

variable "volume_size" {
  description = "EBS volume size in GiB per node"
  type        = number
  default     = 100
}

variable "volume_iops" {
  description = "EBS volume IOPS (for gp3)"
  type        = number
  default     = 3000
}

variable "volume_throughput" {
  description = "EBS volume throughput in MiB/s (for gp3)"
  type        = number
  default     = 125
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days for setup task logs"
  type        = number
  default     = 7
}

variable "vpc_endpoints_security_group_id" {
  description = "Security group ID for VPC endpoints (optional, for setup task egress)"
  type        = string
  default     = ""
}
