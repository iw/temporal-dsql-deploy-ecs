# -----------------------------------------------------------------------------
# EC2 Capacity Module - Security Groups
# -----------------------------------------------------------------------------
# This file creates security groups for EC2 instances:
# - ECS instances security group with VPC-internal communication
# - Egress rules for AWS services and DSQL
#
# Requirements: 5.1
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Security Group for EC2 Instances
# -----------------------------------------------------------------------------

resource "aws_security_group" "ecs_instances" {
  name        = "${var.project_name}-${var.workload_type}-ecs-instances"
  description = "Security group for ECS EC2 instances (${var.workload_type})"
  vpc_id      = var.vpc_id

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
    Name = "${var.project_name}-${var.workload_type}-ecs-instances-sg"
  }
}
