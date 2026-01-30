# -----------------------------------------------------------------------------
# OpenSearch Module - Outputs
# -----------------------------------------------------------------------------
# Requirements: 9.3
# -----------------------------------------------------------------------------

output "domain_endpoint" {
  description = "OpenSearch domain endpoint (without https:// prefix)"
  value       = aws_opensearch_domain.temporal.endpoint
}

output "domain_arn" {
  description = "ARN of the OpenSearch domain"
  value       = aws_opensearch_domain.temporal.arn
}

output "security_group_id" {
  description = "Security group ID for the OpenSearch domain"
  value       = aws_security_group.opensearch.id
}

output "setup_task_definition_arn" {
  description = "ARN of the OpenSearch schema setup task definition"
  value       = aws_ecs_task_definition.opensearch_setup.arn
}

output "setup_security_group_id" {
  description = "Security group ID for the OpenSearch setup task"
  value       = aws_security_group.opensearch_setup.id
}

output "setup_task_role_arn" {
  description = "ARN of the IAM role for the OpenSearch setup task"
  value       = aws_iam_role.opensearch_setup_task.arn
}

output "log_group_name" {
  description = "CloudWatch log group name for OpenSearch setup task"
  value       = aws_cloudwatch_log_group.opensearch_setup.name
}
