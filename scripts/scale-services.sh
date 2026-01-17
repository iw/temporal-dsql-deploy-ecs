#!/bin/bash
set -eo pipefail

# Scale Temporal ECS services up or down
#
# Usage:
#   ./scripts/scale-services.sh [up|down] [OPTIONS]
#
# Commands:
#   up      Scale services to production counts (history=4, matching=3, frontend=2, worker=2, ui=1, grafana=1, adot=1)
#   down    Scale all services to 0 replicas
#
# Options:
#   --region REGION        AWS region (default: eu-west-1 or from terraform.tfvars)
#   --cluster CLUSTER      ECS cluster name (default: from terraform.tfvars project_name)
#   --count COUNT          Override all services to this count for 'up' command
#   --from-terraform       Read cluster name and region from terraform.tfvars
#   -h, --help             Show this help message

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
COMMAND=""
AWS_REGION="${AWS_REGION:-eu-west-1}"
CLUSTER_NAME=""
PROJECT_NAME=""
OVERRIDE_COUNT=""
FROM_TERRAFORM=false

# Function to get production count for a service
get_service_count() {
    local service="$1"
    case "$service" in
        history)  echo 4 ;;
        matching) echo 3 ;;
        frontend) echo 2 ;;
        worker)   echo 2 ;;
        ui)       echo 1 ;;
        grafana)  echo 1 ;;
        adot)     echo 1 ;;
        *)        echo 1 ;;
    esac
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        up|down)
            COMMAND="$1"
            shift
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --count)
            OVERRIDE_COUNT="$2"
            shift 2
            ;;
        --from-terraform)
            FROM_TERRAFORM=true
            shift
            ;;
        -h|--help)
            head -20 "$0" | tail -18
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Validate command
if [ -z "$COMMAND" ]; then
    echo -e "${RED}Error: Missing command (up or down)${NC}"
    echo ""
    echo "Usage: $0 [up|down] [OPTIONS]"
    echo ""
    echo "Examples:"
    echo "  $0 up --from-terraform              # Scale to production counts"
    echo "  $0 up --from-terraform --count 1    # Scale all to 1 replica"
    echo "  $0 down --cluster temporal-dev-cluster --region eu-west-1"
    exit 1
fi

# Read from Terraform if requested
if [ "$FROM_TERRAFORM" = true ]; then
    echo -e "${BLUE}Reading configuration from Terraform...${NC}"
    
    if [ ! -d "terraform" ]; then
        echo -e "${RED}Error: terraform directory not found${NC}"
        exit 1
    fi
    
    if [ -f "terraform/terraform.tfvars" ]; then
        PROJECT_NAME=$(grep -E "^project_name" terraform/terraform.tfvars | cut -d'"' -f2 || echo "temporal-dev")
        TFVARS_REGION=$(grep -E "^region" terraform/terraform.tfvars | cut -d'"' -f2 || true)
        if [ -n "$TFVARS_REGION" ]; then
            AWS_REGION="$TFVARS_REGION"
        fi
    else
        PROJECT_NAME="temporal-dev"
    fi
    
    CLUSTER_NAME="${PROJECT_NAME}-cluster"
    echo -e "${GREEN}✓ Project: $PROJECT_NAME${NC}"
    echo -e "${GREEN}✓ Cluster: $CLUSTER_NAME${NC}"
    echo -e "${GREEN}✓ Region: $AWS_REGION${NC}"
fi

# Validate cluster name
if [ -z "$CLUSTER_NAME" ]; then
    echo -e "${RED}Error: Cluster name not specified${NC}"
    echo "Use --cluster or --from-terraform"
    exit 1
fi

# Determine project name from cluster name if not set
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="${CLUSTER_NAME%-cluster}"
fi

# Function to get short name from full service name
get_short_name() {
    local full_name="$1"
    case "$full_name" in
        *-temporal-history)  echo "history" ;;
        *-temporal-matching) echo "matching" ;;
        *-temporal-frontend) echo "frontend" ;;
        *-temporal-worker)   echo "worker" ;;
        *-temporal-ui)       echo "ui" ;;
        *-grafana)           echo "grafana" ;;
        *-adot)              echo "adot" ;;
        *)                   echo "unknown" ;;
    esac
}

# Ordered list of services
SERVICES=(
    "${PROJECT_NAME}-temporal-history"
    "${PROJECT_NAME}-temporal-matching"
    "${PROJECT_NAME}-temporal-frontend"
    "${PROJECT_NAME}-temporal-worker"
    "${PROJECT_NAME}-temporal-ui"
    "${PROJECT_NAME}-grafana"
    "${PROJECT_NAME}-adot"
)

echo ""
echo "=== Scaling ECS Services ==="
echo "Cluster: $CLUSTER_NAME"
echo "Region: $AWS_REGION"
echo "Command: $COMMAND"
if [ "$COMMAND" = "up" ]; then
    if [ -n "$OVERRIDE_COUNT" ]; then
        echo "Count: $OVERRIDE_COUNT (override for all services)"
    else
        echo "Counts: history=4, matching=3, frontend=2, worker=2, ui=1, grafana=1, adot=1"
    fi
fi
echo ""

# Scale each service
for SERVICE in "${SERVICES[@]}"; do
    SHORT_NAME=$(get_short_name "$SERVICE")
    
    # Determine target count
    if [ "$COMMAND" = "up" ]; then
        if [ -n "$OVERRIDE_COUNT" ]; then
            TARGET_COUNT=$OVERRIDE_COUNT
        else
            TARGET_COUNT=$(get_service_count "$SHORT_NAME")
        fi
    else
        TARGET_COUNT=0
    fi
    
    echo -n "Scaling $SERVICE to $TARGET_COUNT... "
    
    # Check if service exists
    if ! aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE" \
        --region "$AWS_REGION" \
        --query 'services[0].serviceName' \
        --output text 2>/dev/null | grep -q "$SERVICE"; then
        echo -e "${YELLOW}SKIPPED (not found)${NC}"
        continue
    fi
    
    # Update service desired count
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE" \
        --desired-count "$TARGET_COUNT" \
        --region "$AWS_REGION" \
        --output text \
        --query 'service.serviceName' > /dev/null
    
    echo -e "${GREEN}OK${NC}"
done

echo ""

if [ "$COMMAND" = "up" ]; then
    echo -e "${GREEN}=== Services Scaling Up ===${NC}"
    echo ""
    echo "Services are starting. Monitor progress with:"
    echo "  aws ecs describe-services \\"
    echo "    --cluster $CLUSTER_NAME \\"
    echo "    --services ${SERVICES[*]} \\"
    echo "    --region $AWS_REGION \\"
    echo "    --query 'services[].{name:serviceName,running:runningCount,desired:desiredCount}'"
    echo ""
    echo "Or watch the ECS console:"
    echo "  https://${AWS_REGION}.console.aws.amazon.com/ecs/v2/clusters/${CLUSTER_NAME}/services"
else
    echo -e "${YELLOW}=== Services Scaled Down ===${NC}"
    echo ""
    echo "All services have been scaled to 0."
fi
