# -----------------------------------------------------------------------------
# IAM Module - Outputs
# -----------------------------------------------------------------------------
# Requirements: 11.3
# -----------------------------------------------------------------------------

output "execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_execution.arn
}

output "execution_role_name" {
  description = "Name of the ECS task execution role"
  value       = aws_iam_role.ecs_execution.name
}

output "temporal_task_role_arn" {
  description = "ARN of the Temporal services task role"
  value       = aws_iam_role.temporal_task.arn
}

output "temporal_task_role_name" {
  description = "Name of the Temporal services task role"
  value       = aws_iam_role.temporal_task.name
}

output "grafana_task_role_arn" {
  description = "ARN of the Grafana task role"
  value       = aws_iam_role.grafana_task.arn
}

output "grafana_task_role_name" {
  description = "Name of the Grafana task role"
  value       = aws_iam_role.grafana_task.name
}

output "loki_task_role_arn" {
  description = "ARN of the Loki task role"
  value       = aws_iam_role.loki_task.arn
}

output "loki_task_role_name" {
  description = "Name of the Loki task role"
  value       = aws_iam_role.loki_task.name
}

output "temporal_ui_task_role_arn" {
  description = "ARN of the Temporal UI task role"
  value       = aws_iam_role.temporal_ui_task.arn
}

output "temporal_ui_task_role_name" {
  description = "Name of the Temporal UI task role"
  value       = aws_iam_role.temporal_ui_task.name
}
