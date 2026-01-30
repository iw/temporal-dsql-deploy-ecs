# -----------------------------------------------------------------------------
# ECS Cluster Module - Outputs
# -----------------------------------------------------------------------------

output "cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "service_connect_namespace_arn" {
  description = "ARN of the Service Connect namespace"
  value       = aws_service_discovery_http_namespace.main.arn
}

output "ecs_exec_log_group_name" {
  description = "Name of the ECS Exec CloudWatch log group"
  value       = aws_cloudwatch_log_group.ecs_exec.name
}
