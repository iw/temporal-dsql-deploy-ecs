# -----------------------------------------------------------------------------
# Temporal Service Module - Outputs
# -----------------------------------------------------------------------------
# Requirements: 6.4
# -----------------------------------------------------------------------------

output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.service.name
}

output "service_arn" {
  description = "ECS service ARN"
  value       = aws_ecs_service.service.id
}

output "task_definition_arn" {
  description = "Task definition ARN"
  value       = aws_ecs_task_definition.service.arn
}

output "task_definition_family" {
  description = "Task definition family name"
  value       = aws_ecs_task_definition.service.family
}

output "security_group_id" {
  description = "Service security group ID"
  value       = aws_security_group.service.id
}

# -----------------------------------------------------------------------------
# Service-Specific Outputs
# -----------------------------------------------------------------------------
# These outputs provide service-specific information that may be needed
# for inter-service communication rules or monitoring configuration.

output "grpc_port" {
  description = "gRPC port for this service"
  value       = local.grpc_port
}

output "membership_port" {
  description = "Membership port for cluster communication"
  value       = local.membership_port
}

output "metrics_port" {
  description = "Prometheus metrics port"
  value       = local.metrics_port
}

output "service_type" {
  description = "Type of Temporal service (history, matching, frontend, worker)"
  value       = var.service_type
}
