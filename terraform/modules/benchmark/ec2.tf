# -----------------------------------------------------------------------------
# Benchmark EC2 Infrastructure
# -----------------------------------------------------------------------------
# This file creates dedicated EC2 infrastructure for benchmark nodes:
# - Launch template for benchmark instances (same type as Temporal nodes)
# - Auto Scaling Group that scales from zero
# - ECS capacity provider for benchmark workloads
#
# Key features:
# - Scale-from-zero: No instances running when benchmarks are idle
# - Dedicated workload attribute: workload=benchmark
# - Same instance type as Temporal nodes for consistent measurements
#
# Requirements: 10.1, 10.4
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# ECS-Optimized AMI for ARM64
# -----------------------------------------------------------------------------

data "aws_ssm_parameter" "ecs_ami_arm64" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended/image_id"
}

# -----------------------------------------------------------------------------
# Launch Template for Benchmark Nodes
# -----------------------------------------------------------------------------
# Uses the same instance type as Temporal nodes for consistent performance
# measurements.
# Requirements: 10.1, 10.4

resource "aws_launch_template" "benchmark" {
  name_prefix   = "${var.project_name}-benchmark-"
  image_id      = data.aws_ssm_parameter.ecs_ami_arm64.value
  instance_type = var.instance_type

  iam_instance_profile {
    arn = var.instance_profile_arn
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.instance_security_group_id, aws_security_group.benchmark.id]
    delete_on_termination       = true
  }

  # User data to join ECS cluster with benchmark workload attribute
  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo "ECS_CLUSTER=${var.cluster_name}" >> /etc/ecs/ecs.config
    echo "ECS_ENABLE_CONTAINER_METADATA=true" >> /etc/ecs/ecs.config
    echo "ECS_ENABLE_SPOT_INSTANCE_DRAINING=true" >> /etc/ecs/ecs.config
    echo 'ECS_INSTANCE_ATTRIBUTES={"workload": "benchmark"}' >> /etc/ecs/ecs.config
  EOF
  )

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name     = "${var.project_name}-benchmark"
      Workload = "benchmark"
    }
  }

  tags = {
    Name = "${var.project_name}-benchmark-launch-template"
  }
}

# -----------------------------------------------------------------------------
# Auto Scaling Group for Benchmark Nodes
# -----------------------------------------------------------------------------
# Configured to scale from zero - no instances running when idle.
# ECS managed scaling will provision instances when benchmark tasks are scheduled.
# Requirements: 10.1, 10.4

resource "aws_autoscaling_group" "benchmark" {
  name                = "${var.project_name}-benchmark-asg"
  desired_capacity    = 0 # Scale from zero - no instances when idle
  min_size            = 0 # Allow scaling to zero
  max_size            = var.max_instances
  vpc_zone_identifier = var.subnet_ids

  launch_template {
    id      = aws_launch_template.benchmark.id
    version = "$Latest"
  }

  # Disable scale-in protection to allow scaling to zero
  protect_from_scale_in = false

  tag {
    key                 = "Name"
    value               = "${var.project_name}-benchmark"
    propagate_at_launch = true
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "Workload"
    value               = "benchmark"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# ECS Capacity Provider for Benchmark
# -----------------------------------------------------------------------------
# Links the ASG to ECS with managed scaling enabled.
# Requirements: 10.1, 10.4

resource "aws_ecs_capacity_provider" "benchmark" {
  name = "${var.project_name}-benchmark"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.benchmark.arn
    managed_termination_protection = "DISABLED" # Allow scaling to zero

    managed_scaling {
      maximum_scaling_step_size = var.max_instances
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }

  tags = {
    Name     = "${var.project_name}-benchmark-capacity-provider"
    Workload = "benchmark"
  }
}

