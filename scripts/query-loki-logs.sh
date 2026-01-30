#!/bin/bash
# -----------------------------------------------------------------------------
# Query logs from Loki via SSM port forwarding
# -----------------------------------------------------------------------------
#
# Usage:
#   ./scripts/query-loki-logs.sh <environment> <service> [OPTIONS]
#
# Arguments:
#   environment     Environment (dev, bench, prod)
#   service         Service name (frontend, history, matching, worker, benchmark, etc.)
#
# Options:
#   -q, --query     Custom LogQL query (overrides service argument)
#   -l, --limit     Number of log lines to return [default: 100]
#   -t, --time      Time range (e.g., 5m, 1h, 24h) [default: 10m]
#   -f, --filter    Filter pattern (grep-style)
#   --level         Log level filter (info, warn, error)
#   --raw           Output raw JSON instead of formatted logs
#   -h, --help      Show this help message
#
# Examples:
#   ./scripts/query-loki-logs.sh dev frontend
#   ./scripts/query-loki-logs.sh dev history -t 5m
#   ./scripts/query-loki-logs.sh bench benchmark --level error
#   ./scripts/query-loki-logs.sh dev frontend -f "visibility"
#
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Available environments
AVAILABLE_ENVS=("dev" "bench" "prod")

# Default values
ENVIRONMENT=""
SERVICE=""
QUERY=""
LIMIT=100
TIME_RANGE="10m"
FILTER=""
LEVEL=""
RAW_OUTPUT=false
LOCAL_PORT=3100

show_usage() {
    head -28 "$0" | tail -26
    exit 0
}

validate_environment() {
    local env="$1"
    local valid=false
    for available_env in "${AVAILABLE_ENVS[@]}"; do
        if [ "$env" = "$available_env" ]; then
            valid=true
            break
        fi
    done
    
    if [ "$valid" = false ]; then
        echo -e "${RED}Error: Invalid environment '$env'${NC}"
        echo "Available environments: ${AVAILABLE_ENVS[*]}"
        exit 1
    fi
}

# Parse arguments - first two positional args are environment and service
POSITIONAL_COUNT=0
while [[ $# -gt 0 ]]; do
    case $1 in
        dev|bench|prod)
            if [ -z "$ENVIRONMENT" ]; then
                ENVIRONMENT="$1"
                POSITIONAL_COUNT=$((POSITIONAL_COUNT + 1))
            fi
            shift
            ;;
        -q|--query)
            QUERY="$2"
            shift 2
            ;;
        -l|--limit)
            LIMIT="$2"
            shift 2
            ;;
        -t|--time)
            TIME_RANGE="$2"
            shift 2
            ;;
        -f|--filter)
            FILTER="$2"
            shift 2
            ;;
        --level)
            LEVEL="$2"
            shift 2
            ;;
        --raw)
            RAW_OUTPUT=true
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        -*)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
        *)
            # Second positional argument is service
            if [ -n "$ENVIRONMENT" ] && [ -z "$SERVICE" ]; then
                SERVICE="$1"
                POSITIONAL_COUNT=$((POSITIONAL_COUNT + 1))
            fi
            shift
            ;;
    esac
done

# Validate required arguments
if [ -z "$ENVIRONMENT" ]; then
    echo -e "${RED}Error: Environment is required${NC}"
    echo ""
    echo "Usage: $0 <environment> <service> [OPTIONS]"
    echo "Available environments: ${AVAILABLE_ENVS[*]}"
    exit 1
fi

validate_environment "$ENVIRONMENT"

if [ -z "$SERVICE" ] && [ -z "$QUERY" ]; then
    echo -e "${RED}Error: Service name is required (or use --query for custom LogQL)${NC}"
    echo ""
    echo "Usage: $0 <environment> <service> [OPTIONS]"
    echo "Services: frontend, history, matching, worker, benchmark, ui, grafana, loki, alloy"
    exit 1
fi

# Get terraform values
ENV_DIR="$PROJECT_ROOT/terraform/envs/$ENVIRONMENT"
if [ ! -d "$ENV_DIR" ]; then
    echo -e "${RED}Error: Environment directory not found: $ENV_DIR${NC}"
    exit 1
fi

cd "$ENV_DIR"

CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null) || {
    echo -e "${RED}Error: Could not get cluster name from terraform${NC}"
    exit 1
}

REGION=$(terraform output -raw region 2>/dev/null || echo "eu-west-1")

cd "$PROJECT_ROOT"

# Build LogQL query if not provided
if [[ -z "$QUERY" ]]; then
    QUERY="{service_name=\"${SERVICE}\"}"
    
    # Add level filter
    if [[ -n "$LEVEL" ]]; then
        QUERY="${QUERY} | level=\"${LEVEL}\""
    fi
    
    # Add text filter
    if [[ -n "$FILTER" ]]; then
        QUERY="${QUERY} |= \"${FILTER}\""
    fi
fi

echo "=== Loki Log Query ===" >&2
echo "Environment: $ENVIRONMENT" >&2
echo "Cluster: $CLUSTER_NAME" >&2
echo "Query: $QUERY" >&2
echo "Time range: $TIME_RANGE" >&2
echo "Limit: $LIMIT" >&2
echo "" >&2

# Get Loki task info
LOKI_SERVICE="${CLUSTER_NAME%-cluster}-loki"
TASK_ARN=$(aws ecs list-tasks --cluster "$CLUSTER_NAME" --service-name "$LOKI_SERVICE" --query 'taskArns[0]' --output text --region "$REGION" 2>/dev/null)

if [[ -z "$TASK_ARN" || "$TASK_ARN" == "None" ]]; then
    echo -e "${RED}Error: Loki service not found in cluster $CLUSTER_NAME${NC}" >&2
    exit 1
fi

TASK_ID=$(echo "$TASK_ARN" | cut -d'/' -f3)
RUNTIME_ID=$(aws ecs describe-tasks --cluster "$CLUSTER_NAME" --tasks "$TASK_ARN" --query 'tasks[0].containers[?name==`loki`].runtimeId' --output text --region "$REGION")

if [[ -z "$RUNTIME_ID" || "$RUNTIME_ID" == "None" ]]; then
    echo -e "${RED}Error: Could not get Loki container runtime ID${NC}" >&2
    exit 1
fi

# Check if port is already in use (existing tunnel)
if lsof -i ":$LOCAL_PORT" >/dev/null 2>&1; then
    echo "Using existing port forward on localhost:$LOCAL_PORT" >&2
else
    echo "Starting SSM port forward to Loki..." >&2
    
    # Start port forwarding in background
    aws ssm start-session \
        --target "ecs:${CLUSTER_NAME}_${TASK_ID}_${RUNTIME_ID}" \
        --document-name AWS-StartPortForwardingSession \
        --parameters "{\"portNumber\":[\"3100\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}" \
        --region "$REGION" &
    
    SSM_PID=$!
    
    # Wait for tunnel to be ready
    echo "Waiting for tunnel..." >&2
    for i in {1..10}; do
        if curl -s "http://localhost:$LOCAL_PORT/ready" >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done
    
    # Cleanup on exit
    trap "kill $SSM_PID 2>/dev/null || true" EXIT
fi

# Calculate time range
case "$TIME_RANGE" in
    *m) SECONDS_AGO=$((${TIME_RANGE%m} * 60)) ;;
    *h) SECONDS_AGO=$((${TIME_RANGE%h} * 3600)) ;;
    *d) SECONDS_AGO=$((${TIME_RANGE%d} * 86400)) ;;
    *)  SECONDS_AGO=600 ;;
esac

END_TIME=$(date +%s)000000000
START_TIME=$(( (END_TIME / 1000000000 - SECONDS_AGO) * 1000000000 ))

# URL encode the query
ENCODED_QUERY=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$QUERY'''))")

# Query Loki
RESPONSE=$(curl -s "http://localhost:$LOCAL_PORT/loki/api/v1/query_range?query=${ENCODED_QUERY}&start=${START_TIME}&end=${END_TIME}&limit=${LIMIT}")

if [[ "$RAW_OUTPUT" == "true" ]]; then
    echo "$RESPONSE"
else
    # Parse and format the response
    echo "$RESPONSE" | python3 -c "
import json
import sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    
    if data.get('status') != 'success':
        print(f\"Error: {data.get('status', 'unknown')}\", file=sys.stderr)
        if 'error' in data:
            print(f\"  {data['error']}\", file=sys.stderr)
        sys.exit(1)
    
    results = data.get('data', {}).get('result', [])
    
    if not results:
        print('No logs found for the given query and time range', file=sys.stderr)
        sys.exit(0)
    
    # Collect all log entries with timestamps
    entries = []
    for stream in results:
        labels = stream.get('stream', {})
        service = labels.get('service_name', 'unknown')
        level = labels.get('level', '')
        
        for ts, line in stream.get('values', []):
            # Convert nanosecond timestamp to datetime
            dt = datetime.fromtimestamp(int(ts) / 1e9)
            entries.append((dt, service, level, line))
    
    # Sort by timestamp
    entries.sort(key=lambda x: x[0])
    
    # Print formatted logs
    for dt, service, level, line in entries:
        timestamp = dt.strftime('%Y-%m-%d %H:%M:%S')
        level_str = f'[{level.upper()}]' if level else ''
        print(f'{timestamp} {service} {level_str} {line}')

except json.JSONDecodeError as e:
    print(f'Error parsing Loki response: {e}', file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
"
fi
