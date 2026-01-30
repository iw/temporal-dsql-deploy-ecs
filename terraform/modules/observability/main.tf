# -----------------------------------------------------------------------------
# Observability Module - Main Configuration
# -----------------------------------------------------------------------------
# This file creates the Amazon Managed Prometheus workspace for collecting
# Temporal metrics. Temporal services expose Prometheus metrics on port 9090
# and can be configured to remote write to this workspace.
#
# Requirements: 8.1
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Prometheus Workspace
# -----------------------------------------------------------------------------

resource "aws_prometheus_workspace" "main" {
  alias = "${var.project_name}-metrics"

  tags = {
    Name = "${var.project_name}-prometheus"
  }
}
