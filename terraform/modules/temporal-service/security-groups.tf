# -----------------------------------------------------------------------------
# Temporal Service Module - Security Groups
# -----------------------------------------------------------------------------
# This file creates the security group for the Temporal service.
# The security group is parameterized based on service_type to configure
# the correct membership port for cluster communication.
#
# Note: Inter-service communication rules (e.g., Frontend -> History) are
# defined in the environment's main.tf using aws_security_group_rule resources
# to avoid circular dependencies between modules.
#
# Requirements: 6.1
# -----------------------------------------------------------------------------

resource "aws_security_group" "service" {
  name        = "${var.project_name}-${local.service_name}"
  description = "Security group for Temporal ${var.service_type} service"
  vpc_id      = var.vpc_id

  # Membership port for cluster communication (self-referencing)
  # Each service type has a different membership port
  ingress {
    description = "Membership port for cluster communication"
    from_port   = local.membership_port
    to_port     = local.membership_port
    protocol    = "tcp"
    self        = true
  }

  # Egress to VPC for internal communication
  egress {
    description = "Allow all traffic within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # HTTPS egress for AWS services (via VPC endpoints and NAT)
  egress {
    description = "HTTPS for AWS services"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # PostgreSQL egress for DSQL (port 5432)
  egress {
    description = "PostgreSQL for Aurora DSQL"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${local.service_name}-sg"
  }
}
