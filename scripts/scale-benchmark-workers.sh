#!/bin/bash
set -euo pipefail

# Scale benchmark workers up or down
#
# Usage:
#   ./scripts/scale-benchmark-workers.sh up [count]     # Scale up (default: 30)
#   ./scripts/scale-benchmark-workers.sh down           # Scale to 0
#   ./scripts/scale-benchmark-workers.sh status         # Show current status
#   ./scripts/scale-benchmark-workers.sh --from-terraform up [count]
#
# Resource Planning (with 384 vCPU quota, 380 usable):
#   Main cluster:     10 x m8g.4xlarge = 160 vCPU (Temporal services)
#   Benchmark cluster: 13 x m8g.4xlarge = 208 vCPU (1 generator + 51 workers)
#   Total: 368 vCPU (12 vCPU headroom)
#
# Worker Recommendations:
#   --wps 100:  30 workers (960 pollers)
#   --wps 200:  40 workers (1,280 pollers)
#   --wps 400:  51 workers (1,632 pollers) - max with current quota

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Defaults
DEFAULT_COUNT=30
REGION="eu-west-1"
CLUSTER_NAME=""
SERVICE_NAME=""

usage() {
    echo "Usage: $0 [--from-terraform] <up|down|status> [count]"
    echo ""
    echo "Commands:"
    echo "  up [count]   Scale benchmark workers up (default: $DEFAULT_COUNT)"
    echo "  down         Scale benchmark workers to 0"
    echo "  status       Show current worker status"
    echo ""
    echo "Options:"
    echo "  --from-terraform   Read cluster/service names from terraform output"
    echo ""
    echo "Examples:"
    echo "  $0 --from-terraform up 6"
    echo "  $0 --from-terraform down"
    echo "  $0 --from-terraform status"
    exit 1
}

get_terraform_values() {
    if [ ! -d "$SCRIPT_DIR/../terraform" ]; then
        echo -e "${RED}Error: terraform directory not found${NC}"
        exit 1
    fi
    
    cd "$SCRIPT_DIR/../terraform"
    
    CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null) || {
        echo -e "${RED}Error: Could not get cluster name from terraform${NC}"
        exit 1
    }
    
    SERVICE_NAME="${CLUSTER_NAME%-cluster}-benchmark-worker"
    REGION=$(terraform output -raw region 2>/dev/null) || REGION="eu-west-1"
}

show_status() {
    echo -e "${YELLOW}Benchmark Worker Status${NC}"
    echo "Cluster: $CLUSTER_NAME"
    echo "Service: $SERVICE_NAME"
    echo "Region:  $REGION"
    echo ""
    
    aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE_NAME" \
        --region "$REGION" \
        --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount,status:status}' \
        --output table 2>/dev/null || echo -e "${RED}Service not found${NC}"
}

scale_workers() {
    local count=$1
    
    echo -e "${YELLOW}Scaling benchmark workers to $count...${NC}"
    
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --desired-count "$count" \
        --region "$REGION" \
        --query 'service.{desired:desiredCount,status:status}' \
        --output table
    
    if [ "$count" -gt 0 ]; then
        echo ""
        echo -e "${GREEN}Workers scaling up. Monitor with:${NC}"
        echo "  $0 --from-terraform status"
    else
        echo ""
        echo -e "${GREEN}Workers scaling down.${NC}"
    fi
}

# Parse arguments
FROM_TERRAFORM=false
COMMAND=""
COUNT=$DEFAULT_COUNT

while [[ $# -gt 0 ]]; do
    case $1 in
        --from-terraform)
            FROM_TERRAFORM=true
            shift
            ;;
        up|down|status)
            COMMAND=$1
            shift
            if [[ $# -gt 0 && $1 =~ ^[0-9]+$ ]]; then
                COUNT=$1
                shift
            fi
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

if [ -z "$COMMAND" ]; then
    usage
fi

if [ "$FROM_TERRAFORM" = true ]; then
    get_terraform_values
else
    echo -e "${RED}Error: --from-terraform is required${NC}"
    usage
fi

case $COMMAND in
    up)
        scale_workers "$COUNT"
        ;;
    down)
        scale_workers 0
        ;;
    status)
        show_status
        ;;
    *)
        usage
        ;;
esac
