# -----------------------------------------------------------------------------
# ECS on EC2 Cluster Configuration
# -----------------------------------------------------------------------------
# This file creates:
# - Launch template for m7g.xlarge Graviton instances
# - Auto Scaling Group with configurable instance count (default 6)
# - ECS capacity provider linked to ASG
# - IAM instance profile for EC2 instances
#
# Benefits over Fargate:
# - Stable IPs for cluster membership (ringpop)
# - Host networking mode option
# - Better cost efficiency for sustained workloads
# - More control over instance placement
#
# Production configuration:
# - 6 × m7g.xlarge instances (4 vCPU, 16 GiB each)
# - ECS managed scaling distributes tasks across instances
# - No workload-specific placement constraints for flexibility
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# ECS-Optimized AMI for ARM64
# -----------------------------------------------------------------------------

data "aws_ssm_parameter" "ecs_ami_arm64" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended/image_id"
}

# -----------------------------------------------------------------------------
# IAM Role for EC2 Instances
# -----------------------------------------------------------------------------

resource "aws_iam_role" "ecs_instance" {
  name = "${var.project_name}-ecs-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ecs-instance-role"
  }
}

# Attach required policies for ECS instances
resource "aws_iam_role_policy_attachment" "ecs_instance_role" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ssm" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# DSQL access for EC2 instances (needed for IAM auth)
resource "aws_iam_role_policy" "ecs_instance_dsql" {
  name = "${var.project_name}-ecs-instance-dsql"
  role = aws_iam_role.ecs_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dsql:DbConnect",
          "dsql:DbConnectAdmin"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "${var.project_name}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance.name
}

# -----------------------------------------------------------------------------
# Security Group for EC2 Instances
# -----------------------------------------------------------------------------

resource "aws_security_group" "ecs_instances" {
  name        = "${var.project_name}-ecs-instances"
  description = "Security group for ECS EC2 instances"
  vpc_id      = aws_vpc.main.id

  # Allow all traffic within the security group (for host networking)
  ingress {
    description = "All traffic from ECS instances"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Allow traffic from within VPC (for Service Connect and other services)
  ingress {
    description = "All traffic from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # Egress to VPC
  egress {
    description = "Allow all traffic within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # HTTPS egress for AWS services
  egress {
    description = "HTTPS for AWS services"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # PostgreSQL egress for DSQL
  egress {
    description = "PostgreSQL for Aurora DSQL"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ecs-instances-sg"
  }
}

# -----------------------------------------------------------------------------
# Launch Template for ECS Instances
# -----------------------------------------------------------------------------
# Single launch template for all Temporal workloads
# ECS managed scaling handles task distribution across instances
# -----------------------------------------------------------------------------

resource "aws_launch_template" "ecs" {
  name_prefix   = "${var.project_name}-ecs-"
  image_id      = data.aws_ssm_parameter.ecs_ami_arm64.value
  instance_type = var.ec2_instance_type

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
    echo "ECS_CLUSTER=${aws_ecs_cluster.main.name}" >> /etc/ecs/ecs.config
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
      volume_size           = 50
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-ecs"
    }
  }

  tags = {
    Name = "${var.project_name}-ecs-launch-template"
  }
}

# -----------------------------------------------------------------------------
# Auto Scaling Group
# -----------------------------------------------------------------------------
# Single ASG with configurable instance count for production workloads
# Default: 6 × m7g.xlarge instances spread across availability zones
# -----------------------------------------------------------------------------

resource "aws_autoscaling_group" "ecs" {
  name                = "${var.project_name}-ecs-asg"
  desired_capacity    = var.ec2_instance_count
  min_size            = 1
  max_size            = var.ec2_instance_count + 2
  vpc_zone_identifier = aws_subnet.private[*].id

  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }

  protect_from_scale_in = true

  tag {
    key                 = "Name"
    value               = "${var.project_name}-ecs"
    propagate_at_launch = true
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# ECS Capacity Provider
# -----------------------------------------------------------------------------
# Single capacity provider for all Temporal services
# ECS managed scaling handles task placement across instances
# -----------------------------------------------------------------------------

resource "aws_ecs_capacity_provider" "ec2" {
  name = "${var.project_name}-ec2"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "ENABLED"

    managed_scaling {
      maximum_scaling_step_size = 2
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }

  tags = {
    Name = "${var.project_name}-ec2-capacity-provider"
  }
}

# Associate capacity providers with cluster
# Note: Benchmark capacity provider is defined in benchmark-ec2.tf
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = [
    aws_ecs_capacity_provider.ec2.name,
    aws_ecs_capacity_provider.benchmark.name
  ]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 100
    base              = 1
  }
}
