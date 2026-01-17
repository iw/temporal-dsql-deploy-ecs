#!/bin/bash
# -----------------------------------------------------------------------------
# Temporal Benchmark Results Retrieval
# -----------------------------------------------------------------------------
# This script retrieves benchmark results from CloudWatch Logs.
# It can fetch results for a specific task or the most recent benchmark run.
#
# Usage:
#   ./scripts/get-benchmark-results.sh [OPTIONS]
#
# Options:
#   --task-id ID            Task ID to retrieve results for
#   --task-arn ARN          Full task ARN to retrieve results for
#   --latest                Get results from the most recent benchmark task
#   --from-terraform        Read cluster config from terraform.tfvars
#   --json                  Output only the JSON results (for piping)
#   --summary               Show only the summary (default)
#   --full                  Show full log output
#   -h, --help              Show this help message
#
# Examples:
#   ./scripts/get-benchmark-results.sh --latest --from-terraform
#   ./scripts/get-benchmark-results.sh --task-id abc123def456 --from-terraform
#   ./scripts/get-benchmark-results.sh --latest --json --from-terraform | jq .
#
# Requirements: 6.1, 6.2
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
TASK_ID=""
TASK_ARN=""
GET_LATEST=false
FROM_TERRAFORM=false
OUTPUT_JSON=false
OUTPUT_SUMMARY=true
OUTPUT_FULL=false
AWS_REGION="${AWS_REGION:-eu-west-1}"
CLUSTER_NAME=""
PROJECT_NAME=""
LOG_GROUP_NAME=""

log_info() {
    if [ "$OUTPUT_JSON" = false ]; then
        echo -e "${GREEN}[INFO]${NC} $1" >&2
    fi
}

log_warn() {
    if [ "$OUTPUT_JSON" = false ]; then
        echo -e "${YELLOW}[WARN]${NC} $1" >&2
    fi
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

show_help() {
    head -28 "$0" | tail -26
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --task-id)
            TASK_ID="$2"
            shift 2
            ;;
        --task-arn)
            TASK_ARN="$2"
            shift 2
            ;;
        --latest)
            GET_LATEST=true
            shift
            ;;
        --from-terraform)
            FROM_TERRAFORM=true
            shift
            ;;
        --json)
            OUTPUT_JSON=true
            OUTPUT_SUMMARY=false
            shift
            ;;
        --summary)
            OUTPUT_SUMMARY=true
            OUTPUT_FULL=false
            shift
            ;;
        --full)
            OUTPUT_FULL=true
            OUTPUT_SUMMARY=false
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
    LOG_GROUP_NAME="/ecs/${PROJECT_NAME}/benchmark"
}

# Get the latest benchmark task
get_latest_task() {
    log_info "Finding the most recent benchmark task..."

    # List stopped tasks (completed benchmarks)
    local task_arns
    task_arns=$(aws ecs list-tasks \
        --cluster "$CLUSTER_NAME" \
        --family "${PROJECT_NAME}-benchmark" \
        --desired-status STOPPED \
        --region "$AWS_REGION" \
        --query 'taskArns' \
        --output json 2>/dev/null || echo "[]")

    if [ "$task_arns" = "[]" ] || [ -z "$task_arns" ]; then
        # Try running tasks
        task_arns=$(aws ecs list-tasks \
            --cluster "$CLUSTER_NAME" \
            --family "${PROJECT_NAME}-benchmark" \
            --desired-status RUNNING \
            --region "$AWS_REGION" \
            --query 'taskArns' \
            --output json 2>/dev/null || echo "[]")
    fi

    if [ "$task_arns" = "[]" ] || [ -z "$task_arns" ]; then
        log_error "No benchmark tasks found"
        exit 1
    fi

    # Get the first (most recent) task
    TASK_ARN=$(echo "$task_arns" | jq -r '.[0]')
    TASK_ID=$(echo "$TASK_ARN" | cut -d'/' -f3)

    log_info "Found task: $TASK_ID"
}

# Get task details
get_task_details() {
    local task_arn="$1"

    aws ecs describe-tasks \
        --cluster "$CLUSTER_NAME" \
        --tasks "$task_arn" \
        --region "$AWS_REGION" \
        --output json 2>/dev/null
}

# Extract JSON results from logs
extract_json_results() {
    local log_events="$1"
    
    # Look for JSON output that starts with { and contains "results"
    echo "$log_events" | jq -r '.events[].message' 2>/dev/null | \
        grep -E '^\{.*"results"' | \
        head -1 || echo ""
}

# Get logs from CloudWatch
get_logs() {
    local task_id="$1"
    local log_stream="benchmark/${task_id}"

    log_info "Fetching logs from: $LOG_GROUP_NAME/$log_stream"

    # Get log events
    local log_events
    log_events=$(aws logs get-log-events \
        --log-group-name "$LOG_GROUP_NAME" \
        --log-stream-name "$log_stream" \
        --region "$AWS_REGION" \
        --output json 2>/dev/null || echo '{"events":[]}')

    if [ "$(echo "$log_events" | jq '.events | length')" = "0" ]; then
        # Try with benchmark/ prefix variations
        log_stream="benchmark/benchmark/${task_id}"
        log_events=$(aws logs get-log-events \
            --log-group-name "$LOG_GROUP_NAME" \
            --log-stream-name "$log_stream" \
            --region "$AWS_REGION" \
            --output json 2>/dev/null || echo '{"events":[]}')
    fi

    echo "$log_events"
}

# Display summary
display_summary() {
    local json_result="$1"
    local task_details="$2"

    echo ""
    echo "=== Benchmark Results Summary ==="
    echo ""

    # Task info
    local task_status
    task_status=$(echo "$task_details" | jq -r '.tasks[0].lastStatus // "UNKNOWN"')
    local exit_code
    exit_code=$(echo "$task_details" | jq -r '.tasks[0].containers[0].exitCode // "N/A"')
    local started_at
    started_at=$(echo "$task_details" | jq -r '.tasks[0].startedAt // "N/A"')
    local stopped_at
    stopped_at=$(echo "$task_details" | jq -r '.tasks[0].stoppedAt // "N/A"')

    echo "Task Information:"
    echo "  Task ID:     $TASK_ID"
    echo "  Status:      $task_status"
    echo "  Exit Code:   $exit_code"
    echo "  Started:     $started_at"
    echo "  Stopped:     $stopped_at"
    echo ""

    if [ -n "$json_result" ] && [ "$json_result" != "null" ]; then
        # Parse JSON results
        local workflow_type
        workflow_type=$(echo "$json_result" | jq -r '.config.workflowType // "N/A"')
        local target_rate
        target_rate=$(echo "$json_result" | jq -r '.config.targetRate // "N/A"')
        local duration
        duration=$(echo "$json_result" | jq -r '.config.duration // "N/A"')

        local workflows_started
        workflows_started=$(echo "$json_result" | jq -r '.results.workflowsStarted // "N/A"')
        local workflows_completed
        workflows_completed=$(echo "$json_result" | jq -r '.results.workflowsCompleted // "N/A"')
        local workflows_failed
        workflows_failed=$(echo "$json_result" | jq -r '.results.workflowsFailed // "N/A"')
        local actual_rate
        actual_rate=$(echo "$json_result" | jq -r '.results.actualRate // "N/A"')

        local p50
        p50=$(echo "$json_result" | jq -r '.results.latency.p50 // "N/A"')
        local p95
        p95=$(echo "$json_result" | jq -r '.results.latency.p95 // "N/A"')
        local p99
        p99=$(echo "$json_result" | jq -r '.results.latency.p99 // "N/A"')
        local max_latency
        max_latency=$(echo "$json_result" | jq -r '.results.latency.max // "N/A"')

        local passed
        passed=$(echo "$json_result" | jq -r '.passed // "N/A"')
        local failure_reasons
        failure_reasons=$(echo "$json_result" | jq -r '.failureReasons // []')

        echo "Configuration:"
        echo "  Workflow Type:  $workflow_type"
        echo "  Target Rate:    $target_rate WPS"
        echo "  Duration:       $duration"
        echo ""

        echo "Results:"
        echo "  Workflows Started:    $workflows_started"
        echo "  Workflows Completed:  $workflows_completed"
        echo "  Workflows Failed:     $workflows_failed"
        echo "  Actual Rate:          $actual_rate WPS"
        echo ""

        echo "Latency (ms):"
        echo "  P50:  $p50"
        echo "  P95:  $p95"
        echo "  P99:  $p99"
        echo "  Max:  $max_latency"
        echo ""

        if [ "$passed" = "true" ]; then
            echo -e "Status: ${GREEN}PASSED${NC}"
        elif [ "$passed" = "false" ]; then
            echo -e "Status: ${RED}FAILED${NC}"
            if [ "$failure_reasons" != "[]" ]; then
                echo "Failure Reasons:"
                echo "$failure_reasons" | jq -r '.[]' | while read -r reason; do
                    echo "  - $reason"
                done
            fi
        else
            echo "Status: $passed"
        fi
    else
        log_warn "No JSON results found in logs"
        echo "The benchmark may still be running or did not produce JSON output."
        echo ""
        echo "To view raw logs, run:"
        echo "  aws logs tail $LOG_GROUP_NAME --follow --region $AWS_REGION"
    fi

    echo ""
}

# Display full logs
display_full_logs() {
    local log_events="$1"

    echo ""
    echo "=== Full Benchmark Logs ==="
    echo ""

    echo "$log_events" | jq -r '.events[].message' 2>/dev/null || echo "No log events found"

    echo ""
}

# Main execution
main() {
    # Read Terraform configuration
    if [ "$FROM_TERRAFORM" = true ]; then
        read_terraform_config
    else
        PROJECT_NAME="${PROJECT_NAME:-temporal-dev}"
        CLUSTER_NAME="${CLUSTER_NAME:-${PROJECT_NAME}-cluster}"
        LOG_GROUP_NAME="${LOG_GROUP_NAME:-/ecs/${PROJECT_NAME}/benchmark}"
    fi

    # Determine task to retrieve
    if [ "$GET_LATEST" = true ]; then
        get_latest_task
    elif [ -n "$TASK_ARN" ]; then
        TASK_ID=$(echo "$TASK_ARN" | cut -d'/' -f3)
    elif [ -z "$TASK_ID" ]; then
        log_error "Must specify --task-id, --task-arn, or --latest"
        exit 1
    fi

    log_info "Cluster: $CLUSTER_NAME"
    log_info "Region: $AWS_REGION"
    log_info "Task ID: $TASK_ID"

    # Get task details
    local task_details=""
    if [ -n "$TASK_ARN" ]; then
        task_details=$(get_task_details "$TASK_ARN")
    else
        # Construct task ARN from task ID
        local account_id
        account_id=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null || echo "")
        if [ -n "$account_id" ]; then
            TASK_ARN="arn:aws:ecs:${AWS_REGION}:${account_id}:task/${CLUSTER_NAME}/${TASK_ID}"
            task_details=$(get_task_details "$TASK_ARN")
        fi
    fi

    # Get logs
    local log_events
    log_events=$(get_logs "$TASK_ID")

    # Extract JSON results
    local json_result
    json_result=$(extract_json_results "$log_events")

    # Output based on mode
    if [ "$OUTPUT_JSON" = true ]; then
        if [ -n "$json_result" ]; then
            echo "$json_result"
        else
            log_error "No JSON results found"
            exit 1
        fi
    elif [ "$OUTPUT_FULL" = true ]; then
        display_full_logs "$log_events"
    else
        display_summary "$json_result" "$task_details"
    fi
}

main "$@"
