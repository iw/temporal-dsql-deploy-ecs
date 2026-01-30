#!/bin/bash
# -----------------------------------------------------------------------------
# Temporal Benchmark Runner
# -----------------------------------------------------------------------------
# This script runs a benchmark against the Temporal cluster using the
# benchmark-generator ECS service. The service approach provides:
# - Service Connect for temporal-frontend discovery
# - Alloy sidecar for log collection to Loki
# - Proper lifecycle management
#
# Usage:
#   ./scripts/run-benchmark.sh <environment> [OPTIONS]
#
# Arguments:
#   environment             Environment to run benchmark in (dev, bench, prod)
#
# Options:
#   --workflow-type TYPE    Workflow type: simple, multi-activity, timer, child-workflow, state-transitions (default: simple)
#   --rate RATE             Target workflows per second (default: 10)
#   --duration DURATION     Test duration (default: 1m)
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
DURATION="1m"
RAMP_UP="10s"
WORKER_COUNT="4"
ACTIVITY_COUNT="5"
NAMESPACE="benchmark"
GENERATOR_ONLY=false
WAIT_FOR_COMPLETION=false

show_usage() {
    head -34 "$0" | tail -32
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

TERRAFORM_OUTPUT=$(terraform -chdir="$ENV_DIR" output -json 2>/dev/null) || {
    echo -e "${RED}Error: Could not get terraform outputs${NC}"
    exit 1
}

CLUSTER_NAME=$(echo "$TERRAFORM_OUTPUT" | jq -r '.ecs_cluster_name.value')
REGION=$(echo "$TERRAFORM_OUTPUT" | jq -r '.region.value // "eu-west-1"')
GENERATOR_SERVICE=$(echo "$TERRAFORM_OUTPUT" | jq -r '.benchmark_generator_service_name.value // empty')

if [ -z "$GENERATOR_SERVICE" ]; then
    PROJECT_NAME="${CLUSTER_NAME%-cluster}"
    GENERATOR_SERVICE="${PROJECT_NAME}-benchmark-generator"
fi

echo ""
echo "Configuration:"
echo "  Environment:    $ENVIRONMENT"
echo "  Cluster:        $CLUSTER_NAME"
echo "  Region:         $REGION"
echo "  Service:        $GENERATOR_SERVICE"
echo "  Workflow Type:  $WORKFLOW_TYPE"
echo "  Target Rate:    $TARGET_RATE WPS"
echo "  Duration:       $DURATION"
echo "  Namespace:      $NAMESPACE"
echo "  Generator Only: $GENERATOR_ONLY"
echo ""

# Get current task definition
echo -e "${BLUE}Getting current task definition...${NC}"
TASK_DEF_ARN=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$GENERATOR_SERVICE" \
    --region "$REGION" \
    --query 'services[0].taskDefinition' \
    --output text 2>/dev/null)

if [ -z "$TASK_DEF_ARN" ] || [ "$TASK_DEF_ARN" = "None" ]; then
    echo -e "${RED}Error: Could not get task definition for service${NC}"
    exit 1
fi

# Get the task definition JSON
TASK_DEF=$(aws ecs describe-task-definition \
    --task-definition "$TASK_DEF_ARN" \
    --region "$REGION" \
    --query 'taskDefinition' 2>/dev/null)

# Build the environment variable overrides
# We need to update the benchmark container's environment variables
ENV_OVERRIDES=$(cat <<EOF
[
  {"name": "BENCHMARK_NAMESPACE", "value": "$NAMESPACE"},
  {"name": "BENCHMARK_WORKFLOW_TYPE", "value": "$WORKFLOW_TYPE"},
  {"name": "BENCHMARK_TARGET_RATE", "value": "$TARGET_RATE"},
  {"name": "BENCHMARK_DURATION", "value": "$DURATION"},
  {"name": "BENCHMARK_RAMP_UP", "value": "$RAMP_UP"},
  {"name": "BENCHMARK_WORKER_COUNT", "value": "$WORKER_COUNT"},
  {"name": "BENCHMARK_ACTIVITY_COUNT", "value": "$ACTIVITY_COUNT"},
  {"name": "BENCHMARK_GENERATOR_ONLY", "value": "$GENERATOR_ONLY"},
  {"name": "TEMPORAL_ADDRESS", "value": "temporal-frontend:7233"},
  {"name": "BENCHMARK_ITERATIONS", "value": "1"},
  {"name": "BENCHMARK_MAX_P99_LATENCY", "value": "5s"},
  {"name": "BENCHMARK_MIN_THROUGHPUT", "value": "50"}
]
EOF
)

# Update the container definitions with new environment variables
# Find the benchmark container and replace its environment
UPDATED_CONTAINER_DEFS=$(echo "$TASK_DEF" | jq --argjson env "$ENV_OVERRIDES" '
  .containerDefinitions | map(
    if .name == "benchmark" then
      .environment = $env
    else
      .
    end
  )
')

# Extract required fields for register-task-definition
FAMILY=$(echo "$TASK_DEF" | jq -r '.family')
TASK_ROLE_ARN=$(echo "$TASK_DEF" | jq -r '.taskRoleArn // empty')
EXECUTION_ROLE_ARN=$(echo "$TASK_DEF" | jq -r '.executionRoleArn // empty')
NETWORK_MODE=$(echo "$TASK_DEF" | jq -r '.networkMode // empty')
CPU=$(echo "$TASK_DEF" | jq -r '.cpu // empty')
MEMORY=$(echo "$TASK_DEF" | jq -r '.memory // empty')
REQUIRES_COMPATIBILITIES=$(echo "$TASK_DEF" | jq -c '.requiresCompatibilities // empty')
RUNTIME_PLATFORM=$(echo "$TASK_DEF" | jq -c '.runtimePlatform // empty')
VOLUMES=$(echo "$TASK_DEF" | jq -c '.volumes // []')

# Build the register-task-definition command
echo -e "${BLUE}Registering new task definition with updated environment...${NC}"

# Write container definitions to temp file to avoid shell escaping issues
TEMP_CONTAINER_DEFS=$(mktemp)
echo "$UPDATED_CONTAINER_DEFS" > "$TEMP_CONTAINER_DEFS"

# Build base command arguments
REGISTER_ARGS=(
    --region "$REGION"
    --family "$FAMILY"
    --container-definitions "file://$TEMP_CONTAINER_DEFS"
)

if [ -n "$TASK_ROLE_ARN" ]; then
    REGISTER_ARGS+=(--task-role-arn "$TASK_ROLE_ARN")
fi
if [ -n "$EXECUTION_ROLE_ARN" ]; then
    REGISTER_ARGS+=(--execution-role-arn "$EXECUTION_ROLE_ARN")
fi
if [ -n "$NETWORK_MODE" ]; then
    REGISTER_ARGS+=(--network-mode "$NETWORK_MODE")
fi
if [ -n "$CPU" ]; then
    REGISTER_ARGS+=(--cpu "$CPU")
fi
if [ -n "$MEMORY" ]; then
    REGISTER_ARGS+=(--memory "$MEMORY")
fi
if [ -n "$REQUIRES_COMPATIBILITIES" ] && [ "$REQUIRES_COMPATIBILITIES" != "null" ]; then
    # shellcheck disable=SC2086
    REGISTER_ARGS+=(--requires-compatibilities $(echo "$REQUIRES_COMPATIBILITIES" | jq -r 'join(" ")'))
fi

# Handle volumes - write to temp file if present
if [ -n "$VOLUMES" ] && [ "$VOLUMES" != "[]" ]; then
    TEMP_VOLUMES=$(mktemp)
    echo "$VOLUMES" > "$TEMP_VOLUMES"
    REGISTER_ARGS+=(--volumes "file://$TEMP_VOLUMES")
fi

# Handle runtime platform - write to temp file if present
if [ -n "$RUNTIME_PLATFORM" ] && [ "$RUNTIME_PLATFORM" != "null" ]; then
    TEMP_RUNTIME=$(mktemp)
    echo "$RUNTIME_PLATFORM" > "$TEMP_RUNTIME"
    REGISTER_ARGS+=(--runtime-platform "file://$TEMP_RUNTIME")
fi

# Register the new task definition
NEW_TASK_DEF_ARN=$(aws ecs register-task-definition "${REGISTER_ARGS[@]}" | jq -r '.taskDefinition.taskDefinitionArn')

# Cleanup temp files
rm -f "$TEMP_CONTAINER_DEFS" "${TEMP_VOLUMES:-}" "${TEMP_RUNTIME:-}"

if [ -z "$NEW_TASK_DEF_ARN" ] || [ "$NEW_TASK_DEF_ARN" = "null" ]; then
    echo -e "${RED}Error: Failed to register new task definition${NC}"
    exit 1
fi

echo "New task definition: $NEW_TASK_DEF_ARN"

# Check current service status
CURRENT_COUNT=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$GENERATOR_SERVICE" \
    --region "$REGION" \
    --query 'services[0].desiredCount' \
    --output text 2>/dev/null || echo "0")

if [ "$CURRENT_COUNT" != "0" ] && [ "$CURRENT_COUNT" != "None" ]; then
    echo -e "${YELLOW}Warning: Generator service is already running (desired=$CURRENT_COUNT)${NC}"
    echo "Scaling down first..."
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$GENERATOR_SERVICE" \
        --desired-count 0 \
        --region "$REGION" \
        --output text > /dev/null
    
    # Wait for scale down
    echo "Waiting for scale down..."
    sleep 10
fi

echo -e "${BLUE}Starting benchmark generator service with new configuration...${NC}"

# Update service with new task definition and scale to 1
aws ecs update-service \
    --cluster "$CLUSTER_NAME" \
    --service "$GENERATOR_SERVICE" \
    --task-definition "$NEW_TASK_DEF_ARN" \
    --desired-count 1 \
    --force-new-deployment \
    --region "$REGION" \
    --output text > /dev/null

echo ""
echo -e "${GREEN}Benchmark generator service started!${NC}"
echo ""
echo "Monitor logs with:"
echo "  ./scripts/query-loki-logs.sh $ENVIRONMENT benchmark"
echo ""
echo "Check status with:"
echo "  aws ecs describe-services --cluster $CLUSTER_NAME --services $GENERATOR_SERVICE --query 'services[0].{desired:desiredCount,running:runningCount}' --region $REGION"
echo ""

if [ "$WAIT_FOR_COMPLETION" = true ]; then
    echo "Waiting for task to start..."
    
    # Wait for task to be running
    for i in {1..60}; do
        RUNNING=$(aws ecs describe-services \
            --cluster "$CLUSTER_NAME" \
            --services "$GENERATOR_SERVICE" \
            --region "$REGION" \
            --query 'services[0].runningCount' \
            --output text 2>/dev/null || echo "0")
        
        if [ "$RUNNING" = "1" ]; then
            echo "Task is running"
            break
        fi
        echo -n "."
        sleep 5
    done
    
    echo ""
    echo "Benchmark is running. Waiting for completion..."
    echo "(The task will exit when the benchmark duration is complete)"
    echo ""
    
    # Wait for task to stop (benchmark completed)
    while true; do
        RUNNING=$(aws ecs describe-services \
            --cluster "$CLUSTER_NAME" \
            --services "$GENERATOR_SERVICE" \
            --region "$REGION" \
            --query 'services[0].runningCount' \
            --output text 2>/dev/null || echo "0")
        
        if [ "$RUNNING" = "0" ]; then
            echo ""
            echo -e "${GREEN}Benchmark completed${NC}"
            echo ""
            echo "View results with:"
            echo "  ./scripts/query-loki-logs.sh $ENVIRONMENT benchmark -t 10m"
            break
        fi
        echo -n "."
        sleep 10
    done
    
    # Scale service back to 0
    echo ""
    echo "Scaling generator service back to 0..."
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$GENERATOR_SERVICE" \
        --desired-count 0 \
        --region "$REGION" \
        --output text > /dev/null
fi
