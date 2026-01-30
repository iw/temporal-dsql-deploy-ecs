#!/bin/bash
# -----------------------------------------------------------------------------
# Temporal ECS Cluster Management
# -----------------------------------------------------------------------------
# This script provides utilities for managing Temporal ECS services:
# - Scale services up/down
# - Clean cluster membership table (for crash loop recovery)
# - Wait for EC2 instances to register
# - Ordered service startup for ringpop cluster formation
#
# Usage:
#   ./scripts/cluster-management.sh <environment> <command>
#
# Arguments:
#   environment    Environment to operate on (dev, bench, prod)
#
# Commands:
#   scale-down       - Scale all services to 0
#   clean-membership - Prompt to clean cluster_membership table
#   wait-ec2         - Wait for EC2 instances to register
#   scale-up         - Scale up services one at a time
#   force-deploy     - Force new deployment for all services
#   status           - Show cluster and service status
#   recover          - Full crash loop recovery
#
# Prerequisites:
# - AWS CLI configured with appropriate permissions
# - Terraform applied for the environment
# - DSQL cluster endpoint available (for clean-membership)
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Available environments
AVAILABLE_ENVS=("dev" "bench" "prod")

# Default values
ENVIRONMENT=""
COMMAND=""
CLUSTER_NAME=""
REGION=""
PROJECT_NAME=""

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    echo "Usage: $0 <environment> <command>"
    echo ""
    echo "Arguments:"
    echo "  environment    Environment to operate on (dev, bench, prod)"
    echo ""
    echo "Commands:"
    echo "  scale-down       - Scale all services to 0"
    echo "  clean-membership - Prompt to clean cluster_membership table"
    echo "  wait-ec2         - Wait for EC2 instances to register"
    echo "  scale-up         - Scale up services one at a time"
    echo "  force-deploy     - Force new deployment for all services"
    echo "  status           - Show cluster and service status"
    echo "  recover          - Full crash loop recovery"
    echo ""
    echo "Available environments: ${AVAILABLE_ENVS[*]}"
    echo ""
    echo "Examples:"
    echo "  $0 dev status"
    echo "  $0 bench scale-down"
    echo "  $0 prod recover"
    exit 1
}

# Validate environment
validate_environment() {
    local env="$1"
    local env_dir="$PROJECT_ROOT/terraform/envs/$env"
    
    local valid=false
    for available_env in "${AVAILABLE_ENVS[@]}"; do
        if [ "$env" = "$available_env" ]; then
            valid=true
            break
        fi
    done
    
    if [ "$valid" = false ]; then
        log_error "Invalid environment '$env'"
        echo ""
        echo "Available environments: ${AVAILABLE_ENVS[*]}"
        exit 1
    fi
    
    if [ ! -d "$env_dir" ]; then
        log_error "Environment directory not found: terraform/envs/$env"
        exit 1
    fi
}

# Read configuration from Terraform outputs
read_terraform_config() {
    local env_dir="$PROJECT_ROOT/terraform/envs/$ENVIRONMENT"
    
    log_info "Reading configuration from Terraform ($ENVIRONMENT environment)..."
    
    cd "$env_dir"
    
    # Get cluster name from terraform output
    CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null) || {
        log_error "Could not get cluster name from terraform output"
        echo "Make sure terraform has been applied for the $ENVIRONMENT environment"
        exit 1
    }
    
    # Get region from terraform output
    REGION=$(terraform output -raw region 2>/dev/null) || REGION="eu-west-1"
    
    # Extract project name from cluster name (remove -cluster suffix)
    PROJECT_NAME="${CLUSTER_NAME%-cluster}"
    
    cd "$PROJECT_ROOT"
    
    log_info "Environment: $ENVIRONMENT"
    log_info "Project: $PROJECT_NAME"
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Region: $REGION"
}

# Get service names (ADOT runs as sidecar, not separate service)
get_service_names() {
    echo "${PROJECT_NAME}-temporal-frontend"
    echo "${PROJECT_NAME}-temporal-history"
    echo "${PROJECT_NAME}-temporal-matching"
    echo "${PROJECT_NAME}-temporal-worker"
    echo "${PROJECT_NAME}-temporal-ui"
    echo "${PROJECT_NAME}-grafana"
}

# Scale all services to 0
scale_down_all() {
    log_info "Scaling down all Temporal services to 0..."
    
    local services
    services=($(get_service_names))
    
    for service in "${services[@]}"; do
        log_info "Scaling down $service..."
        aws ecs update-service \
            --cluster "$CLUSTER_NAME" \
            --service "$service" \
            --desired-count 0 \
            --region "$REGION" \
            --no-cli-pager 2>/dev/null || log_warn "Service $service not found or already scaled down"
    done
    
    log_info "Waiting for services to scale down..."
    sleep 30
    
    # Wait for running tasks to stop
    for service in "${services[@]}"; do
        log_info "Waiting for $service tasks to stop..."
        aws ecs wait services-stable \
            --cluster "$CLUSTER_NAME" \
            --services "$service" \
            --region "$REGION" 2>/dev/null || true
    done
}

# Clean cluster_membership table
clean_membership() {
    log_info "Cleaning cluster_membership table in DSQL..."
    
    # Get DSQL endpoint from Terraform
    local env_dir="$PROJECT_ROOT/terraform/envs/$ENVIRONMENT"
    cd "$env_dir"
    
    local dsql_endpoint
    dsql_endpoint=$(terraform output -raw dsql_cluster_endpoint 2>/dev/null) || {
        # Try to get from tfvars
        if [ -f "terraform.tfvars" ]; then
            dsql_endpoint=$(grep -E "^dsql_cluster_endpoint" terraform.tfvars | cut -d'"' -f2 || echo "")
        fi
    }
    
    cd "$PROJECT_ROOT"
    
    if [ -z "$dsql_endpoint" ]; then
        log_warn "Could not get DSQL endpoint from terraform."
        log_warn "Please clean cluster_membership manually."
        log_warn "Run: DELETE FROM cluster_membership;"
        return 1
    fi
    
    log_info "DSQL endpoint: $dsql_endpoint"
    log_warn "Please connect to DSQL and run: DELETE FROM cluster_membership;"
    log_warn "You can use temporal-dsql-tool or psql with IAM auth."
    
    read -p "Press Enter after cleaning cluster_membership table..."
}

# Wait for EC2 instances to register with ECS
wait_for_ec2() {
    log_info "Waiting for EC2 instances to register with ECS cluster..."
    
    local max_attempts=30
    local attempt=0
    
    # Read expected instance count from terraform output
    local env_dir="$PROJECT_ROOT/terraform/envs/$ENVIRONMENT"
    cd "$env_dir"
    
    local expected_instances
    expected_instances=$(terraform output -raw ec2_instance_count 2>/dev/null) || expected_instances=6
    
    cd "$PROJECT_ROOT"
    
    while [ "$attempt" -lt "$max_attempts" ]; do
        local instance_count
        instance_count=$(aws ecs describe-clusters \
            --clusters "$CLUSTER_NAME" \
            --region "$REGION" \
            --query 'clusters[0].registeredContainerInstancesCount' \
            --output text 2>/dev/null || echo "0")
        
        # Ensure instance_count is a valid number
        if ! [ "$instance_count" -eq "$instance_count" ] 2>/dev/null; then
            instance_count=0
        fi
        
        if [ "$instance_count" -ge "$expected_instances" ]; then
            log_info "EC2 instances registered: $instance_count"
            return 0
        fi
        
        log_info "Waiting for EC2 instances... ${instance_count}/${expected_instances} registered, attempt $((attempt+1))/${max_attempts}"
        sleep 10
        attempt=$((attempt+1))
    done
    
    log_error "Timeout waiting for EC2 instances to register"
    return 1
}

# Scale up services one at a time
scale_up_services() {
    log_info "Scaling up Temporal services..."
    
    # Production service counts (ADOT runs as sidecar, not separate service)
    # Order matters: History first for shard ownership, then Matching, Frontend, Worker, UI
    # This ensures ringpop cluster forms correctly
    local services=(
        "${PROJECT_NAME}-temporal-history:4"
        "${PROJECT_NAME}-temporal-matching:3"
        "${PROJECT_NAME}-temporal-frontend:2"
        "${PROJECT_NAME}-temporal-worker:2"
        "${PROJECT_NAME}-temporal-ui:1"
        "${PROJECT_NAME}-grafana:1"
    )
    
    for service_count in "${services[@]}"; do
        local service="${service_count%%:*}"
        local count="${service_count##*:}"
        
        log_info "Scaling up $service to $count..."
        aws ecs update-service \
            --cluster "$CLUSTER_NAME" \
            --service "$service" \
            --desired-count "$count" \
            --region "$REGION" \
            --no-cli-pager
        
        log_info "Waiting for $service to stabilize..."
        aws ecs wait services-stable \
            --cluster "$CLUSTER_NAME" \
            --services "$service" \
            --region "$REGION" || log_warn "$service may not be fully stable yet"
        
        # Give ringpop time to form
        sleep 15
    done
    
    log_info "All Temporal services scaled up."
}

# Force new deployment (after image update)
force_new_deployment() {
    log_info "Forcing new deployment for all services..."
    
    local services
    services=($(get_service_names))
    
    for service in "${services[@]}"; do
        log_info "Forcing new deployment for $service..."
        aws ecs update-service \
            --cluster "$CLUSTER_NAME" \
            --service "$service" \
            --force-new-deployment \
            --region "$REGION" \
            --no-cli-pager 2>/dev/null || log_warn "Service $service not found"
    done
    
    log_info "New deployments triggered. Monitor progress in ECS console."
}

# Show cluster status
show_status() {
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Region: $REGION"
    echo ""
    
    # Show EC2 instances
    log_info "EC2 Container Instances:"
    aws ecs list-container-instances \
        --cluster "$CLUSTER_NAME" \
        --region "$REGION" \
        --query 'containerInstanceArns' \
        --output text 2>/dev/null | tr '\t' '\n' | while read arn; do
        if [ -n "$arn" ]; then
            aws ecs describe-container-instances \
                --cluster "$CLUSTER_NAME" \
                --container-instances "$arn" \
                --region "$REGION" \
                --query 'containerInstances[0].{status:status,cpu:remainingResources[?name==`CPU`].integerValue|[0],memory:remainingResources[?name==`MEMORY`].integerValue|[0]}' \
                --output table 2>/dev/null || true
        fi
    done
    echo ""
    
    # Show services
    log_info "ECS Services:"
    local services
    services=($(get_service_names))
    aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "${services[@]}" \
        --region "$REGION" \
        --query 'services[].{name:serviceName,desired:desiredCount,running:runningCount,status:status}' \
        --output table 2>/dev/null || log_warn "Could not get service status"
}

# Recover from crash loop
recover() {
    log_info "Starting crash loop recovery..."
    log_warn "This will scale down all services, clean cluster_membership, and scale up."
    
    echo -n "Continue? [y/n] "
    read -r REPLY
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "Recovery cancelled."
        exit 1
    fi
    
    scale_down_all
    clean_membership
    scale_up_services
    
    log_info "Recovery complete!"
}

# Main execution
main() {
    # Parse arguments
    if [ $# -lt 2 ]; then
        show_usage
    fi
    
    ENVIRONMENT="$1"
    COMMAND="$2"
    
    # Validate environment
    validate_environment "$ENVIRONMENT"
    
    # Read terraform config
    read_terraform_config
    
    case "$COMMAND" in
        scale-down)
            scale_down_all
            ;;
        clean-membership)
            clean_membership
            ;;
        wait-ec2)
            wait_for_ec2
            ;;
        scale-up)
            scale_up_services
            ;;
        force-deploy)
            force_new_deployment
            ;;
        status)
            show_status
            ;;
        recover)
            recover
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            show_usage
            ;;
    esac
    
    log_info "Done!"
}

main "$@"
