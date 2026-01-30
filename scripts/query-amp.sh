#!/bin/bash
# Query Amazon Managed Prometheus
# Usage: ./scripts/query-amp.sh <environment> "promql_query"
# Example: ./scripts/query-amp.sh dev 'sum(rate(state_transition_count_sum[1m]))'
#
# ============================================================================
# *Do not delete* - Manual range query example (timestamps in epoch seconds):
#
# AMP_BASE="https://aps-workspaces.eu-west-1.amazonaws.com/workspaces/<workspace-id>"
# awscurl --service aps --region eu-west-1 \
#   -X POST "${AMP_BASE}/api/v1/query_range" \
#   -H 'Content-Type: application/x-www-form-urlencoded' \
#   -d "query=histogram_quantile(0.95, sum by (le, job) (rate(persistence_latency_bucket[5m])))&start=1769781600&end=1769785200&step=60"
#
# Convert times: date -j -f "%Y-%m-%dT%H:%M:%SZ" "2026-01-30T14:00:00Z" +%s
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <environment> <promql_query>"
  echo "Example: $0 dev 'up'"
  echo "Example: $0 dev '{__name__=~\"state_transition.*\"}'"
  exit 1
fi

ENVIRONMENT="$1"
QUERY="$2"

ENV_DIR="$PROJECT_ROOT/terraform/envs/$ENVIRONMENT"
if [[ ! -d "$ENV_DIR" ]]; then
  echo "Error: Environment directory not found: $ENV_DIR"
  exit 1
fi

cd "$ENV_DIR"

WORKSPACE_ARN=$(terraform output -raw prometheus_workspace_arn 2>/dev/null)
WORKSPACE_ID=$(echo "$WORKSPACE_ARN" | grep -oE '[^/]+$')
REGION=$(terraform output -raw region 2>/dev/null || echo "eu-west-1")

if [[ -z "$WORKSPACE_ID" ]]; then
  echo "Error: Could not get prometheus workspace from Terraform outputs"
  exit 1
fi

AMP_ENDPOINT="https://aps-workspaces.${REGION}.amazonaws.com/workspaces/${WORKSPACE_ID}"

awscurl --service aps --region "${REGION}" -X POST \
  "${AMP_ENDPOINT}/api/v1/query" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "query=${QUERY}" | jq '.'
