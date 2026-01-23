#!/bin/bash
# Query Amazon Managed Prometheus
# Usage: ./scripts/query-amp.sh "promql_query"
# Example: ./scripts/query-amp.sh 'sum(rate(state_transition_count_sum[1m]))'
#
# For range queries with specific time periods, use awscurl directly:
#
#   WORKSPACE_ID=$(terraform -chdir=terraform output -raw prometheus_workspace_id)
#   REGION="eu-west-1"
#   awscurl --service aps --region "${REGION}" -X POST \
#     "https://aps-workspaces.${REGION}.amazonaws.com/workspaces/${WORKSPACE_ID}/api/v1/query_range" \
#     -H 'Content-Type: application/x-www-form-urlencoded' \
#     -d 'query=sum(rate(workflow_success_total{namespace="benchmark"}[1m]))&start=1769180700&end=1769181300&step=30s' | jq '.'
#
# Convert timestamps: date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "2026-01-23T15:05:00Z" +%s

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"

# Get workspace ID from Terraform
WORKSPACE_ID=$(terraform -chdir="${TF_DIR}" output -raw prometheus_workspace_id 2>/dev/null)
REGION=$(terraform -chdir="${TF_DIR}" output -raw region 2>/dev/null || echo "eu-west-1")

if [[ -z "${WORKSPACE_ID}" ]]; then
  echo "Error: Could not get prometheus_workspace_id from Terraform outputs"
  exit 1
fi

AMP_ENDPOINT="https://aps-workspaces.${REGION}.amazonaws.com/workspaces/${WORKSPACE_ID}"

QUERY="${1:-up}"

# Use POST to avoid URL encoding issues with awscurl
awscurl --service aps --region "${REGION}" -X POST \
  "${AMP_ENDPOINT}/api/v1/query" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "query=${QUERY}" | jq '.'
