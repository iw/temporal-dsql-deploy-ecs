#!/bin/bash
set -euo pipefail

# Setup OpenSearch Provisioned for Temporal visibility store
#
# Usage:
#   ./scripts/setup-opensearch.sh <environment> [OPTIONS]
#
# Arguments:
#   environment        Environment to operate on (dev, bench, prod)
#
# Options:
#   --region REGION    AWS region (default: from terraform output)
#   --index INDEX      Override visibility index name
#   -h, --help         Show this help message
#
# Examples:
#   ./scripts/setup-opensearch.sh dev
#   ./scripts/setup-opensearch.sh bench --region eu-west-1
#   ./scripts/setup-opensearch.sh prod --index temporal_visibility_v1_prod
#
# Prerequisites:
#   - awscurl installed (pip install awscurl)
#   - AWS credentials configured
#   - Terraform applied for the environment

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
AWS_REGION=""
OS_VISIBILITY_INDEX=""

# Function to show usage
show_usage() {
    head -24 "$0" | tail -22
    exit 0
}

# Function to validate environment
validate_environment() {
    local env="$1"
    local env_dir="terraform/envs/$env"
    
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
    
    if [ ! -d "$env_dir" ]; then
        echo -e "${RED}Error: Environment directory not found: $env_dir${NC}"
        exit 1
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
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --index)
            OS_VISIBILITY_INDEX="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            if [ -z "$ENVIRONMENT" ] && [[ ! "$1" =~ ^-- ]]; then
                echo -e "${RED}Error: Invalid environment '$1'${NC}"
                echo ""
                echo "Available environments: ${AVAILABLE_ENVS[*]}"
                exit 1
            else
                echo -e "${RED}Unknown option: $1${NC}"
                exit 1
            fi
            ;;
    esac
done

# Validate environment is provided
if [ -z "$ENVIRONMENT" ]; then
    echo -e "${RED}Error: Environment is required${NC}"
    echo ""
    echo "Usage: $0 <environment> [OPTIONS]"
    echo ""
    echo "Available environments: ${AVAILABLE_ENVS[*]}"
    exit 1
fi

validate_environment "$ENVIRONMENT"

ENV_DIR="terraform/envs/$ENVIRONMENT"

echo "=== Setting up OpenSearch for Temporal Visibility ==="
echo "Environment: $ENVIRONMENT"
echo ""

# Get configuration from Terraform outputs
echo -e "${BLUE}Reading configuration from Terraform...${NC}"
cd "$PROJECT_ROOT/$ENV_DIR"

# Get OpenSearch endpoint
OS_ENDPOINT=$(terraform output -raw opensearch_endpoint 2>/dev/null) || {
    echo -e "${RED}Error: Could not get opensearch_endpoint from terraform output${NC}"
    echo "Make sure terraform has been applied for the $ENVIRONMENT environment"
    exit 1
}

# Get region from terraform if not provided
if [ -z "$AWS_REGION" ]; then
    AWS_REGION=$(terraform output -raw region 2>/dev/null) || AWS_REGION="eu-west-1"
fi

# Get visibility index from terraform if not provided
if [ -z "$OS_VISIBILITY_INDEX" ]; then
    OS_VISIBILITY_INDEX=$(terraform output -raw opensearch_visibility_index 2>/dev/null) || {
        # Fallback to environment-specific default
        OS_VISIBILITY_INDEX="temporal_visibility_v1_${ENVIRONMENT}"
    }
fi

cd "$PROJECT_ROOT"

# Parse endpoint into host
OS_HOST="$OS_ENDPOINT"
OS_PORT="443"
OS_SCHEME="https"
OS_VERSION="v8"

echo -e "${GREEN}✓ Configuration loaded${NC}"
echo ""
echo "OpenSearch Configuration:"
echo "  Endpoint: $OS_SCHEME://$OS_HOST:$OS_PORT"
echo "  Index: $OS_VISIBILITY_INDEX"
echo "  Version: $OS_VERSION"
echo "  AWS Region: $AWS_REGION"
echo ""

# Check if we have temporal-elasticsearch-tool available
TEMPORAL_ES_TOOL=""
if [ -x "../temporal-dsql/temporal-elasticsearch-tool" ]; then
    TEMPORAL_ES_TOOL="../temporal-dsql/temporal-elasticsearch-tool"
elif [ -x "/usr/local/bin/temporal-elasticsearch-tool" ]; then
    TEMPORAL_ES_TOOL="/usr/local/bin/temporal-elasticsearch-tool"
elif command -v temporal-elasticsearch-tool >/dev/null 2>&1; then
    TEMPORAL_ES_TOOL="temporal-elasticsearch-tool"
fi

# Function to make AWS SigV4 signed requests using awscurl
make_signed_request() {
    local method="$1"
    local path="$2"
    local data="${3:-}"
    
    local url="$OS_SCHEME://$OS_HOST:$OS_PORT$path"
    
    if ! command -v awscurl >/dev/null 2>&1; then
        echo -e "${RED}Error: awscurl not found. Install with: pip install awscurl${NC}"
        exit 1
    fi
    
    if [ -n "$data" ]; then
        awscurl --service es --region "$AWS_REGION" \
            -X "$method" "$url" \
            -H 'Content-Type: application/json' \
            -d "$data"
    else
        awscurl --service es --region "$AWS_REGION" \
            -X "$method" "$url"
    fi
}

# Setup OpenSearch index
if [ -n "$TEMPORAL_ES_TOOL" ]; then
    echo "=== Using temporal-elasticsearch-tool for OpenSearch setup ==="
    echo "Tool location: $TEMPORAL_ES_TOOL"
    echo ""
    
    # Wait for OpenSearch to be ready
    echo "Waiting for OpenSearch to be ready..."
    max_attempts=30
    attempt=0
    
    until make_signed_request "GET" "/_cluster/health?wait_for_status=yellow&timeout=5s" 2>/dev/null | grep -q '"status"'; do
        attempt=$((attempt + 1))
        if [ $attempt -ge $max_attempts ]; then
            echo -e "${RED}❌ OpenSearch did not become ready after $max_attempts attempts${NC}"
            exit 1
        fi
        echo "  Waiting... (attempt $attempt/$max_attempts)"
        sleep 5
    done
    echo -e "${GREEN}✓ OpenSearch is ready${NC}"
    echo ""
    
    # Step 1: Setup schema (creates templates and cluster settings)
    echo "Step 1: Setting up OpenSearch schema..."
    for i in 1 2 3; do
        if $TEMPORAL_ES_TOOL --ep "$OS_SCHEME://$OS_HOST:$OS_PORT" setup-schema 2>&1; then
            echo -e "${GREEN}✓ Schema setup completed${NC}"
            break
        else
            if [ $i -eq 3 ]; then
                echo -e "${RED}❌ Schema setup failed after 3 attempts${NC}"
                exit 1
            fi
            echo "  Retrying schema setup... (attempt $((i+1))/3)"
            sleep 3
        fi
    done
    echo ""
    
    # Step 2: Create visibility index
    echo "Step 2: Creating visibility index..."
    $TEMPORAL_ES_TOOL --ep "$OS_SCHEME://$OS_HOST:$OS_PORT" create-index --index "$OS_VISIBILITY_INDEX"
    echo -e "${GREEN}✓ Index '$OS_VISIBILITY_INDEX' created successfully${NC}"
    echo ""
    
    # Step 3: Verify setup with ping
    echo "Step 3: Verifying OpenSearch connectivity..."
    $TEMPORAL_ES_TOOL --ep "$OS_SCHEME://$OS_HOST:$OS_PORT" ping
    echo -e "${GREEN}✓ OpenSearch connectivity verified${NC}"
    echo ""
    
else
    echo "=== Using awscurl for OpenSearch setup ==="
    echo "Note: temporal-elasticsearch-tool not found, using REST API directly"
    echo ""
    
    # Step 1: Wait for OpenSearch to be ready
    echo "Step 1: Waiting for OpenSearch to be ready..."
    max_attempts=30
    attempt=0
    
    until make_signed_request "GET" "/_cluster/health?wait_for_status=yellow&timeout=5s" 2>/dev/null | grep -q '"status"'; do
        attempt=$((attempt + 1))
        if [ $attempt -ge $max_attempts ]; then
            echo -e "${RED}❌ OpenSearch did not become ready after $max_attempts attempts${NC}"
            exit 1
        fi
        echo "  Waiting... (attempt $attempt/$max_attempts)"
        sleep 5
    done
    echo -e "${GREEN}✓ OpenSearch is ready${NC}"
    echo ""
    
    # Step 2: Create index template
    echo "Step 2: Creating index template..."
    TEMPLATE_BODY='{
        "index_patterns": ["temporal_visibility_v1*"],
        "settings": {
            "number_of_shards": 1,
            "number_of_replicas": 1,
            "index.mapping.total_fields.limit": 2000
        },
        "mappings": {
            "properties": {
                "NamespaceId": { "type": "keyword" },
                "WorkflowId": { "type": "keyword" },
                "RunId": { "type": "keyword" },
                "WorkflowTypeName": { "type": "keyword" },
                "StartTime": { "type": "date", "format": "strict_date_optional_time||epoch_millis" },
                "ExecutionTime": { "type": "date", "format": "strict_date_optional_time||epoch_millis" },
                "CloseTime": { "type": "date", "format": "strict_date_optional_time||epoch_millis" },
                "ExecutionStatus": { "type": "keyword" },
                "TaskQueue": { "type": "keyword" },
                "HistoryLength": { "type": "long" },
                "StateTransitionCount": { "type": "long" },
                "VisibilityTaskKey": { "type": "keyword" },
                "Memo": { "type": "text" },
                "Encoding": { "type": "keyword" },
                "ParentWorkflowId": { "type": "keyword" },
                "ParentRunId": { "type": "keyword" },
                "RootWorkflowId": { "type": "keyword" },
                "RootRunId": { "type": "keyword" },
                "HistorySizeBytes": { "type": "long" },
                "ExecutionDuration": { "type": "long" },
                "TemporalScheduledStartTime": { "type": "date", "format": "strict_date_optional_time||epoch_millis" },
                "TemporalScheduledById": { "type": "keyword" },
                "TemporalSchedulePaused": { "type": "boolean" }
            }
        }
    }'
    
    make_signed_request "PUT" "/_template/temporal_visibility_v1_template" "$TEMPLATE_BODY"
    echo ""
    echo -e "${GREEN}✓ Index template created${NC}"
    echo ""
    
    # Step 3: Create index if it doesn't exist
    echo "Step 3: Creating visibility index..."
    INDEX_EXISTS=$(make_signed_request "HEAD" "/$OS_VISIBILITY_INDEX" 2>&1 || echo "not_found")
    
    if echo "$INDEX_EXISTS" | grep -q "not_found\|404"; then
        make_signed_request "PUT" "/$OS_VISIBILITY_INDEX" '{}'
        echo -e "${GREEN}✓ Index '$OS_VISIBILITY_INDEX' created${NC}"
    else
        echo -e "${GREEN}✓ Index '$OS_VISIBILITY_INDEX' already exists${NC}"
    fi
    echo ""
fi

# Final verification
echo "=== Final Verification ==="

# Check cluster health
echo "Cluster health:"
make_signed_request "GET" "/_cat/health?v" || {
    echo -e "${RED}❌ Failed to get cluster health${NC}"
    exit 1
}
echo ""

# Check index status
echo "Index status:"
make_signed_request "GET" "/_cat/indices/$OS_VISIBILITY_INDEX?v" || {
    echo -e "${RED}❌ Failed to get index information${NC}"
    exit 1
}
echo ""

# Test basic search functionality
echo "Testing search functionality..."
SEARCH_RESULT=$(make_signed_request "POST" "/$OS_VISIBILITY_INDEX/_search" '{
    "query": { "match_all": {} },
    "size": 0
}')

if echo "$SEARCH_RESULT" | grep -q '"hits"'; then
    echo -e "${GREEN}✓ Search functionality is working${NC}"
    DOC_COUNT=$(echo "$SEARCH_RESULT" | grep -o '"value":[0-9]*' | head -1 | cut -d: -f2 || echo "0")
    echo "Current document count: $DOC_COUNT"
else
    echo -e "${YELLOW}⚠️  Search test returned unexpected result (may be empty index)${NC}"
fi
echo ""

echo -e "${GREEN}🎉 OpenSearch setup completed successfully for $ENVIRONMENT environment!${NC}"
echo ""
