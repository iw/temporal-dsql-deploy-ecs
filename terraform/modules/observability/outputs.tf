# -----------------------------------------------------------------------------
# Observability Module - Outputs
# -----------------------------------------------------------------------------
# Requirements: 8.3
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Prometheus Outputs
# -----------------------------------------------------------------------------

output "prometheus_workspace_arn" {
  description = "ARN of the Amazon Managed Prometheus workspace"
  value       = aws_prometheus_workspace.main.arn
}

output "prometheus_remote_write_endpoint" {
  description = "Remote write endpoint for Amazon Managed Prometheus"
  value       = "${aws_prometheus_workspace.main.prometheus_endpoint}api/v1/remote_write"
}

output "prometheus_query_endpoint" {
  description = "Query endpoint for Amazon Managed Prometheus"
  value       = "${aws_prometheus_workspace.main.prometheus_endpoint}api/v1/query"
}

# -----------------------------------------------------------------------------
# Loki Outputs
# -----------------------------------------------------------------------------

output "loki_endpoint" {
  description = "Loki HTTP endpoint (via Service Connect)"
  value       = "http://loki:3100"
}

output "loki_s3_bucket_name" {
  description = "S3 bucket name for Loki storage"
  value       = aws_s3_bucket.loki.id
}

output "loki_s3_bucket_arn" {
  description = "S3 bucket ARN for Loki storage"
  value       = aws_s3_bucket.loki.arn
}

output "loki_security_group_id" {
  description = "Security group ID for Loki service"
  value       = aws_security_group.loki.id
}

# -----------------------------------------------------------------------------
# Grafana Outputs
# -----------------------------------------------------------------------------

output "grafana_service_name" {
  description = "ECS service name for Grafana"
  value       = aws_ecs_service.grafana.name
}

output "grafana_security_group_id" {
  description = "Security group ID for Grafana service"
  value       = aws_security_group.grafana.id
}
