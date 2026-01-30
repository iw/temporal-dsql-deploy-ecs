#!/bin/bash
set -euo pipefail

# Scale benchmark workers up or down
#
# Usage:
#   ./scripts/scale-benchmark-workers.sh <environment> <up|down|status> [count]
#
# Arguments:
#   environment        Environment to operate on (dev, bench, prod)
#
# Commands:
#   up [count]         Scale benchmark workers up (default: 30)
#   down               Scale benchmark workers to 0
#   status             Show current worker status
#
# Options:
#   -h, --help         Show this help message
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
#
# Available Environments:
#   dev    Development environment (benchmark usually disabled)
#   bench  Benchmark environment (benchmark enabled by default)
#   prod   Production environment (benchmark usually disabled)
#
# Examples:
#   ./scripts/scale-benchmark-workers.sh bench up 30
#   ./scripts/scale-benchmark-workers.sh bench down
#   ./scripts/scale-benchmark-workers.sh bench status

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
DEFAULT_COUNT=30
ENVIRONMENT=""
COMMAND=""
COUNT=$DEFAULT_COUNT
REGION=""
CLUSTER_NAME=""
SERVICE_NAME=""

# Function to show usage
show_usage() {
    head -38 "$0" | tail -36
    exit 0
}

# Function to validate environment
validate_environment() {
    local env="$1"
    local env_dir="$PROJECT_ROOT/terraform/envs/$env"
    
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
        echo -e "${RED}Error: Environment directory not found: terraform/envs/$env${NC}"
        echo ""
        echo "Available environments: ${AVAILABLE_ENVS[*]}"
        echo ""
        echo "Please ensure the environment has been created in terraform/envs/"
        exit 1
    fi
    
    # Check if terraform has been initialized
    if [ ! -d "$env_dir/.terraform" ]; then
        echo -e "${YELLOW}Warning: Terraform not initialized for environment '$env'${NC}"
        echo "Run: cd terraform/envs/$env && terraform init"
    fi
}

# Function to get terraform values for an environment
get_terraform_values() {
    local env="$1"
    local env_dir="$PROJECT_ROOT/terraform/envs/$env"
    
    if [ ! -d "$env_dir" ]; then
        echo -e "${RED}Error: Environment directory not found: terraform/envs/$env${NC}"
        exit 1
    fi
    
    cd "$env_dir"
    
    # Get cluster name from terraform output
    CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null) || {
        echo -e "${RED}Error: Could not get cluster name from terraform output${NC}"
        echo "Make sure terraform has been applied for the $env environment"
        exit 1
    }
    
    # Get benchmark worker service name from terraform output
    SERVICE_NAME=$(terraform output -raw benchmark_worker_service_name 2>/dev/null) || {
        echo -e "${RED}Error: Could not get benchmark worker service name from terraform output${NC}"
        echo "Make sure benchmark is enabled in the $env environment"
        echo ""
        echo "Benchmark is typically only enabled in the 'bench' environment."
        echo "Check that benchmark_enabled = true in terraform/envs/$env/variables.tf"
        exit 1
    }
    
    # Check if benchmark is enabled (service name will be null if disabled)
    if [ -z "$SERVICE_NAME" ] || [ "$SERVICE_NAME" = "null" ]; then
        echo -e "${RED}Error: Benchmark is not enabled in the '$env' environment${NC}"
        echo ""
        echo "Benchmark is typically only enabled in the 'bench' environment."
        echo "To enable benchmark, set benchmark_enabled = true in terraform/envs/$env/variables.tf"
        exit 1
    fi
    
    # Get region from terraform output
    REGION=$(terraform output -raw region 2>/dev/null || echo "eu-west-1")
    
    cd "$PROJECT_ROOT"
}

# Function to show status
show_status() {
    echo -e "${BLUE}Benchmark Worker Status${NC}"
    echo "Environment: $ENVIRONMENT"
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

# Function to scale workers
scale_workers() {
    local count=$1
    
    echo -e "${BLUE}Scaling benchmark workers to $count...${NC}"
    echo "Environment: $ENVIRONMENT"
    echo "Cluster: $CLUSTER_NAME"
    echo "Service: $SERVICE_NAME"
    echo "Region:  $REGION"
    echo ""
    
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
        echo "  $0 $ENVIRONMENT status"
    else
        echo ""
        echo -e "${GREEN}Workers scaling down.${NC}"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        dev|bench|prod)
            if [ -z "$ENVIRONMENT" ]; then
                ENVIRONMENT="$1"
            fi
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
            show_usage
            ;;
        *)
            if [[ $1 =~ ^[0-9]+$ ]] && [ -n "$COMMAND" ]; then
                COUNT=$1
                shift
            elif [ -z "$ENVIRONMENT" ] && [[ ! "$1" =~ ^-- ]]; then
                echo -e "${RED}Error: Invalid environment '$1'${NC}"
                echo ""
                echo "Available environments: ${AVAILABLE_ENVS[*]}"
                exit 1
            else
                echo -e "${RED}Unknown option: $1${NC}"
                echo ""
                echo "Usage: $0 <environment> <up|down|status> [count]"
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
    echo "Usage: $0 <environment> <up|down|status> [count]"
    echo ""
    echo "Available environments: ${AVAILABLE_ENVS[*]}"
    echo ""
    echo "Examples:"
    echo "  $0 bench up 30      # Scale bench workers to 30"
    echo "  $0 bench down       # Scale bench workers to 0"
    echo "  $0 bench status     # Show bench worker status"
    exit 1
fi

# Validate environment
validate_environment "$ENVIRONMENT"

# Validate command is provided
if [ -z "$COMMAND" ]; then
    echo -e "${RED}Error: Command is required (up, down, or status)${NC}"
    echo ""
    echo "Usage: $0 $ENVIRONMENT <up|down|status> [count]"
    echo ""
    echo "Examples:"
    echo "  $0 $ENVIRONMENT up 30      # Scale workers to 30"
    echo "  $0 $ENVIRONMENT down       # Scale workers to 0"
    echo "  $0 $ENVIRONMENT status     # Show worker status"
    exit 1
fi

# Get terraform values
get_terraform_values "$ENVIRONMENT"

# Execute command
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
        echo -e "${RED}Error: Invalid command '$COMMAND'${NC}"
        echo ""
        echo "Valid commands: up, down, status"
        exit 1
        ;;
esac
