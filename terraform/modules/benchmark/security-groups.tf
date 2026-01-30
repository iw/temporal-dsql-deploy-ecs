# -----------------------------------------------------------------------------
# Benchmark Security Groups
# -----------------------------------------------------------------------------
# Security group for benchmark runner with:
# - Ingress for metrics scraping from ADOT (port 9090)
# - Egress to Temporal Frontend via Service Connect
# - Egress to AWS services (CloudWatch Logs)
#
# Requirements: 10.1
# -----------------------------------------------------------------------------

resource "aws_security_group" "benchmark" {
  name        = "${var.project_name}-benchmark"
  description = "Security group for Benchmark Runner"
  vpc_id      = var.vpc_id

  # Egress to VPC for Service Connect communication with Temporal Frontend
  egress {
    description = "Allow all traffic within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # HTTPS egress for AWS services (CloudWatch Logs, etc.)
  egress {
    description = "HTTPS for AWS services"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-benchmark-sg"
  }
}

# Allow benchmark to connect to Temporal Frontend (gRPC port 7233)
resource "aws_security_group_rule" "frontend_from_benchmark" {
  type                     = "ingress"
  description              = "gRPC from Benchmark runner"
  from_port                = 7233
  to_port                  = 7233
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.benchmark.id
  security_group_id        = var.frontend_security_group_id
}

