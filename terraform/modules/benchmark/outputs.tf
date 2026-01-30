# -----------------------------------------------------------------------------
# Benchmark Module - Outputs
# -----------------------------------------------------------------------------
# This file defines all outputs from the benchmark module.
#
# Requirements: 10.3
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Task Definition Outputs
# -----------------------------------------------------------------------------

output "task_definition_arn" {
  description = "ARN of the Benchmark task definition"
  value       = aws_ecs_task_definition.benchmark.arn
}

output "task_definition_family" {
  description = "Family of the Benchmark task definition"
  value       = aws_ecs_task_definition.benchmark.family
}

output "worker_task_definition_arn" {
  description = "ARN of the Benchmark Worker task definition"
  value       = aws_ecs_task_definition.benchmark_worker.arn
}

# -----------------------------------------------------------------------------
# Capacity Provider Outputs
# -----------------------------------------------------------------------------

output "capacity_provider_name" {
  description = "Name of the Benchmark ECS capacity provider"
  value       = aws_ecs_capacity_provider.benchmark.name
}

output "asg_name" {
  description = "Name of the Benchmark Auto Scaling Group"
  value       = aws_autoscaling_group.benchmark.name
}

# -----------------------------------------------------------------------------
# Service Outputs
# -----------------------------------------------------------------------------

output "generator_service_name" {
  description = "Name of the Benchmark Generator ECS service"
  value       = aws_ecs_service.benchmark_generator.name
}

output "worker_service_name" {
  description = "Name of the Benchmark Worker ECS service"
  value       = aws_ecs_service.benchmark_worker.name
}

# -----------------------------------------------------------------------------
# Security Group Outputs
# -----------------------------------------------------------------------------

output "security_group_id" {
  description = "ID of the Benchmark security group"
  value       = aws_security_group.benchmark.id
}

# -----------------------------------------------------------------------------
# IAM Outputs
# -----------------------------------------------------------------------------

output "task_role_arn" {
  description = "ARN of the Benchmark task role"
  value       = aws_iam_role.benchmark_task.arn
}

