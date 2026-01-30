# -----------------------------------------------------------------------------
# Temporal UI Module - Outputs
# -----------------------------------------------------------------------------
# Requirements: 7.4
# -----------------------------------------------------------------------------

output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.ui.name
}

output "task_definition_arn" {
  description = "Task definition ARN"
  value       = aws_ecs_task_definition.ui.arn
}

output "security_group_id" {
  description = "Security group ID for the UI service"
  value       = aws_security_group.ui.id
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.ui.name
}
