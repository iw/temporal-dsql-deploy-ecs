#!/bin/bash
# -----------------------------------------------------------------------------
# Temporal Benchmark Runner
# -----------------------------------------------------------------------------
# This script runs a benchmark task against the Temporal cluster on ECS.
# It uses the benchmark capacity provider which scales from zero.
#
# Usage:
#   ./scripts/run-benchmark.sh [OPTIONS]
#
# Options:
#   --workflow-type TYPE    Workflow type: simple, multi-activity, timer, child-workflow (default: simple)
#   --rate RATE             Target workflows per second (default: 100)
#   --duration DURATION     Test duration (default: 5m)
#   --ramp-up DURATION      Ramp-up period (default: 30s)
#   --workers COUNT         Number of parallel workers (default: 4)
#   --iterations COUNT      Number of test iterations (default: 1)
#   --namespace NAME        Namespace for benchmark workflows (default: benchmark)
#   --activity-count COUNT  Activities for multi-activity workflow (default: 5)
#   --timer-duration DUR    Timer duration for timer workflow (default: 1s)
#   --child-count COUNT     Child workflows for child-workflow type (default: 3)
#   --max-p99-latency DUR   Maximum acceptable p99 latency (default: 5s)
#   --min-throughput RATE   Minimum acceptable throughput (default: 50)
#   --completion-timeout DUR Timeout for waiting for workflows to complete (default: auto-calculated)
#   --generator-only        Run in generator-only mode (no embedded worker)
#   --from-terraform        Read cluster config from terraform.tfvars
#   --wait                  Wait for task to complete and show results
#   -h, --help              Show this help message
#
# Examples:
#   ./scripts/run-benchmark.sh --from-terraform
#   ./scripts/run-benchmark.sh --workflow-type simple --rate 200 --duration 10m --wait
#   ./scripts/run-benchmark.sh --namespace benchmark --workflow-type multi-activity --activity-count 10 --rate 50
#
# Requirements: 5.1, 5.2
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
WORKFLOW_TYPE="simple"
TARGET_RATE="100"
DURATION="5m"
RAMP_UP="30s"
WORKER_COUNT="4"
ITERATIONS="1"
ACTIVITY_COUNT="5"
TIMER_DURATION="1s"
CHILD_COUNT="3"
MAX_P99_LATENCY="5s"
MIN_THROUGHPUT="50"
COMPLETION_TIMEOUT=""
NAMESPACE="benchmark"
GENERATOR_ONLY=false
AWS_REGION="${AWS_REGION:-eu-west-1}"
CLUSTER_NAME=""
PROJECT_NAME=""
TEMPORAL_ADDRESS=""
FROM_TERRAFORM=false
WAIT_FOR_COMPLETION=false

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    head -35 "$0" | tail -33
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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
        --iterations)
            ITERATIONS="$2"
            shift 2
            ;;
        --activity-count)
            ACTIVITY_COUNT="$2"
            shift 2
            ;;
        --timer-duration)
            TIMER_DURATION="$2"
            shift 2
            ;;
        --child-count)
            CHILD_COUNT="$2"
            shift 2
            ;;
        --max-p99-latency)
            MAX_P99_LATENCY="$2"
            shift 2
            ;;
        --min-throughput)
            MIN_THROUGHPUT="$2"
            shift 2
            ;;
        --completion-timeout)
            COMPLETION_TIMEOUT="$2"
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
        --from-terraform)
            FROM_TERRAFORM=true
            shift
            ;;
        --wait)
            WAIT_FOR_COMPLETION=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate workflow type
case "$WORKFLOW_TYPE" in
    simple|multi-activity|timer|child-workflow)
        ;;
    *)
        log_error "Invalid workflow type: $WORKFLOW_TYPE"
        log_error "Valid types: simple, multi-activity, timer, child-workflow"
        exit 1
        ;;
esac

# Read configuration from Terraform
read_terraform_config() {
    if [ ! -d "$TERRAFORM_DIR" ]; then
        log_error "Terraform directory not found: $TERRAFORM_DIR"
        exit 1
    fi

    if [ -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
        PROJECT_NAME=$(grep -E "^project_name" "$TERRAFORM_DIR/terraform.tfvars" | cut -d'"' -f2 || echo "temporal-dev")
        TFVARS_REGION=$(grep -E "^region" "$TERRAFORM_DIR/terraform.tfvars" | cut -d'"' -f2 || true)
        if [ -n "$TFVARS_REGION" ]; then
            AWS_REGION="$TFVARS_REGION"
        fi
    else
        PROJECT_NAME="temporal-dev"
    fi

    CLUSTER_NAME="${PROJECT_NAME}-cluster"
}

# Get infrastructure details from Terraform state
get_terraform_outputs() {
    cd "$TERRAFORM_DIR"
    
    # Get subnet IDs
    SUBNET_IDS=$(terraform output -json private_subnet_ids 2>/dev/null | jq -r 'join(",")' || echo "")
    if [ -z "$SUBNET_IDS" ]; then
        log_error "Could not get subnet IDs from Terraform"
        exit 1
    fi

    # Get security group IDs
    ECS_SG_ID=$(terraform output -raw ecs_instances_security_group_id 2>/dev/null || echo "")
    BENCHMARK_SG_ID=$(terraform output -raw benchmark_security_group_id 2>/dev/null || echo "")
    
    if [ -z "$ECS_SG_ID" ] || [ -z "$BENCHMARK_SG_ID" ]; then
        log_error "Could not get security group IDs from Terraform"
        exit 1
    fi

    # Get capacity provider name
    CAPACITY_PROVIDER=$(terraform output -raw benchmark_capacity_provider_name 2>/dev/null || echo "${PROJECT_NAME}-benchmark")

    # Get task definition family
    TASK_DEFINITION=$(terraform output -raw benchmark_task_definition_family 2>/dev/null || echo "${PROJECT_NAME}-benchmark")

    cd "$PROJECT_ROOT"
    
    # Get Temporal Frontend IP address (since standalone tasks don't have Service Connect)
    log_info "Getting Temporal Frontend IP address..."
    local frontend_task_arn
    frontend_task_arn=$(aws ecs list-tasks \
        --cluster "$CLUSTER_NAME" \
        --service-name "${PROJECT_NAME}-temporal-frontend" \
        --query 'taskArns[0]' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [ -z "$frontend_task_arn" ] || [ "$frontend_task_arn" = "None" ]; then
        log_error "Could not find Temporal Frontend task. Is the service running?"
        exit 1
    fi
    
    FRONTEND_IP=$(aws ecs describe-tasks \
        --cluster "$CLUSTER_NAME" \
        --tasks "$frontend_task_arn" \
        --region "$AWS_REGION" \
        --query 'tasks[0].containers[0].networkInterfaces[0].privateIpv4Address' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$FRONTEND_IP" ] || [ "$FRONTEND_IP" = "None" ]; then
        log_error "Could not get Temporal Frontend IP address"
        exit 1
    fi
    
    TEMPORAL_ADDRESS="${FRONTEND_IP}:7233"
    log_info "Temporal Frontend address: $TEMPORAL_ADDRESS"
}

# Build environment overrides JSON
build_env_overrides() {
    local env_vars=""
    
    # Add TEMPORAL_ADDRESS if we have the frontend IP
    if [ -n "${TEMPORAL_ADDRESS:-}" ]; then
        env_vars+='{"name": "TEMPORAL_ADDRESS", "value": "'"$TEMPORAL_ADDRESS"'"},'
    fi
    
    # Add namespace (workflows will be created in this namespace)
    env_vars+='{"name": "BENCHMARK_NAMESPACE", "value": "'"$NAMESPACE"'"},'
    env_vars+='{"name": "BENCHMARK_WORKFLOW_TYPE", "value": "'"$WORKFLOW_TYPE"'"},'
    env_vars+='{"name": "BENCHMARK_TARGET_RATE", "value": "'"$TARGET_RATE"'"},'
    env_vars+='{"name": "BENCHMARK_DURATION", "value": "'"$DURATION"'"},'
    env_vars+='{"name": "BENCHMARK_RAMP_UP", "value": "'"$RAMP_UP"'"},'
    env_vars+='{"name": "BENCHMARK_WORKER_COUNT", "value": "'"$WORKER_COUNT"'"},'
    env_vars+='{"name": "BENCHMARK_ITERATIONS", "value": "'"$ITERATIONS"'"},'
    env_vars+='{"name": "BENCHMARK_MAX_P99_LATENCY", "value": "'"$MAX_P99_LATENCY"'"},'
    env_vars+='{"name": "BENCHMARK_MIN_THROUGHPUT", "value": "'"$MIN_THROUGHPUT"'"}'

    # Add completion timeout if specified
    if [ -n "${COMPLETION_TIMEOUT:-}" ]; then
        env_vars+=',{"name": "BENCHMARK_COMPLETION_TIMEOUT", "value": "'"$COMPLETION_TIMEOUT"'"}'
    fi

    # Add generator-only mode if specified
    if [ "$GENERATOR_ONLY" = true ]; then
        env_vars+=',{"name": "BENCHMARK_GENERATOR_ONLY", "value": "true"}'
    fi

    # Add workflow-specific parameters
    case "$WORKFLOW_TYPE" in
        multi-activity)
            env_vars+=',{"name": "BENCHMARK_ACTIVITY_COUNT", "value": "'"$ACTIVITY_COUNT"'"}'
            ;;
        timer)
            env_vars+=',{"name": "BENCHMARK_TIMER_DURATION", "value": "'"$TIMER_DURATION"'"}'
            ;;
        child-workflow)
            env_vars+=',{"name": "BENCHMARK_CHILD_COUNT", "value": "'"$CHILD_COUNT"'"}'
            ;;
    esac

    echo "$env_vars"
}

# Wait for task to complete
wait_for_task() {
    local task_arn="$1"
    local task_id
    task_id=$(echo "$task_arn" | cut -d'/' -f3)

    log_info "Waiting for benchmark task to complete..."
    log_info "Task ID: $task_id"

    while true; do
        local status
        status=$(aws ecs describe-tasks \
            --cluster "$CLUSTER_NAME" \
            --tasks "$task_arn" \
            --region "$AWS_REGION" \
            --query 'tasks[0].lastStatus' \
            --output text 2>/dev/null || echo "UNKNOWN")

        case "$status" in
            STOPPED)
                log_info "Task completed"
                
                # Get exit code
                local exit_code
                exit_code=$(aws ecs describe-tasks \
                    --cluster "$CLUSTER_NAME" \
                    --tasks "$task_arn" \
                    --region "$AWS_REGION" \
                    --query 'tasks[0].containers[0].exitCode' \
                    --output text 2>/dev/null || echo "UNKNOWN")
                
                if [ "$exit_code" = "0" ]; then
                    log_info "Benchmark completed successfully (exit code: 0)"
                else
                    log_warn "Benchmark exited with code: $exit_code"
                fi
                
                # Show how to get results
                echo ""
                log_info "To get benchmark results, run:"
                echo "  ./scripts/get-benchmark-results.sh --task-id $task_id --from-terraform"
                return 0
                ;;
            PENDING|PROVISIONING|ACTIVATING|RUNNING)
                echo -n "."
                sleep 10
                ;;
            DEACTIVATING|STOPPING|DEPROVISIONING)
                echo ""
                log_info "Task is stopping..."
                sleep 5
                ;;
            *)
                echo ""
                log_error "Unexpected task status: $status"
                return 1
                ;;
        esac
    done
}

# Main execution
main() {
    echo ""
    echo "=== Temporal Benchmark Runner ==="
    echo ""

    # Read Terraform configuration
    if [ "$FROM_TERRAFORM" = true ]; then
        log_info "Reading configuration from Terraform..."
        read_terraform_config
        get_terraform_outputs
    else
        # Use defaults or environment variables
        PROJECT_NAME="${PROJECT_NAME:-temporal-dev}"
        CLUSTER_NAME="${CLUSTER_NAME:-${PROJECT_NAME}-cluster}"
        
        # These must be provided if not using Terraform
        if [ -z "${SUBNET_IDS:-}" ] || [ -z "${ECS_SG_ID:-}" ] || [ -z "${BENCHMARK_SG_ID:-}" ]; then
            log_error "When not using --from-terraform, you must set:"
            log_error "  SUBNET_IDS, ECS_SG_ID, BENCHMARK_SG_ID environment variables"
            log_error "Or use --from-terraform to read from Terraform state"
            exit 1
        fi
        CAPACITY_PROVIDER="${CAPACITY_PROVIDER:-${PROJECT_NAME}-benchmark}"
        TASK_DEFINITION="${TASK_DEFINITION:-${PROJECT_NAME}-benchmark}"
    fi

    log_info "Cluster: $CLUSTER_NAME"
    log_info "Region: $AWS_REGION"
    log_info "Task Definition: $TASK_DEFINITION"
    log_info "Capacity Provider: $CAPACITY_PROVIDER"
    echo ""

    # Display benchmark configuration
    echo "Benchmark Configuration:"
    echo "  Namespace:        $NAMESPACE"
    echo "  Workflow Type:    $WORKFLOW_TYPE"
    echo "  Target Rate:      $TARGET_RATE WPS"
    echo "  Duration:         $DURATION"
    echo "  Ramp-up:          $RAMP_UP"
    echo "  Workers:          $WORKER_COUNT"
    echo "  Iterations:       $ITERATIONS"
    echo "  Max P99 Latency:  $MAX_P99_LATENCY"
    echo "  Min Throughput:   $MIN_THROUGHPUT"
    if [ -n "${COMPLETION_TIMEOUT:-}" ]; then
        echo "  Completion Timeout: $COMPLETION_TIMEOUT"
    else
        echo "  Completion Timeout: auto-calculated"
    fi
    if [ "$GENERATOR_ONLY" = true ]; then
        echo "  Mode:             generator-only (no embedded worker)"
    else
        echo "  Mode:             full (embedded worker)"
    fi
    
    case "$WORKFLOW_TYPE" in
        multi-activity)
            echo "  Activity Count:   $ACTIVITY_COUNT"
            ;;
        timer)
            echo "  Timer Duration:   $TIMER_DURATION"
            ;;
        child-workflow)
            echo "  Child Count:      $CHILD_COUNT"
            ;;
    esac
    echo ""

    # Build environment overrides
    local env_overrides
    env_overrides=$(build_env_overrides)

    # Build the overrides JSON
    local overrides_json
    overrides_json=$(cat <<EOF
{
    "containerOverrides": [{
        "name": "benchmark",
        "environment": [$env_overrides]
    }]
}
EOF
)

    log_info "Starting benchmark task..."

    # Run the ECS task
    local task_output
    task_output=$(aws ecs run-task \
        --cluster "$CLUSTER_NAME" \
        --task-definition "$TASK_DEFINITION" \
        --capacity-provider-strategy "capacityProvider=$CAPACITY_PROVIDER,weight=1,base=1" \
        --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_IDS],securityGroups=[$ECS_SG_ID,$BENCHMARK_SG_ID],assignPublicIp=DISABLED}" \
        --enable-execute-command \
        --overrides "$overrides_json" \
        --region "$AWS_REGION" \
        --output json 2>&1)

    # Check for errors
    if echo "$task_output" | grep -q '"failures":\s*\[' && echo "$task_output" | grep -q '"reason"'; then
        local failure_reason
        failure_reason=$(echo "$task_output" | jq -r '.failures[0].reason // "Unknown error"')
        log_error "Failed to start benchmark task: $failure_reason"
        exit 1
    fi

    # Extract task ARN
    local task_arn
    task_arn=$(echo "$task_output" | jq -r '.tasks[0].taskArn // empty')

    if [ -z "$task_arn" ]; then
        log_error "Failed to get task ARN from response"
        echo "$task_output"
        exit 1
    fi

    local task_id
    task_id=$(echo "$task_arn" | cut -d'/' -f3)

    echo ""
    log_info "Benchmark task started successfully!"
    echo ""
    echo "Task ARN: $task_arn"
    echo "Task ID:  $task_id"
    echo ""

    if [ "$WAIT_FOR_COMPLETION" = true ]; then
        wait_for_task "$task_arn"
    else
        echo "Monitor progress:"
        echo "  aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $task_arn --region $AWS_REGION"
        echo ""
        echo "View logs:"
        echo "  aws logs tail /ecs/${PROJECT_NAME}/benchmark --follow --region $AWS_REGION"
        echo ""
        echo "Get results after completion:"
        echo "  ./scripts/get-benchmark-results.sh --task-id $task_id --from-terraform"
    fi
}

main "$@"
