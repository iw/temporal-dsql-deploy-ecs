#!/bin/bash
# -----------------------------------------------------------------------------
# Temporal Benchmark Runner
# -----------------------------------------------------------------------------
# This script runs a benchmark task against the Temporal cluster on ECS.
# It uses the benchmark capacity provider which scales from zero.
#
# Usage:
#   ./scripts/run-benchmark.sh <environment> [OPTIONS]
#
# Arguments:
#   environment             Environment to run benchmark in (dev, bench, prod)
#
# Options:
#   --workflow-type TYPE    Workflow type: simple, multi-activity, timer, child-workflow (default: simple)
#   --rate RATE             Target workflows per second (default: 10)
#   --duration DURATION     Test duration (default: 2m)
#   --ramp-up DURATION      Ramp-up period (default: 10s)
#   --workers COUNT         Number of parallel workers (default: 4)
#   --namespace NAME        Namespace for benchmark workflows (default: benchmark)
#   --activity-count COUNT  Activities for multi-activity workflow (default: 5)
#   --generator-only        Run in generator-only mode (use separate benchmark workers)
#   --wait                  Wait for task to complete and show results
#   -h, --help              Show this help message
#
# Examples:
#   ./scripts/run-benchmark.sh dev
#   ./scripts/run-benchmark.sh dev --rate 20 --duration 5m --wait
#   ./scripts/run-benchmark.sh bench --workflow-type multi-activity --rate 100 --generator-only
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

# Defaults
ENVIRONMENT=""
WORKFLOW_TYPE="simple"
TARGET_RATE="10"
DURATION="2m"
RAMP_UP="10s"
WORKER_COUNT="4"
ACTIVITY_COUNT="5"
NAMESPACE="benchmark"
GENERATOR_ONLY=false
WAIT_FOR_COMPLETION=false

show_usage() {
    head -30 "$0" | tail -28
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

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        dev|bench|prod)
            ENVIRONMENT="$1"
            shift
            ;;
        --workflow-type)
            WORKFLOW_TYPE="$2"
            shift 2
            ;;
        --rate)
            TARGET_RATE="$2"
            shift 2
            ;;
        --duration)
            DURATION="$2"
            shift 2
            ;;
        --ramp-up)
            RAMP_UP="$2"
            shift 2
            ;;
        --workers)
            WORKER_COUNT="$2"
            shift 2
            ;;
        --activity-count)
            ACTIVITY_COUNT="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --generator-only)
            GENERATOR_ONLY=true
            shift
            ;;
        --wait)
            WAIT_FOR_COMPLETION=true
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Validate environment
if [ -z "$ENVIRONMENT" ]; then
    echo -e "${RED}Error: Environment is required${NC}"
    echo ""
    echo "Usage: $0 <environment> [OPTIONS]"
    echo "Available environments: ${AVAILABLE_ENVS[*]}"
    exit 1
fi

validate_environment "$ENVIRONMENT"

# Get terraform values
ENV_DIR="$PROJECT_ROOT/terraform/envs/$ENVIRONMENT"
if [ ! -d "$ENV_DIR" ]; then
    echo -e "${RED}Error: Environment directory not found: $ENV_DIR${NC}"
    exit 1
fi

cd "$ENV_DIR"

echo -e "${BLUE}Reading terraform outputs for $ENVIRONMENT...${NC}"

CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null) || {
    echo -e "${RED}Error: Could not get cluster name${NC}"
    exit 1
}

REGION=$(terraform output -raw region 2>/dev/null || echo "eu-west-1")

SUBNET_IDS=$(terraform output -json private_subnet_ids 2>/dev/null | jq -r 'join(",")') || {
    echo -e "${RED}Error: Could not get subnet IDs${NC}"
    exit 1
}

ECS_SG=$(terraform output -raw ecs_instances_security_group_id 2>/dev/null) || {
    echo -e "${RED}Error: Could not get ECS security group${NC}"
    exit 1
}

BENCH_SG=$(terraform output -raw benchmark_security_group_id 2>/dev/null) || {
    echo -e "${RED}Error: Could not get benchmark security group${NC}"
    exit 1
}

TASK_DEF=$(terraform output -raw benchmark_task_definition_arn 2>/dev/null) || {
    echo -e "${RED}Error: Could not get benchmark task definition${NC}"
    exit 1
}

CAP_PROVIDER=$(terraform output -raw benchmark_capacity_provider_name 2>/dev/null) || {
    echo -e "${RED}Error: Could not get benchmark capacity provider${NC}"
    exit 1
}

cd "$PROJECT_ROOT"

echo ""
echo "Configuration:"
echo "  Environment:    $ENVIRONMENT"
echo "  Cluster:        $CLUSTER_NAME"
echo "  Region:         $REGION"
echo "  Workflow Type:  $WORKFLOW_TYPE"
echo "  Target Rate:    $TARGET_RATE WPS"
echo "  Duration:       $DURATION"
echo "  Namespace:      $NAMESPACE"
echo "  Generator Only: $GENERATOR_ONLY"
echo ""

# Build environment overrides
ENV_VARS='[
  {"name":"BENCHMARK_NAMESPACE","value":"'"$NAMESPACE"'"},
  {"name":"BENCHMARK_WORKFLOW_TYPE","value":"'"$WORKFLOW_TYPE"'"},
  {"name":"BENCHMARK_TARGET_RATE","value":"'"$TARGET_RATE"'"},
  {"name":"BENCHMARK_DURATION","value":"'"$DURATION"'"},
  {"name":"BENCHMARK_RAMP_UP","value":"'"$RAMP_UP"'"},
  {"name":"BENCHMARK_WORKER_COUNT","value":"'"$WORKER_COUNT"'"}'

if [ "$WORKFLOW_TYPE" = "multi-activity" ]; then
    ENV_VARS+=',{"name":"BENCHMARK_ACTIVITY_COUNT","value":"'"$ACTIVITY_COUNT"'"}'
fi

if [ "$GENERATOR_ONLY" = true ]; then
    ENV_VARS+=',{"name":"BENCHMARK_GENERATOR_ONLY","value":"true"}'
fi

ENV_VARS+=']'

OVERRIDES='{"containerOverrides":[{"name":"benchmark","environment":'"$ENV_VARS"'}]}'

echo -e "${BLUE}Starting benchmark task...${NC}"

TASK_OUTPUT=$(aws ecs run-task \
    --cluster "$CLUSTER_NAME" \
    --task-definition "$TASK_DEF" \
    --capacity-provider-strategy "capacityProvider=$CAP_PROVIDER,weight=1,base=1" \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_IDS],securityGroups=[$ECS_SG,$BENCH_SG],assignPublicIp=DISABLED}" \
    --overrides "$OVERRIDES" \
    --region "$REGION" \
    --output json 2>&1)

# Check for errors
if echo "$TASK_OUTPUT" | jq -e '.failures[0].reason' > /dev/null 2>&1; then
    FAILURE=$(echo "$TASK_OUTPUT" | jq -r '.failures[0].reason')
    echo -e "${RED}Error: $FAILURE${NC}"
    exit 1
fi

TASK_ARN=$(echo "$TASK_OUTPUT" | jq -r '.tasks[0].taskArn // empty')
if [ -z "$TASK_ARN" ]; then
    echo -e "${RED}Error: Failed to get task ARN${NC}"
    echo "$TASK_OUTPUT"
    exit 1
fi

TASK_ID=$(echo "$TASK_ARN" | cut -d'/' -f3)

echo ""
echo -e "${GREEN}Benchmark task started!${NC}"
echo "  Task ID: $TASK_ID"
echo ""

if [ "$WAIT_FOR_COMPLETION" = true ]; then
    echo "Waiting for completion..."
    while true; do
        STATUS=$(aws ecs describe-tasks \
            --cluster "$CLUSTER_NAME" \
            --tasks "$TASK_ARN" \
            --region "$REGION" \
            --query 'tasks[0].lastStatus' \
            --output text 2>/dev/null || echo "UNKNOWN")
        
        case "$STATUS" in
            STOPPED)
                EXIT_CODE=$(aws ecs describe-tasks \
                    --cluster "$CLUSTER_NAME" \
                    --tasks "$TASK_ARN" \
                    --region "$REGION" \
                    --query 'tasks[0].containers[0].exitCode' \
                    --output text 2>/dev/null || echo "UNKNOWN")
                echo ""
                if [ "$EXIT_CODE" = "0" ]; then
                    echo -e "${GREEN}Benchmark completed successfully${NC}"
                else
                    echo -e "${YELLOW}Benchmark exited with code: $EXIT_CODE${NC}"
                fi
                break
                ;;
            PENDING|PROVISIONING|ACTIVATING|RUNNING)
                echo -n "."
                sleep 10
                ;;
            *)
                echo ""
                echo -e "${RED}Unexpected status: $STATUS${NC}"
                break
                ;;
        esac
    done
else
    echo "Monitor with:"
    echo "  ./scripts/query-loki-logs.sh $ENVIRONMENT benchmark"
fi
