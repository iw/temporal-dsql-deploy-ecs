#!/bin/bash
# -----------------------------------------------------------------------------
# Staggered Service Startup Script
# -----------------------------------------------------------------------------
# Starts Temporal services in stages to avoid overwhelming DynamoDB rate limiter
# and DSQL connection rate limits during cold start.
#
# Usage:
#   ./scripts/staggered-startup.sh [--from-terraform|--cluster <name>] [--region <region>]
#
# Options:
#   --from-terraform    Read cluster name and region from Terraform state
#   --cluster <name>    ECS cluster name (default: temporal-bench)
#   --region <region>   AWS region (default: eu-west-1)
#   --dry-run           Show what would be done without executing
#   --stage <n>         Start from specific stage (1-5)
#   --wait <seconds>    Wait time between stages (default: 120)
# -----------------------------------------------------------------------------

set -euo pipefail

# Default values
CLUSTER_NAME="temporal-bench"
REGION="eu-west-1"
DRY_RUN=false
START_STAGE=1
WAIT_SECONDS=240

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --from-terraform)
            cd "$(dirname "$0")/../terraform/envs/bench"
            CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null || echo "temporal-bench")
            REGION=$(terraform output -raw region 2>/dev/null || echo "eu-west-1")
            cd - > /dev/null
            shift
            ;;
        --cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --stage)
            START_STAGE="$2"
            shift 2
            ;;
        --wait)
            WAIT_SECONDS="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Service configurations: name suffix, desired count
# Order: observability first, then frontend, history, matching, worker, UI
declare -a STAGES=(
    "0|loki|1|Loki (log aggregation)"
    "0|grafana|1|Grafana (dashboards)"
    "1|temporal-frontend|9|Frontend services (API gateway)"
    "2|temporal-history|16|History services (workflow state)"
    "3|temporal-matching|16|Matching services (task queues)"
    "4|temporal-worker|3|Worker services (system workflows)"
    "5|temporal-ui|1|UI service"
)

echo "=============================================="
echo "Staggered Service Startup"
echo "=============================================="
echo "Cluster: $CLUSTER_NAME"
echo "Region:  $REGION"
echo "Wait:    ${WAIT_SECONDS}s between stages"
echo "=============================================="
echo ""

scale_service() {
    local service_suffix=$1
    local count=$2
    # Service names use project name prefix, not cluster name
    local project_name="${CLUSTER_NAME%-cluster}"
    local service_name="${project_name}-${service_suffix}"
    
    if $DRY_RUN; then
        echo "  [DRY-RUN] Would scale $service_name to $count"
    else
        aws ecs update-service \
            --cluster "$CLUSTER_NAME" \
            --service "$service_name" \
            --desired-count "$count" \
            --region "$REGION" \
            --no-cli-pager \
            > /dev/null
        echo "  ✓ Scaled $service_name to $count"
    fi
}

wait_for_stable() {
    local service_suffix=$1
    local project_name="${CLUSTER_NAME%-cluster}"
    local service_name="${project_name}-${service_suffix}"
    
    if $DRY_RUN; then
        echo "  [DRY-RUN] Would wait for $service_name to stabilize"
        return
    fi
    
    echo "  Waiting for $service_name to stabilize..."
    aws ecs wait services-stable \
        --cluster "$CLUSTER_NAME" \
        --services "$service_name" \
        --region "$REGION" \
        2>/dev/null || true
}

for stage_config in "${STAGES[@]}"; do
    IFS='|' read -r stage_num service_suffix count description <<< "$stage_config"
    
    if [[ $stage_num -lt $START_STAGE ]]; then
        echo "Stage $stage_num: $description - SKIPPED"
        continue
    fi
    
    echo "Stage $stage_num: $description"
    echo "----------------------------------------------"
    
    scale_service "$service_suffix" "$count"
    
    # Wait for service to stabilize before proceeding
    # Stage 0 (observability) only needs 10s, others need full wait for reservoir fill
    if ! $DRY_RUN && [[ $stage_num -lt 5 ]]; then
        if [[ $stage_num -eq 0 ]]; then
            echo "  Waiting 10s for observability to start..."
            sleep 10
        else
            echo "  Waiting ${WAIT_SECONDS}s for reservoirs to fill..."
            sleep "$WAIT_SECONDS"
        fi
    fi
    
    echo ""
done

echo "=============================================="
if $DRY_RUN; then
    echo "DRY RUN COMPLETE - no changes made"
else
    echo "All services started!"
    echo ""
    echo "Monitor progress:"
    echo "  - DSQL console for connection count"
    echo "  - Grafana for reservoir metrics"
    echo "  - CloudWatch logs for errors"
fi
echo "=============================================="
