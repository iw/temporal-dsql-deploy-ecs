# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------
# This file creates security groups for all services:
# - Temporal services (History, Matching, Frontend, Worker, UI)
# - Supporting services (Grafana, OpenSearch)
# - Inter-service communication rules
# 
# Security principles:
# - No inbound traffic from internet (0.0.0.0/0)
# - Specific security group references for inter-service communication
# - HTTPS egress for AWS service access
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Temporal History Service Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "temporal_history" {
  name        = "${var.project_name}-temporal-history"
  description = "Security group for Temporal History service"
  vpc_id      = aws_vpc.main.id

  # Membership port for cluster communication (self-referencing)
  ingress {
    description = "Membership port for cluster communication"
    from_port   = 6934
    to_port     = 6934
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
    Name = "${var.project_name}-temporal-history-sg"
  }
}

# -----------------------------------------------------------------------------
# Temporal Matching Service Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "temporal_matching" {
  name        = "${var.project_name}-temporal-matching"
  description = "Security group for Temporal Matching service"
  vpc_id      = aws_vpc.main.id

  # Membership port for cluster communication (self-referencing)
  ingress {
    description = "Membership port for cluster communication"
    from_port   = 6935
    to_port     = 6935
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

  # HTTPS egress for AWS services
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
    Name = "${var.project_name}-temporal-matching-sg"
  }
}

# -----------------------------------------------------------------------------
# Temporal Frontend Service Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "temporal_frontend" {
  name        = "${var.project_name}-temporal-frontend"
  description = "Security group for Temporal Frontend service"
  vpc_id      = aws_vpc.main.id

  # Membership port for cluster communication (self-referencing)
  ingress {
    description = "Membership port for cluster communication"
    from_port   = 6933
    to_port     = 6933
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

  # HTTPS egress for AWS services
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
    Name = "${var.project_name}-temporal-frontend-sg"
  }
}

# -----------------------------------------------------------------------------
# Temporal Worker Service Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "temporal_worker" {
  name        = "${var.project_name}-temporal-worker"
  description = "Security group for Temporal Worker service"
  vpc_id      = aws_vpc.main.id

  # Membership port for cluster communication (self-referencing)
  ingress {
    description = "Membership port for cluster communication"
    from_port   = 6939
    to_port     = 6939
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

  # HTTPS egress for AWS services
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
    Name = "${var.project_name}-temporal-worker-sg"
  }
}

# -----------------------------------------------------------------------------
# Temporal UI Service Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "temporal_ui" {
  name        = "${var.project_name}-temporal-ui"
  description = "Security group for Temporal UI service"
  vpc_id      = aws_vpc.main.id

  # No ingress from internet - access via SSM port forwarding only

  # Egress to VPC for internal communication (to Frontend)
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

  tags = {
    Name = "${var.project_name}-temporal-ui-sg"
  }
}

# -----------------------------------------------------------------------------
# Inter-Service Communication Rules
# -----------------------------------------------------------------------------
# These rules are defined separately to avoid circular dependencies
# between security groups.
# -----------------------------------------------------------------------------

# Frontend -> History (gRPC port 7234)
resource "aws_security_group_rule" "history_from_frontend" {
  type                     = "ingress"
  description              = "gRPC from Frontend service"
  from_port                = 7234
  to_port                  = 7234
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_frontend.id
  security_group_id        = aws_security_group.temporal_history.id
}

# Frontend -> Matching (gRPC port 7235)
resource "aws_security_group_rule" "matching_from_frontend" {
  type                     = "ingress"
  description              = "gRPC from Frontend service"
  from_port                = 7235
  to_port                  = 7235
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_frontend.id
  security_group_id        = aws_security_group.temporal_matching.id
}

# History -> Matching (gRPC port 7235)
resource "aws_security_group_rule" "matching_from_history" {
  type                     = "ingress"
  description              = "gRPC from History service"
  from_port                = 7235
  to_port                  = 7235
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_history.id
  security_group_id        = aws_security_group.temporal_matching.id
}

# History -> Matching (membership port 6935)
resource "aws_security_group_rule" "matching_membership_from_history" {
  type                     = "ingress"
  description              = "Membership from History service"
  from_port                = 6935
  to_port                  = 6935
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_history.id
  security_group_id        = aws_security_group.temporal_matching.id
}

# Matching -> History (gRPC port 7234)
resource "aws_security_group_rule" "history_from_matching" {
  type                     = "ingress"
  description              = "gRPC from Matching service"
  from_port                = 7234
  to_port                  = 7234
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_matching.id
  security_group_id        = aws_security_group.temporal_history.id
}

# Matching -> History (membership port 6934)
resource "aws_security_group_rule" "history_membership_from_matching" {
  type                     = "ingress"
  description              = "Membership from Matching service"
  from_port                = 6934
  to_port                  = 6934
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_matching.id
  security_group_id        = aws_security_group.temporal_history.id
}

# Frontend -> History (membership port 6934)
resource "aws_security_group_rule" "history_membership_from_frontend" {
  type                     = "ingress"
  description              = "Membership from Frontend service"
  from_port                = 6934
  to_port                  = 6934
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_frontend.id
  security_group_id        = aws_security_group.temporal_history.id
}

# Frontend -> Matching (membership port 6935)
resource "aws_security_group_rule" "matching_membership_from_frontend" {
  type                     = "ingress"
  description              = "Membership from Frontend service"
  from_port                = 6935
  to_port                  = 6935
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_frontend.id
  security_group_id        = aws_security_group.temporal_matching.id
}

# History -> Frontend (membership port 6933)
resource "aws_security_group_rule" "frontend_membership_from_history" {
  type                     = "ingress"
  description              = "Membership from History service"
  from_port                = 6933
  to_port                  = 6933
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_history.id
  security_group_id        = aws_security_group.temporal_frontend.id
}

# Matching -> Frontend (membership port 6933)
resource "aws_security_group_rule" "frontend_membership_from_matching" {
  type                     = "ingress"
  description              = "Membership from Matching service"
  from_port                = 6933
  to_port                  = 6933
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_matching.id
  security_group_id        = aws_security_group.temporal_frontend.id
}

# Worker -> Frontend (gRPC port 7233)
resource "aws_security_group_rule" "frontend_from_worker" {
  type                     = "ingress"
  description              = "gRPC from Worker service"
  from_port                = 7233
  to_port                  = 7233
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_worker.id
  security_group_id        = aws_security_group.temporal_frontend.id
}

# UI -> Frontend (gRPC port 7233)
resource "aws_security_group_rule" "frontend_from_ui" {
  type                     = "ingress"
  description              = "gRPC from UI service"
  from_port                = 7233
  to_port                  = 7233
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_ui.id
  security_group_id        = aws_security_group.temporal_frontend.id
}

# -----------------------------------------------------------------------------
# Worker Membership Rules (ringpop cluster communication)
# -----------------------------------------------------------------------------

# Worker -> Frontend (membership port 6933)
resource "aws_security_group_rule" "frontend_membership_from_worker" {
  type                     = "ingress"
  description              = "Membership from Worker service"
  from_port                = 6933
  to_port                  = 6933
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_worker.id
  security_group_id        = aws_security_group.temporal_frontend.id
}

# Worker -> History (membership port 6934)
resource "aws_security_group_rule" "history_membership_from_worker" {
  type                     = "ingress"
  description              = "Membership from Worker service"
  from_port                = 6934
  to_port                  = 6934
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_worker.id
  security_group_id        = aws_security_group.temporal_history.id
}

# Worker -> Matching (membership port 6935)
resource "aws_security_group_rule" "matching_membership_from_worker" {
  type                     = "ingress"
  description              = "Membership from Worker service"
  from_port                = 6935
  to_port                  = 6935
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_worker.id
  security_group_id        = aws_security_group.temporal_matching.id
}

# Frontend -> Worker (membership port 6939)
resource "aws_security_group_rule" "worker_membership_from_frontend" {
  type                     = "ingress"
  description              = "Membership from Frontend service"
  from_port                = 6939
  to_port                  = 6939
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_frontend.id
  security_group_id        = aws_security_group.temporal_worker.id
}

# History -> Worker (membership port 6939)
resource "aws_security_group_rule" "worker_membership_from_history" {
  type                     = "ingress"
  description              = "Membership from History service"
  from_port                = 6939
  to_port                  = 6939
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_history.id
  security_group_id        = aws_security_group.temporal_worker.id
}

# Matching -> Worker (membership port 6939)
resource "aws_security_group_rule" "worker_membership_from_matching" {
  type                     = "ingress"
  description              = "Membership from Matching service"
  from_port                = 6939
  to_port                  = 6939
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_matching.id
  security_group_id        = aws_security_group.temporal_worker.id
}

# Worker -> History (gRPC port 7234)
resource "aws_security_group_rule" "history_from_worker" {
  type                     = "ingress"
  description              = "gRPC from Worker service"
  from_port                = 7234
  to_port                  = 7234
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_worker.id
  security_group_id        = aws_security_group.temporal_history.id
}

# Worker -> Matching (gRPC port 7235)
resource "aws_security_group_rule" "matching_from_worker" {
  type                     = "ingress"
  description              = "gRPC from Worker service"
  from_port                = 7235
  to_port                  = 7235
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_worker.id
  security_group_id        = aws_security_group.temporal_matching.id
}


# -----------------------------------------------------------------------------
# Grafana Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "grafana" {
  name        = "${var.project_name}-grafana"
  description = "Security group for Grafana service"
  vpc_id      = aws_vpc.main.id

  # No ingress from internet - access via SSM port forwarding only

  # Egress to VPC for internal communication (to Prometheus endpoint)
  egress {
    description = "Allow all traffic within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # HTTPS egress for AWS services (Prometheus, etc.)
  egress {
    description = "HTTPS for AWS services"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-grafana-sg"
  }
}

# -----------------------------------------------------------------------------
# OpenSearch Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "opensearch" {
  name        = "${var.project_name}-opensearch"
  description = "Security group for OpenSearch domain"
  vpc_id      = aws_vpc.main.id

  # No ingress from internet - only from Temporal services

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
# OpenSearch Ingress Rules
# -----------------------------------------------------------------------------
# OpenSearch receives connections from Temporal History and Frontend services
# for visibility store operations.
# -----------------------------------------------------------------------------

# History -> OpenSearch (HTTPS port 443)
resource "aws_security_group_rule" "opensearch_from_history" {
  type                     = "ingress"
  description              = "HTTPS from History service"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_history.id
  security_group_id        = aws_security_group.opensearch.id
}

# Frontend -> OpenSearch (HTTPS port 443)
resource "aws_security_group_rule" "opensearch_from_frontend" {
  type                     = "ingress"
  description              = "HTTPS from Frontend service"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_frontend.id
  security_group_id        = aws_security_group.opensearch.id
}

# Matching -> OpenSearch (HTTPS port 443) - for visibility queries
resource "aws_security_group_rule" "opensearch_from_matching" {
  type                     = "ingress"
  description              = "HTTPS from Matching service"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_matching.id
  security_group_id        = aws_security_group.opensearch.id
}

# Worker -> OpenSearch (HTTPS port 443) - for visibility queries
resource "aws_security_group_rule" "opensearch_from_worker" {
  type                     = "ingress"
  description              = "HTTPS from Worker service"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.temporal_worker.id
  security_group_id        = aws_security_group.opensearch.id
}
