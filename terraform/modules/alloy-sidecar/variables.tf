# -----------------------------------------------------------------------------
# Alloy Sidecar Module - Input Variables
# -----------------------------------------------------------------------------
# Requirements: 12.2
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name for resource naming and SSM parameter paths"
  type        = string
}

variable "service_name" {
  description = "Service name for labeling (e.g., history, matching, frontend, worker)"
  type        = string
}

variable "prometheus_remote_write_endpoint" {
  description = "Amazon Managed Prometheus remote write endpoint URL"
  type        = string
}

variable "loki_endpoint" {
  description = "Loki push endpoint URL (e.g., http://loki:3100/loki/api/v1/push)"
  type        = string
}

variable "region" {
  description = "AWS region for SigV4 authentication and CloudWatch logs"
  type        = string
}

variable "alloy_image" {
  description = "Grafana Alloy container image"
  type        = string
  default     = "grafana/alloy:v1.12.2"
}
