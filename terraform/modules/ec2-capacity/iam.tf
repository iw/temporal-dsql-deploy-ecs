# -----------------------------------------------------------------------------
# EC2 Capacity Module - IAM Configuration
# -----------------------------------------------------------------------------
# This file creates IAM roles for EC2 instances:
# - ECS instance role for container agent operations
# - Instance profile for EC2 instances
# - Required policies for ECS, SSM, and DSQL access
#
# Requirements: 5.1
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# IAM Role for EC2 Instances
# -----------------------------------------------------------------------------

resource "aws_iam_role" "ecs_instance" {
  name = "${var.project_name}-${var.workload_type}-ecs-instance"

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
    Name = "${var.project_name}-${var.workload_type}-ecs-instance-role"
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
  name = "${var.project_name}-${var.workload_type}-ecs-instance-dsql"
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

# Instance profile for EC2 instances
resource "aws_iam_instance_profile" "ecs_instance" {
  name = "${var.project_name}-${var.workload_type}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance.name
}
