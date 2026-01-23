#!/bin/bash
# Query Aurora DSQL CloudWatch metrics
# Usage: ./scripts/query-dsql-metrics.sh [metric_name] [period_minutes]
# Example: ./scripts/query-dsql-metrics.sh CommitLatency 5
# Example: ./scripts/query-dsql-metrics.sh all 10

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"

# Get region from Terraform
REGION=$(terraform -chdir="${TF_DIR}" output -raw region 2>/dev/null || echo "eu-west-1")

# Get DSQL cluster ID from endpoint variable (format: cluster-id.dsql.region.on.aws)
DSQL_ENDPOINT=$(terraform -chdir="${TF_DIR}" output -json 2>/dev/null | jq -r '.dsql_cluster_endpoint.value // empty')
if [[ -z "${DSQL_ENDPOINT}" ]]; then
  # Fallback: get from tfvars
  DSQL_ENDPOINT=$(grep dsql_cluster_endpoint "${TF_DIR}/terraform.tfvars" 2>/dev/null | cut -d'"' -f2)
fi

if [[ -z "${DSQL_ENDPOINT}" ]]; then
  echo "Error: Could not determine DSQL cluster endpoint"
  exit 1
fi

# Extract cluster ID from endpoint (first segment before .dsql.)
CLUSTER_ID=$(echo "${DSQL_ENDPOINT}" | cut -d'.' -f1)

METRIC="${1:-CommitLatency}"
PERIOD_MINS="${2:-5}"

END_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
START_TIME=$(date -u -v-${PERIOD_MINS}M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "${PERIOD_MINS} minutes ago" +%Y-%m-%dT%H:%M:%SZ)

# Function to query a single metric
query_metric() {
  local metric_name="$1"
  aws cloudwatch get-metric-statistics \
    --namespace "AWS/AuroraDSQL" \
    --metric-name "${metric_name}" \
    --dimensions Name=ClusterIdentifier,Value="${CLUSTER_ID}" \
    --start-time "${START_TIME}" \
    --end-time "${END_TIME}" \
    --period 60 \
    --statistics Average Maximum Minimum Sum \
    --region "${REGION}" \
    --output table 2>/dev/null || echo "No data"
}

# If metric is "all", show all key metrics
if [[ "${METRIC}" == "all" ]]; then
  echo "=== DSQL Metrics Summary (last ${PERIOD_MINS} minutes) ==="
  echo "Cluster: ${CLUSTER_ID}"
  echo ""
  
  for m in CommitLatency OccConflicts TotalTransactions ReadOnlyTransactions; do
    echo "--- ${m} ---"
    query_metric "${m}"
    echo ""
  done
  exit 0
fi

echo "Querying ${METRIC} for last ${PERIOD_MINS} minutes..."
echo "Cluster: ${CLUSTER_ID}"
echo ""

query_metric "${METRIC}"
