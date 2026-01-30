# -----------------------------------------------------------------------------
# EC2 Capacity Module - Outputs
# -----------------------------------------------------------------------------
# This file defines all outputs from the EC2 capacity module.
#
# Requirements: 5.3
# -----------------------------------------------------------------------------

output "capacity_provider_name" {
  description = "Name of the ECS capacity provider"
  value       = aws_ecs_capacity_provider.ec2.name
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.ecs.name
}

output "asg_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.ecs.arn
}

output "instance_security_group_id" {
  description = "ID of the security group for EC2 instances"
  value       = aws_security_group.ecs_instances.id
}

output "instance_role_arn" {
  description = "ARN of the EC2 instance IAM role"
  value       = aws_iam_role.ecs_instance.arn
}

output "instance_role_name" {
  description = "Name of the EC2 instance IAM role"
  value       = aws_iam_role.ecs_instance.name
}

output "instance_profile_arn" {
  description = "ARN of the EC2 instance profile"
  value       = aws_iam_instance_profile.ecs_instance.arn
}

output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.ecs.id
}
