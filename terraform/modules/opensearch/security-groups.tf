# -----------------------------------------------------------------------------
# OpenSearch Module - Security Groups
# -----------------------------------------------------------------------------
# This file creates security groups for the OpenSearch domain and setup task:
# - OpenSearch domain security group (receives connections from Temporal services)
# - OpenSearch setup task security group (for schema initialization)
#
# Note: Ingress rules from Temporal services are NOT defined here because
# they depend on Temporal service security groups which are created in
# separate modules. Those rules should be created in the environment's
# main.tf using aws_security_group_rule resources.
#
# Requirements: 9.1
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# OpenSearch Domain Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "opensearch" {
  name        = "${var.project_name}-opensearch"
  description = "Security group for OpenSearch domain"
  vpc_id      = var.vpc_id

  # No ingress from internet - only from Temporal services
  # Ingress rules are added by the environment configuration

  # Egress to VPC (typically not needed for OpenSearch but included for completeness)
  egress {
    description = "Allow all traffic within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.project_name}-opensearch-sg"
  }
}

# -----------------------------------------------------------------------------
# OpenSearch Setup Task Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "opensearch_setup" {
  name        = "${var.project_name}-opensearch-setup"
  description = "Security group for OpenSearch setup task"
  vpc_id      = var.vpc_id

  # Outbound to OpenSearch (HTTPS)
  egress {
    description     = "HTTPS to OpenSearch"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.opensearch.id]
  }

  # Outbound to VPC endpoints (for ECR, CloudWatch Logs, SSM)
  egress {
    description     = "HTTPS to VPC endpoints"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = var.vpc_endpoints_security_group_id != "" ? [var.vpc_endpoints_security_group_id] : []
  }

  # Outbound to S3 Gateway endpoint (for ECR image layers)
  # S3 Gateway endpoints use prefix lists, but we allow all HTTPS for simplicity
  egress {
    description = "HTTPS to S3 (ECR image layers)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-opensearch-setup-sg"
  }
}

# Allow OpenSearch to receive connections from setup task
resource "aws_security_group_rule" "opensearch_from_setup" {
  type                     = "ingress"
  description              = "HTTPS from OpenSearch setup task"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.opensearch_setup.id
  security_group_id        = aws_security_group.opensearch.id
}
