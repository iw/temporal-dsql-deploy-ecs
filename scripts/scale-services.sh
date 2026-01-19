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
#   --wps WPS              Target workflows per second - auto-calculates replica counts and resources
#   --apply                Update terraform.tfvars and run terraform apply (requires --wps)
#   --from-terraform       Read cluster name and region from terraform.tfvars
#   -h, --help             Show this help message
#
# WPS Presets (replica counts and CPU/memory):
#   --wps 25   history=2 (1024/4096), matching=2 (512/2048), frontend=1 (512/2048), worker=1 (512/2048)
#   --wps 50   history=3 (1024/4096), matching=2 (1024/4096), frontend=2 (512/2048), worker=2 (512/2048)
#   --wps 75   history=4 (2048/8192), matching=3 (1024/4096), frontend=2 (1024/4096), worker=2 (1024/4096)
#   --wps 100  history=6 (2048/8192), matching=4 (1024/4096), frontend=3 (1024/4096), worker=2 (1024/4096)
#   --wps 150  history=6 (2048/8192), matching=5 (2048/8192), frontend=3 (1024/4096), worker=3 (1024/4096)
#
# Examples:
#   ./scripts/scale-services.sh up --from-terraform --wps 75 --apply   # Full setup for 75 WPS
#   ./scripts/scale-services.sh up --from-terraform --wps 75           # Scale only (no terraform)
#   ./scripts/scale-services.sh down --from-terraform                  # Scale to 0

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
TARGET_WPS=""
FROM_TERRAFORM=false
APPLY_TERRAFORM=false

# Function to get production count for a service (default profile)
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

# Function to get replica count based on target WPS
get_wps_count() {
    local service="$1"
    local wps="$2"
    
    # Scale based on WPS tiers
    # These are estimates - actual capacity depends on workflow complexity
    if [ "$wps" -le 25 ]; then
        case "$service" in
            history)  echo 2 ;;
            matching) echo 2 ;;
            frontend) echo 1 ;;
            worker)   echo 1 ;;
            ui)       echo 1 ;;
            grafana)  echo 1 ;;
            adot)     echo 1 ;;
            *)        echo 1 ;;
        esac
    elif [ "$wps" -le 50 ]; then
        case "$service" in
            history)  echo 3 ;;
            matching) echo 2 ;;
            frontend) echo 2 ;;
            worker)   echo 2 ;;
            ui)       echo 1 ;;
            grafana)  echo 1 ;;
            adot)     echo 1 ;;
            *)        echo 1 ;;
        esac
    elif [ "$wps" -le 75 ]; then
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
    elif [ "$wps" -le 100 ]; then
        case "$service" in
            history)  echo 6 ;;
            matching) echo 4 ;;
            frontend) echo 3 ;;
            worker)   echo 2 ;;
            ui)       echo 1 ;;
            grafana)  echo 1 ;;
            adot)     echo 1 ;;
            *)        echo 1 ;;
        esac
    else
        # 150+ WPS
        case "$service" in
            history)  echo 6 ;;
            matching) echo 5 ;;
            frontend) echo 3 ;;
            worker)   echo 3 ;;
            ui)       echo 1 ;;
            grafana)  echo 1 ;;
            adot)     echo 1 ;;
            *)        echo 1 ;;
        esac
    fi
}

# Function to get CPU for a service based on target WPS
get_wps_cpu() {
    local service="$1"
    local wps="$2"
    
    if [ "$wps" -le 25 ]; then
        case "$service" in
            history)  echo 1024 ;;
            matching) echo 512 ;;
            frontend) echo 512 ;;
            worker)   echo 512 ;;
            *)        echo 256 ;;
        esac
    elif [ "$wps" -le 50 ]; then
        case "$service" in
            history)  echo 1024 ;;
            matching) echo 1024 ;;
            frontend) echo 512 ;;
            worker)   echo 512 ;;
            *)        echo 256 ;;
        esac
    elif [ "$wps" -le 100 ]; then
        case "$service" in
            history)  echo 2048 ;;
            matching) echo 1024 ;;
            frontend) echo 1024 ;;
            worker)   echo 1024 ;;
            *)        echo 256 ;;
        esac
    else
        # 150+ WPS
        case "$service" in
            history)  echo 2048 ;;
            matching) echo 2048 ;;
            frontend) echo 1024 ;;
            worker)   echo 1024 ;;
            *)        echo 256 ;;
        esac
    fi
}

# Function to get memory for a service based on target WPS
get_wps_memory() {
    local service="$1"
    local wps="$2"
    
    if [ "$wps" -le 25 ]; then
        case "$service" in
            history)  echo 4096 ;;
            matching) echo 2048 ;;
            frontend) echo 2048 ;;
            worker)   echo 2048 ;;
            *)        echo 512 ;;
        esac
    elif [ "$wps" -le 50 ]; then
        case "$service" in
            history)  echo 4096 ;;
            matching) echo 4096 ;;
            frontend) echo 2048 ;;
            worker)   echo 2048 ;;
            *)        echo 512 ;;
        esac
    elif [ "$wps" -le 100 ]; then
        case "$service" in
            history)  echo 8192 ;;
            matching) echo 4096 ;;
            frontend) echo 4096 ;;
            worker)   echo 4096 ;;
            *)        echo 512 ;;
        esac
    else
        # 150+ WPS
        case "$service" in
            history)  echo 8192 ;;
            matching) echo 8192 ;;
            frontend) echo 4096 ;;
            worker)   echo 4096 ;;
            *)        echo 512 ;;
        esac
    fi
}

# Function to update terraform.tfvars with WPS-based resources
update_tfvars_for_wps() {
    local wps="$1"
    local tfvars_file="terraform/terraform.tfvars"
    
    if [ ! -f "$tfvars_file" ]; then
        echo -e "${RED}Error: $tfvars_file not found${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Updating $tfvars_file for $wps WPS...${NC}"
    
    # Get resource values for each service
    local history_cpu=$(get_wps_cpu history "$wps")
    local history_mem=$(get_wps_memory history "$wps")
    local matching_cpu=$(get_wps_cpu matching "$wps")
    local matching_mem=$(get_wps_memory matching "$wps")
    local frontend_cpu=$(get_wps_cpu frontend "$wps")
    local frontend_mem=$(get_wps_memory frontend "$wps")
    local worker_cpu=$(get_wps_cpu worker "$wps")
    local worker_mem=$(get_wps_memory worker "$wps")
    
    # Update or add each variable using sed
    # History
    if grep -q "^temporal_history_cpu" "$tfvars_file"; then
        sed -i.bak "s/^temporal_history_cpu.*/temporal_history_cpu    = $history_cpu/" "$tfvars_file"
    else
        echo "temporal_history_cpu    = $history_cpu" >> "$tfvars_file"
    fi
    if grep -q "^temporal_history_memory" "$tfvars_file"; then
        sed -i.bak "s/^temporal_history_memory.*/temporal_history_memory = $history_mem/" "$tfvars_file"
    else
        echo "temporal_history_memory = $history_mem" >> "$tfvars_file"
    fi
    
    # Matching
    if grep -q "^temporal_matching_cpu" "$tfvars_file"; then
        sed -i.bak "s/^temporal_matching_cpu.*/temporal_matching_cpu    = $matching_cpu/" "$tfvars_file"
    else
        echo "temporal_matching_cpu    = $matching_cpu" >> "$tfvars_file"
    fi
    if grep -q "^temporal_matching_memory" "$tfvars_file"; then
        sed -i.bak "s/^temporal_matching_memory.*/temporal_matching_memory = $matching_mem/" "$tfvars_file"
    else
        echo "temporal_matching_memory = $matching_mem" >> "$tfvars_file"
    fi
    
    # Frontend
    if grep -q "^temporal_frontend_cpu" "$tfvars_file"; then
        sed -i.bak "s/^temporal_frontend_cpu.*/temporal_frontend_cpu    = $frontend_cpu/" "$tfvars_file"
    else
        echo "temporal_frontend_cpu    = $frontend_cpu" >> "$tfvars_file"
    fi
    if grep -q "^temporal_frontend_memory" "$tfvars_file"; then
        sed -i.bak "s/^temporal_frontend_memory.*/temporal_frontend_memory = $frontend_mem/" "$tfvars_file"
    else
        echo "temporal_frontend_memory = $frontend_mem" >> "$tfvars_file"
    fi
    
    # Worker
    if grep -q "^temporal_worker_cpu" "$tfvars_file"; then
        sed -i.bak "s/^temporal_worker_cpu.*/temporal_worker_cpu    = $worker_cpu/" "$tfvars_file"
    else
        echo "temporal_worker_cpu    = $worker_cpu" >> "$tfvars_file"
    fi
    if grep -q "^temporal_worker_memory" "$tfvars_file"; then
        sed -i.bak "s/^temporal_worker_memory.*/temporal_worker_memory = $worker_mem/" "$tfvars_file"
    else
        echo "temporal_worker_memory = $worker_mem" >> "$tfvars_file"
    fi
    
    # Clean up backup files
    rm -f "${tfvars_file}.bak"
    
    echo -e "${GREEN}✓ Updated terraform.tfvars:${NC}"
    echo "  History:  CPU=$history_cpu, Memory=$history_mem"
    echo "  Matching: CPU=$matching_cpu, Memory=$matching_mem"
    echo "  Frontend: CPU=$frontend_cpu, Memory=$frontend_mem"
    echo "  Worker:   CPU=$worker_cpu, Memory=$worker_mem"
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
        --wps)
            TARGET_WPS="$2"
            shift 2
            ;;
        --apply)
            APPLY_TERRAFORM=true
            shift
            ;;
        --from-terraform)
            FROM_TERRAFORM=true
            shift
            ;;
        -h|--help)
            head -35 "$0" | tail -33
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
    echo "  $0 up --from-terraform                      # Scale to production counts"
    echo "  $0 up --from-terraform --wps 75             # Scale for 75 WPS (replica counts only)"
    echo "  $0 up --from-terraform --wps 75 --apply     # Full setup: update tfvars, terraform apply, scale"
    echo "  $0 down --from-terraform                    # Scale all to 0"
    exit 1
fi

# Validate --apply requires --wps
if [ "$APPLY_TERRAFORM" = true ] && [ -z "$TARGET_WPS" ]; then
    echo -e "${RED}Error: --apply requires --wps${NC}"
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
    elif [ -n "$TARGET_WPS" ]; then
        echo "Target WPS: $TARGET_WPS"
        echo "Counts: history=$(get_wps_count history $TARGET_WPS), matching=$(get_wps_count matching $TARGET_WPS), frontend=$(get_wps_count frontend $TARGET_WPS), worker=$(get_wps_count worker $TARGET_WPS), ui=1, grafana=1, adot=1"
        if [ "$APPLY_TERRAFORM" = true ]; then
            echo "Resources: Will update terraform.tfvars and apply"
        fi
    else
        echo "Counts: history=4, matching=3, frontend=2, worker=2, ui=1, grafana=1, adot=1"
    fi
fi
echo ""

# If --apply is set, update tfvars and run terraform apply
if [ "$APPLY_TERRAFORM" = true ] && [ -n "$TARGET_WPS" ]; then
    echo "=== Updating Terraform Configuration ==="
    update_tfvars_for_wps "$TARGET_WPS"
    echo ""
    
    echo "=== Running Terraform Apply ==="
    cd terraform
    terraform apply -auto-approve
    cd "$PROJECT_ROOT"
    echo ""
    echo -e "${GREEN}✓ Terraform apply completed${NC}"
    echo ""
    
    # Wait a moment for task definitions to be registered
    echo "Waiting for task definitions to be registered..."
    sleep 5
fi

# Scale each service
for SERVICE in "${SERVICES[@]}"; do
    SHORT_NAME=$(get_short_name "$SERVICE")
    
    # Determine target count
    if [ "$COMMAND" = "up" ]; then
        if [ -n "$OVERRIDE_COUNT" ]; then
            TARGET_COUNT=$OVERRIDE_COUNT
        elif [ -n "$TARGET_WPS" ]; then
            TARGET_COUNT=$(get_wps_count "$SHORT_NAME" "$TARGET_WPS")
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
