#!/bin/bash
set -euo pipefail

# Setup DSQL schema using temporal-dsql-tool
# This script uses the dedicated DSQL schema tool for simplified setup
#
# Usage:
#   ./scripts/setup-schema.sh [OPTIONS]
#
# Options:
#   --endpoint ENDPOINT    DSQL cluster endpoint (required if not using --from-terraform)
#   --region REGION        AWS region (default: eu-west-1 or AWS_REGION env var)
#   --database DATABASE    Database name (default: postgres)
#   --user USER            Database user (default: admin)
#   --from-terraform       Read DSQL endpoint from Terraform outputs
#   --temporal-dsql PATH   Path to temporal-dsql repository (default: ../temporal-dsql)
#   --overwrite            Drop existing tables and recreate schema
#   -h, --help             Show this help message

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Default values
DSQL_ENDPOINT=""
AWS_REGION="${AWS_REGION:-eu-west-1}"
DATABASE="postgres"
DB_USER="admin"
DB_PORT="5432"
FROM_TERRAFORM=false
TEMPORAL_DSQL_PATH="../temporal-dsql"
OVERWRITE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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
        --from-terraform)
            FROM_TERRAFORM=true
            shift
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
            head -20 "$0" | tail -17
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "=== Setting up DSQL Schema ==="
echo ""

# Get DSQL endpoint from Terraform if requested
if [ "$FROM_TERRAFORM" = true ]; then
    echo "Reading DSQL endpoint from Terraform outputs..."
    
    if [ ! -d "terraform" ]; then
        echo "❌ terraform directory not found"
        exit 1
    fi
    
    cd terraform
    
    # Check if Terraform is initialized
    if [ ! -d ".terraform" ]; then
        echo "❌ Terraform not initialized. Run 'terraform init' first."
        exit 1
    fi
    
    # Try to get the DSQL endpoint from terraform.tfvars or state
    if [ -f "terraform.tfvars" ]; then
        DSQL_ENDPOINT=$(grep -E "^dsql_cluster_endpoint" terraform.tfvars | cut -d'"' -f2 || true)
    fi
    
    if [ -z "$DSQL_ENDPOINT" ]; then
        echo "❌ Could not find dsql_cluster_endpoint in terraform.tfvars"
        echo "Please specify --endpoint or add dsql_cluster_endpoint to terraform.tfvars"
        exit 1
    fi
    
    # Get region from tfvars if available
    TFVARS_REGION=$(grep -E "^region" terraform.tfvars | cut -d'"' -f2 || true)
    if [ -n "$TFVARS_REGION" ]; then
        AWS_REGION="$TFVARS_REGION"
    fi
    
    cd "$PROJECT_ROOT"
    echo "✅ Found DSQL endpoint: $DSQL_ENDPOINT"
fi

# Validate DSQL endpoint is set
if [ -z "$DSQL_ENDPOINT" ]; then
    echo "❌ DSQL endpoint not specified"
    echo ""
    echo "Usage:"
    echo "  $0 --endpoint <dsql-endpoint> [--region <region>]"
    echo "  $0 --from-terraform"
    echo ""
    echo "Examples:"
    echo "  $0 --endpoint my-cluster.dsql.eu-west-1.on.aws"
    echo "  $0 --from-terraform"
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
