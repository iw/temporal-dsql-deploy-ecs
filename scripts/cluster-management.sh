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
# Prerequisites:
# - AWS CLI configured with appropriate permissions
# - Terraform initialized in terraform/ directory
# - DSQL cluster endpoint available (for clean-membership)
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"
CLUSTER_NAME="${CLUSTER_NAME:-temporal-dev-cluster}"
REGION="${AWS_REGION:-eu-west-1}"
PROJECT_NAME="${PROJECT_NAME:-temporal-dev}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Read configuration from Terraform
read_terraform_config() {
    if [ -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
        local tf_project
        local tf_region
        tf_project=$(grep -E "^project_name" "$TERRAFORM_DIR/terraform.tfvars" | cut -d'"' -f2 || true)
        tf_region=$(grep -E "^region" "$TERRAFORM_DIR/terraform.tfvars" | cut -d'"' -f2 || true)
        
        if [ -n "$tf_project" ]; then
            PROJECT_NAME="$tf_project"
            CLUSTER_NAME="${PROJECT_NAME}-cluster"
        fi
        if [ -n "$tf_region" ]; then
            REGION="$tf_region"
        fi
        
        log_info "Using project: $PROJECT_NAME, cluster: $CLUSTER_NAME, region: $REGION"
    fi
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
    
    read_terraform_config
    
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
    
    read_terraform_config
    
    # Get DSQL endpoint from Terraform
    local dsql_endpoint
    if [ -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
        dsql_endpoint=$(grep -E "^dsql_cluster_endpoint" "$TERRAFORM_DIR/terraform.tfvars" | cut -d'"' -f2 || echo "")
    fi
    
    if [ -z "$dsql_endpoint" ]; then
        log_warn "Could not get DSQL endpoint from terraform.tfvars."
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
    
    read_terraform_config
    
    local max_attempts=30
    local attempt=0
    
    # Read expected instance count from terraform.tfvars, default to 6
    local expected_instances=6
    if [ -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
        local tf_count
        # Extract just the number after the = sign
        tf_count=$(grep -E "^ec2_instance_count\s*=" "$TERRAFORM_DIR/terraform.tfvars" | sed 's/.*=\s*//' | tr -d ' ' || echo "6")
        if [ -n "$tf_count" ] && [ "$tf_count" -eq "$tf_count" ] 2>/dev/null; then
            expected_instances="$tf_count"
        fi
    fi
    
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
    
    read_terraform_config
    
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
    
    read_terraform_config
    
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
    read_terraform_config
    
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
    case "${1:-}" in
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
            echo "Usage: $0 {scale-down|clean-membership|wait-ec2|scale-up|force-deploy|status|recover}"
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
            echo "Environment variables:"
            echo "  CLUSTER_NAME     - ECS cluster name"
            echo "  AWS_REGION       - AWS region"
            echo "  PROJECT_NAME     - Project name prefix"
            echo ""
            echo "Note: Configuration is also read from terraform/terraform.tfvars if present."
            exit 1
            ;;
    esac
    
    log_info "Done!"
}

main "$@"
