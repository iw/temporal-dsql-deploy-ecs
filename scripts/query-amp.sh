#!/bin/bash
# Query Amazon Managed Prometheus
# Usage: ./scripts/query-amp.sh <environment> "promql_query"
# Example: ./scripts/query-amp.sh dev 'sum(rate(state_transition_count_sum[1m]))'

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
