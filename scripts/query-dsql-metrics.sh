#!/bin/bash
# Query Aurora DSQL CloudWatch metrics
# Usage: ./scripts/query-dsql-metrics.sh <environment> [metric_name] [period_minutes]
# Example: ./scripts/query-dsql-metrics.sh dev CommitLatency 5
# Example: ./scripts/query-dsql-metrics.sh bench all 10

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Available environments
AVAILABLE_ENVS=("dev" "bench" "prod")

# Parse arguments
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <environment> [metric_name] [period_minutes]"
  echo ""
  echo "Arguments:"
  echo "  environment    Environment to query (dev, bench, prod)"
  echo "  metric_name    Metric to query (default: CommitLatency, or 'all')"
  echo "  period_minutes Time period in minutes (default: 5)"
  echo ""
  echo "Examples:"
  echo "  $0 dev CommitLatency 5"
  echo "  $0 bench all 10"
  exit 1
fi

ENVIRONMENT="$1"
METRIC="${2:-CommitLatency}"
PERIOD_MINS="${3:-5}"

# Validate environment
valid=false
for env in "${AVAILABLE_ENVS[@]}"; do
  if [[ "$ENVIRONMENT" == "$env" ]]; then
    valid=true
    break
  fi
done

if [[ "$valid" == "false" ]]; then
  echo -e "${RED}Error: Invalid environment '$ENVIRONMENT'${NC}"
  echo "Available environments: ${AVAILABLE_ENVS[*]}"
  exit 1
fi

TF_DIR="${PROJECT_ROOT}/terraform/envs/${ENVIRONMENT}"

if [[ ! -d "$TF_DIR" ]]; then
  echo -e "${RED}Error: Environment directory not found: terraform/envs/$ENVIRONMENT${NC}"
  exit 1
fi

echo -e "${GREEN}Reading configuration from Terraform ($ENVIRONMENT environment)...${NC}"

# Get region from Terraform
REGION=$(terraform -chdir="${TF_DIR}" output -raw region 2>/dev/null || echo "eu-west-1")

# Get DSQL cluster ID from endpoint variable (format: cluster-id.dsql.region.on.aws)
DSQL_ENDPOINT=$(terraform -chdir="${TF_DIR}" output -raw dsql_cluster_endpoint 2>/dev/null || echo "")
if [[ -z "${DSQL_ENDPOINT}" ]]; then
  # Fallback: get from tfvars
  if [[ -f "${TF_DIR}/terraform.tfvars" ]]; then
    DSQL_ENDPOINT=$(grep -E "^dsql_cluster_endpoint" "${TF_DIR}/terraform.tfvars" 2>/dev/null | cut -d'"' -f2 || echo "")
  fi
fi

if [[ -z "${DSQL_ENDPOINT}" ]]; then
  echo -e "${RED}Error: Could not determine DSQL cluster endpoint${NC}"
  exit 1
fi

# Extract cluster ID from endpoint (first segment before .dsql.)
CLUSTER_ID=$(echo "${DSQL_ENDPOINT}" | cut -d'.' -f1)

echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
echo "Cluster: $CLUSTER_ID"
echo ""

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
  echo ""
  
  for m in CommitLatency OccConflicts TotalTransactions ReadOnlyTransactions; do
    echo "--- ${m} ---"
    query_metric "${m}"
    echo ""
  done
  exit 0
fi

echo "Querying ${METRIC} for last ${PERIOD_MINS} minutes..."
echo ""

query_metric "${METRIC}"
