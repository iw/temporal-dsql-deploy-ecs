#!/bin/bash
set -eo pipefail

# Scale Temporal ECS services up or down
#
# Usage:
#   ./scripts/scale-services.sh <environment> [up|down] [OPTIONS]
#
# Arguments:
#   environment        Environment to operate on (dev, bench, prod)
#
# Commands:
#   up      Scale services up (uses terraform.tfvars counts, or --wps preset)
#   down    Scale all services to 0 replicas
#
# Options:
#   --region REGION        AWS region (default: from terraform output)
#   --wps WPS              Target workflows per second (50, 100, 200, 400)
#   --apply                Update terraform.tfvars and run terraform apply (requires --wps)
#   -h, --help             Show this help message
#
# WPS Presets (optional, for --wps flag):
#   --wps 50   history=3,  matching=2,  frontend=2, worker=2
#   --wps 100  history=6,  matching=4,  frontend=3, worker=2
#   --wps 200  history=16, matching=16, frontend=9, worker=3
#   --wps 400  history=16, matching=16, frontend=9, worker=3
#
# Examples:
#   ./scripts/scale-services.sh dev up                     # Scale using terraform.tfvars counts
#   ./scripts/scale-services.sh dev up --wps 100           # Scale dev for 100 WPS
#   ./scripts/scale-services.sh bench up --wps 200 --apply # Full setup with terraform
#   ./scripts/scale-services.sh prod down                  # Scale prod to 0
#
# Available Environments:
#   dev    Development environment (minimal resources)
#   bench  Benchmark environment (includes benchmark module)
#   prod   Production environment (production-grade resources)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Available environments
AVAILABLE_ENVS=("dev" "bench" "prod")

# Default values
ENVIRONMENT=""
COMMAND=""
AWS_REGION=""
CLUSTER_NAME=""
PROJECT_NAME=""
TARGET_WPS=""
APPLY_TERRAFORM=false

# Function to show usage
show_usage() {
    head -36 "$0" | tail -34
    exit 0
}

# Function to validate environment
validate_environment() {
    local env="$1"
    local env_dir="terraform/envs/$env"
    
    # Check if environment is in the list of available environments
    local valid=false
    for available_env in "${AVAILABLE_ENVS[@]}"; do
        if [ "$env" = "$available_env" ]; then
            valid=true
            break
        fi
    done
    
    if [ "$valid" = false ]; then
        echo -e "${RED}Error: Invalid environment '$env'${NC}"
        echo ""
        echo "Available environments: ${AVAILABLE_ENVS[*]}"
        exit 1
    fi
    
    # Check if environment directory exists
    if [ ! -d "$env_dir" ]; then
        echo -e "${RED}Error: Environment directory not found: $env_dir${NC}"
        echo ""
        echo "Available environments: ${AVAILABLE_ENVS[*]}"
        echo ""
        echo "Please ensure the environment has been created in terraform/envs/"
        exit 1
    fi
    
    # Check if terraform has been initialized
    if [ ! -d "$env_dir/.terraform" ]; then
        echo -e "${YELLOW}Warning: Terraform not initialized for environment '$env'${NC}"
        echo "Run: cd $env_dir && terraform init"
    fi
}

# Function to get replica count based on target WPS
get_wps_count() {
    local service="$1"
    local wps="$2"
    
    case "$wps" in
        50)
            case "$service" in
                history)  echo 3 ;;
                matching) echo 2 ;;
                frontend) echo 2 ;;
                worker)   echo 2 ;;
                ui)       echo 1 ;;
                grafana)  echo 1 ;;
                *)        echo 1 ;;
            esac
            ;;
        100)
            case "$service" in
                history)  echo 6 ;;
                matching) echo 4 ;;
                frontend) echo 3 ;;
                worker)   echo 2 ;;
                ui)       echo 1 ;;
                grafana)  echo 1 ;;
                *)        echo 1 ;;
            esac
            ;;
        200)
            case "$service" in
                history)  echo 16 ;;
                matching) echo 16 ;;
                frontend) echo 9 ;;
                worker)   echo 3 ;;
                ui)       echo 1 ;;
                grafana)  echo 1 ;;
                *)        echo 1 ;;
            esac
            ;;
        400)
            case "$service" in
                history)  echo 16 ;;
                matching) echo 16 ;;
                frontend) echo 9 ;;
                worker)   echo 3 ;;
                ui)       echo 1 ;;
                grafana)  echo 1 ;;
                *)        echo 1 ;;
            esac
            ;;
        *)
            echo -e "${RED}Error: Invalid WPS value. Use 50, 100, 200, or 400${NC}" >&2
            exit 1
            ;;
    esac
}

# Function to get CPU for a service based on target WPS
get_wps_cpu() {
    local service="$1"
    local wps="$2"
    
    case "$wps" in
        50)
            case "$service" in
                history)  echo 1024 ;;
                matching) echo 1024 ;;
                frontend) echo 512 ;;
                worker)   echo 512 ;;
                *)        echo 256 ;;
            esac
            ;;
        100)
            case "$service" in
                history)  echo 2048 ;;
                matching) echo 1024 ;;
                frontend) echo 1024 ;;
                worker)   echo 512 ;;
                *)        echo 256 ;;
            esac
            ;;
        200|400)
            case "$service" in
                history)  echo 4096 ;;
                matching) echo 1024 ;;
                frontend) echo 2048 ;;
                worker)   echo 512 ;;
                *)        echo 256 ;;
            esac
            ;;
    esac
}

# Function to get memory for a service based on target WPS
get_wps_memory() {
    local service="$1"
    local wps="$2"
    
    case "$wps" in
        50)
            case "$service" in
                history)  echo 4096 ;;
                matching) echo 2048 ;;
                frontend) echo 2048 ;;
                worker)   echo 1024 ;;
                *)        echo 512 ;;
            esac
            ;;
        100|200|400)
            case "$service" in
                history)  echo 8192 ;;
                matching) echo 2048 ;;
                frontend) echo 4096 ;;
                worker)   echo 1024 ;;
                *)        echo 512 ;;
            esac
            ;;
    esac
}

# Function to update terraform.tfvars with WPS-based resources
update_tfvars_for_wps() {
    local wps="$1"
    local env_dir="$2"
    local tfvars_file="$env_dir/terraform.tfvars"
    
    if [ ! -f "$tfvars_file" ]; then
        echo -e "${YELLOW}Warning: $tfvars_file not found, skipping tfvars update${NC}"
        return 0
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
    
    # Update each variable using sed
    sed -i.bak "s/^temporal_history_cpu.*/temporal_history_cpu    = $history_cpu/" "$tfvars_file"
    sed -i.bak "s/^temporal_history_memory.*/temporal_history_memory = $history_mem/" "$tfvars_file"
    sed -i.bak "s/^temporal_matching_cpu.*/temporal_matching_cpu    = $matching_cpu/" "$tfvars_file"
    sed -i.bak "s/^temporal_matching_memory.*/temporal_matching_memory = $matching_mem/" "$tfvars_file"
    sed -i.bak "s/^temporal_frontend_cpu.*/temporal_frontend_cpu    = $frontend_cpu/" "$tfvars_file"
    sed -i.bak "s/^temporal_frontend_memory.*/temporal_frontend_memory = $frontend_mem/" "$tfvars_file"
    sed -i.bak "s/^temporal_worker_cpu.*/temporal_worker_cpu    = $worker_cpu/" "$tfvars_file"
    sed -i.bak "s/^temporal_worker_memory.*/temporal_worker_memory = $worker_mem/" "$tfvars_file"
    
    # Clean up backup files
    rm -f "${tfvars_file}.bak"
    
    echo -e "${GREEN}✓ Updated terraform.tfvars:${NC}"
    echo "  History:  CPU=$history_cpu, Memory=$history_mem"
    echo "  Matching: CPU=$matching_cpu, Memory=$matching_mem"
    echo "  Frontend: CPU=$frontend_cpu, Memory=$frontend_mem"
    echo "  Worker:   CPU=$worker_cpu, Memory=$worker_mem"
}

# Function to get terraform outputs for an environment
get_terraform_outputs() {
    local env_dir="$1"
    
    echo -e "${BLUE}Reading configuration from Terraform ($ENVIRONMENT environment)...${NC}"
    
    cd "$PROJECT_ROOT/$env_dir"
    
    # Get cluster name from terraform output
    CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null) || {
        echo -e "${RED}Error: Could not get cluster name from terraform output${NC}"
        echo "Make sure terraform has been applied for the $ENVIRONMENT environment"
        exit 1
    }
    
    # Get region from terraform output
    AWS_REGION=$(terraform output -raw region 2>/dev/null) || {
        # Fallback: use default
        AWS_REGION="eu-west-1"
    }
    
    # Extract project name from cluster name (remove -cluster suffix)
    PROJECT_NAME="${CLUSTER_NAME%-cluster}"
    
    cd "$PROJECT_ROOT"
    
    echo -e "${GREEN}✓ Environment: $ENVIRONMENT${NC}"
    echo -e "${GREEN}✓ Project: $PROJECT_NAME${NC}"
    echo -e "${GREEN}✓ Cluster: $CLUSTER_NAME${NC}"
    echo -e "${GREEN}✓ Region: $AWS_REGION${NC}"
}

# Function to get current terraform-configured count for a service
get_terraform_count() {
    local service="$1"
    local env_dir="$2"
    local tfvars_file="$PROJECT_ROOT/$env_dir/terraform.tfvars"
    
    if [ ! -f "$tfvars_file" ]; then
        # Default counts if no tfvars
        case "$service" in
            history)  echo 2 ;;
            matching) echo 2 ;;
            frontend) echo 2 ;;
            worker)   echo 1 ;;
            ui)       echo 1 ;;
            grafana)  echo 1 ;;
            *)        echo 1 ;;
        esac
        return
    fi
    
    # Map service name to terraform variable
    local var_name
    case "$service" in
        history)  var_name="temporal_history_count" ;;
        matching) var_name="temporal_matching_count" ;;
        frontend) var_name="temporal_frontend_count" ;;
        worker)   var_name="temporal_worker_count" ;;
        ui)       var_name="temporal_ui_count" ;;
        grafana)  var_name="grafana_count" ;;
        *)        echo 1; return ;;
    esac
    
    # Extract value from tfvars
    local count=$(grep "^${var_name}" "$tfvars_file" 2>/dev/null | sed 's/.*=\s*//' | tr -d ' ')
    
    if [ -n "$count" ] && [ "$count" -gt 0 ] 2>/dev/null; then
        echo "$count"
    else
        # Default if not found or invalid
        case "$service" in
            history)  echo 2 ;;
            matching) echo 2 ;;
            frontend) echo 2 ;;
            worker)   echo 1 ;;
            *)        echo 1 ;;
        esac
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        dev|bench|prod)
            if [ -z "$ENVIRONMENT" ]; then
                ENVIRONMENT="$1"
            fi
            shift
            ;;
        up|down)
            COMMAND="$1"
            shift
            ;;
        --region)
            AWS_REGION="$2"
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
        -h|--help)
            show_usage
            ;;
        *)
            # Check if this looks like an environment name (first positional arg)
            if [ -z "$ENVIRONMENT" ] && [[ ! "$1" =~ ^-- ]]; then
                echo -e "${RED}Error: Invalid environment '$1'${NC}"
                echo ""
                echo "Available environments: ${AVAILABLE_ENVS[*]}"
                exit 1
            else
                echo -e "${RED}Unknown option: $1${NC}"
                echo ""
                echo "Usage: $0 <environment> [up|down] [OPTIONS]"
                echo ""
                echo "Available environments: ${AVAILABLE_ENVS[*]}"
                exit 1
            fi
            ;;
    esac
done

# Validate environment is provided
if [ -z "$ENVIRONMENT" ]; then
    echo -e "${RED}Error: Environment is required${NC}"
    echo ""
    echo "Usage: $0 <environment> [up|down] [OPTIONS]"
    echo ""
    echo "Available environments: ${AVAILABLE_ENVS[*]}"
    echo ""
    echo "Examples:"
    echo "  $0 dev up --wps 100           # Scale dev for 100 WPS"
    echo "  $0 bench up --wps 200 --apply # Full setup with terraform"
    echo "  $0 prod down                  # Scale prod to 0"
    exit 1
fi

# Validate environment
validate_environment "$ENVIRONMENT"

# Validate command
if [ -z "$COMMAND" ]; then
    echo -e "${RED}Error: Missing command (up or down)${NC}"
    echo ""
    echo "Usage: $0 <environment> [up|down] [OPTIONS]"
    echo ""
    echo "Examples:"
    echo "  $0 $ENVIRONMENT up --wps 100           # Scale for 100 WPS"
    echo "  $0 $ENVIRONMENT up --wps 200 --apply   # Full setup with terraform"
    echo "  $0 $ENVIRONMENT down                   # Scale all to 0"
    exit 1
fi

# Validate --wps is required for 'up' command (unless using --current)
if [ "$COMMAND" = "up" ] && [ -z "$TARGET_WPS" ]; then
    # Default to using current terraform-configured counts
    echo -e "${YELLOW}Note: No --wps specified, using terraform-configured counts${NC}"
    USE_CURRENT_COUNTS=true
else
    USE_CURRENT_COUNTS=false
fi

# Validate --apply requires --wps
if [ "$APPLY_TERRAFORM" = true ] && [ -z "$TARGET_WPS" ]; then
    echo -e "${RED}Error: --apply requires --wps${NC}"
    exit 1
fi

# Set environment directory
ENV_DIR="terraform/envs/$ENVIRONMENT"

# Get terraform outputs
get_terraform_outputs "$ENV_DIR"

# Override region if provided via command line
if [ -n "$2" ] && [ "$2" != "$AWS_REGION" ]; then
    # Region was explicitly set via --region, keep it
    :
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
)

echo ""
echo "=== Scaling ECS Services ==="
echo "Environment: $ENVIRONMENT"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $AWS_REGION"
echo "Command: $COMMAND"
if [ "$COMMAND" = "up" ]; then
    if [ "$USE_CURRENT_COUNTS" = true ]; then
        echo "Mode: Using terraform-configured counts"
        echo "Counts: history=$(get_terraform_count history $ENV_DIR), matching=$(get_terraform_count matching $ENV_DIR), frontend=$(get_terraform_count frontend $ENV_DIR), worker=$(get_terraform_count worker $ENV_DIR), ui=$(get_terraform_count ui $ENV_DIR), grafana=$(get_terraform_count grafana $ENV_DIR)"
    else
        echo "Target WPS: $TARGET_WPS"
        echo "Counts: history=$(get_wps_count history $TARGET_WPS), matching=$(get_wps_count matching $TARGET_WPS), frontend=$(get_wps_count frontend $TARGET_WPS), worker=$(get_wps_count worker $TARGET_WPS), ui=1, grafana=1"
    fi
    if [ "$APPLY_TERRAFORM" = true ]; then
        echo "Resources: Will update terraform.tfvars and apply"
    fi
fi
echo ""

# If --apply is set, update tfvars and run terraform apply
if [ "$APPLY_TERRAFORM" = true ] && [ -n "$TARGET_WPS" ]; then
    echo "=== Updating Terraform Configuration ==="
    update_tfvars_for_wps "$TARGET_WPS" "$ENV_DIR"
    echo ""
    
    echo "=== Running Terraform Apply ==="
    cd "$PROJECT_ROOT/$ENV_DIR"
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
        if [ "$USE_CURRENT_COUNTS" = true ]; then
            TARGET_COUNT=$(get_terraform_count "$SHORT_NAME" "$ENV_DIR")
        else
            TARGET_COUNT=$(get_wps_count "$SHORT_NAME" "$TARGET_WPS")
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
