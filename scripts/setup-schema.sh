#!/bin/bash
set -euo pipefail

# Setup DSQL schema using temporal-dsql-tool
# This script uses the dedicated DSQL schema tool for simplified setup
#
# Usage:
#   ./scripts/setup-schema.sh <environment> [OPTIONS]
#   ./scripts/setup-schema.sh --endpoint ENDPOINT [OPTIONS]
#
# Arguments:
#   environment        Environment to read config from (dev, bench, prod)
#
# Options:
#   --endpoint ENDPOINT    DSQL cluster endpoint (required if not using environment)
#   --region REGION        AWS region (default: from terraform or eu-west-1)
#   --database DATABASE    Database name (default: postgres)
#   --user USER            Database user (default: admin)
#   --temporal-dsql PATH   Path to temporal-dsql repository (default: ../temporal-dsql)
#   --overwrite            Drop existing tables and recreate schema
#   -h, --help             Show this help message
#
# Examples:
#   ./scripts/setup-schema.sh dev
#   ./scripts/setup-schema.sh bench --overwrite
#   ./scripts/setup-schema.sh --endpoint my-cluster.dsql.eu-west-1.on.aws

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Available environments
AVAILABLE_ENVS=("dev" "bench" "prod")

# Default values
ENVIRONMENT=""
DSQL_ENDPOINT=""
AWS_REGION="${AWS_REGION:-eu-west-1}"
DATABASE="postgres"
DB_USER="admin"
DB_PORT="5432"
TEMPORAL_DSQL_PATH="../temporal-dsql"
OVERWRITE=""

# Function to show usage
show_usage() {
    head -24 "$0" | tail -22
    exit 0
}

# Function to validate environment
validate_environment() {
    local env="$1"
    local valid=false
    for available_env in "${AVAILABLE_ENVS[@]}"; do
        if [ "$env" = "$available_env" ]; then
            valid=true
            break
        fi
    done
    
    if [ "$valid" = false ]; then
        return 1
    fi
    return 0
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
        --endpoint)
            DSQL_ENDPOINT="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --database)
            DATABASE="$2"
            shift 2
            ;;
        --user)
            DB_USER="$2"
            shift 2
            ;;
        --temporal-dsql)
            TEMPORAL_DSQL_PATH="$2"
            shift 2
            ;;
        --overwrite)
            OVERWRITE="--overwrite"
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            # Check if it looks like an environment
            if [ -z "$ENVIRONMENT" ] && [[ ! "$1" =~ ^-- ]]; then
                echo -e "${RED}Error: Invalid environment '$1'${NC}"
                echo ""
                echo "Available environments: ${AVAILABLE_ENVS[*]}"
                exit 1
            else
                echo "Unknown option: $1"
                exit 1
            fi
            ;;
    esac
done

echo "=== Setting up DSQL Schema ==="
echo ""

# Get DSQL endpoint from Terraform if environment is specified
if [ -n "$ENVIRONMENT" ] && [ -z "$DSQL_ENDPOINT" ]; then
    echo -e "${BLUE}Reading DSQL endpoint from Terraform ($ENVIRONMENT environment)...${NC}"
    
    ENV_DIR="terraform/envs/$ENVIRONMENT"
    if [ ! -d "$ENV_DIR" ]; then
        echo -e "${RED}❌ Environment directory not found: $ENV_DIR${NC}"
        exit 1
    fi
    
    cd "$ENV_DIR"
    
    # Check if Terraform is initialized
    if [ ! -d ".terraform" ]; then
        echo -e "${RED}❌ Terraform not initialized. Run 'terraform init' first.${NC}"
        exit 1
    fi
    
    # Try to get the DSQL endpoint from terraform output or tfvars
    DSQL_ENDPOINT=$(terraform output -raw dsql_cluster_endpoint 2>/dev/null) || {
        if [ -f "terraform.tfvars" ]; then
            DSQL_ENDPOINT=$(grep -E "^dsql_cluster_endpoint" terraform.tfvars | cut -d'"' -f2 || true)
        fi
    }
    
    if [ -z "$DSQL_ENDPOINT" ]; then
        echo -e "${RED}❌ Could not find dsql_cluster_endpoint${NC}"
        echo "Please specify --endpoint or add dsql_cluster_endpoint to terraform.tfvars"
        exit 1
    fi
    
    # Get region from terraform output if available
    TFVARS_REGION=$(terraform output -raw region 2>/dev/null) || true
    if [ -n "$TFVARS_REGION" ]; then
        AWS_REGION="$TFVARS_REGION"
    fi
    
    cd "$PROJECT_ROOT"
    echo -e "${GREEN}✅ Found DSQL endpoint: $DSQL_ENDPOINT${NC}"
fi

# Validate DSQL endpoint is set
if [ -z "$DSQL_ENDPOINT" ]; then
    echo -e "${RED}❌ DSQL endpoint not specified${NC}"
    echo ""
    echo "Usage:"
    echo "  $0 <environment> [--overwrite]"
    echo "  $0 --endpoint <dsql-endpoint> [--region <region>]"
    echo ""
    echo "Available environments: ${AVAILABLE_ENVS[*]}"
    echo ""
    echo "Examples:"
    echo "  $0 dev"
    echo "  $0 bench --overwrite"
    echo "  $0 --endpoint my-cluster.dsql.eu-west-1.on.aws"
    exit 1
fi

# Check if temporal-dsql-tool exists
TEMPORAL_DSQL_TOOL="$TEMPORAL_DSQL_PATH/temporal-dsql-tool"
if [ ! -f "$TEMPORAL_DSQL_TOOL" ]; then
    echo "❌ temporal-dsql-tool not found at $TEMPORAL_DSQL_TOOL"
    echo ""
    echo "Please ensure the temporal-dsql repository is built:"
    echo "  cd $TEMPORAL_DSQL_PATH && go build ./cmd/tools/temporal-dsql-tool"
    echo ""
    echo "Or specify the path with --temporal-dsql /path/to/temporal-dsql"
    exit 1
fi

# Export AWS_REGION for temporal-dsql-tool
export AWS_REGION

echo "Configuration:"
echo "  DSQL Endpoint: $DSQL_ENDPOINT"
echo "  Database: $DATABASE"
echo "  User: $DB_USER"
echo "  Port: $DB_PORT"
echo "  AWS Region: $AWS_REGION"
if [ -n "$OVERWRITE" ]; then
    echo "  Mode: OVERWRITE (will drop existing tables)"
fi
echo ""

# Setup schema using temporal-dsql-tool with embedded schema
# Note: We use --version 1.12 to create schema_version table required by Temporal server
echo "=== Running temporal-dsql-tool setup-schema ==="
echo "Using embedded schema: dsql/v12/temporal"
echo ""

$TEMPORAL_DSQL_TOOL \
    --endpoint "$DSQL_ENDPOINT" \
    --port "$DB_PORT" \
    --user "$DB_USER" \
    --database "$DATABASE" \
    --region "$AWS_REGION" \
    setup-schema \
    --schema-name "dsql/v12/temporal" \
    --version 1.12 \
    $OVERWRITE

echo ""
echo "✅ Schema setup completed"
echo ""

echo "Key tables that should now exist:"
echo "  - cluster_metadata_info"
echo "  - executions"
echo "  - current_executions"
echo "  - activity_info_maps"
echo "  - timer_info_maps"
echo "  - child_execution_info_maps"
echo "  - request_cancel_info_maps"
echo "  - signal_info_maps"
echo "  - buffered_events"
echo "  - tasks"
echo "  - task_queues"
echo "  - schema_version"
echo "  - And more..."
echo ""

echo "🎉 DSQL schema setup completed!"
echo ""
