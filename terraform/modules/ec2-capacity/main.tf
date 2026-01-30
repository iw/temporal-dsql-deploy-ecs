# -----------------------------------------------------------------------------
# EC2 Capacity Module - Main Configuration
# -----------------------------------------------------------------------------
# This module creates EC2 capacity provider infrastructure:
# - ECS-optimized ARM64 AMI for Graviton instances
# - Launch template with ECS configuration
# - Auto Scaling Group with configurable instance count
# - ECS capacity provider linked to ASG
#
# Benefits over Fargate:
# - Stable IPs for cluster membership (ringpop)
# - Host networking mode option
# - Better cost efficiency for sustained workloads
# - More control over instance placement
#
# Requirements: 5.1, 5.4, 5.5
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# ECS-Optimized AMI for ARM64
# -----------------------------------------------------------------------------

data "aws_ssm_parameter" "ecs_ami_arm64" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended/image_id"
}

# -----------------------------------------------------------------------------
# Launch Template for ECS Instances
# -----------------------------------------------------------------------------
# Single launch template for Temporal workloads
# ECS managed scaling handles task distribution across instances
# -----------------------------------------------------------------------------

resource "aws_launch_template" "ecs" {
  name_prefix   = "${var.project_name}-${var.workload_type}-ecs-"
  image_id      = data.aws_ssm_parameter.ecs_ami_arm64.value
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs_instance.arn
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ecs_instances.id]
    delete_on_termination       = true
  }

  # User data to join ECS cluster
  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo "ECS_CLUSTER=${var.cluster_name}" >> /etc/ecs/ecs.config
    echo "ECS_ENABLE_CONTAINER_METADATA=true" >> /etc/ecs/ecs.config
    echo "ECS_ENABLE_SPOT_INSTANCE_DRAINING=true" >> /etc/ecs/ecs.config
  EOF
  )

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.ebs_volume_size
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name     = "${var.project_name}-${var.workload_type}-ecs"
      Workload = var.workload_type
    }
  }

  tags = {
    Name = "${var.project_name}-${var.workload_type}-ecs-launch-template"
  }
}

# -----------------------------------------------------------------------------
# Auto Scaling Group
# -----------------------------------------------------------------------------
# ASG with configurable instance count for production workloads
# Spread across availability zones for high availability
# -----------------------------------------------------------------------------

resource "aws_autoscaling_group" "ecs" {
  name                = "${var.project_name}-${var.workload_type}-ecs-asg"
  desired_capacity    = var.instance_count
  min_size            = var.min_size
  max_size            = coalesce(var.max_size, var.instance_count + 2)
  vpc_zone_identifier = var.subnet_ids

  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }

  protect_from_scale_in = var.protect_from_scale_in

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.workload_type}-ecs"
    propagate_at_launch = true
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "Workload"
    value               = var.workload_type
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# ECS Capacity Provider
# -----------------------------------------------------------------------------
# Capacity provider for ECS services
# ECS managed scaling handles task placement across instances
# -----------------------------------------------------------------------------

resource "aws_ecs_capacity_provider" "ec2" {
  name = "${var.project_name}-${var.workload_type}-ec2"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = var.protect_from_scale_in ? "ENABLED" : "DISABLED"

    managed_scaling {
      maximum_scaling_step_size = var.scaling_step_size
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = var.target_capacity
    }
  }

  tags = {
    Name = "${var.project_name}-${var.workload_type}-ec2-capacity-provider"
  }
}
