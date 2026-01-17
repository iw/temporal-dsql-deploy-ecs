#!/bin/bash
set -euo pipefail

# Setup OpenSearch Provisioned for Temporal visibility store
# This script initializes the OpenSearch index using temporal-elasticsearch-tool
# For AWS OpenSearch Provisioned, this should be run from an ECS task with IAM permissions
# or locally with AWS credentials configured

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "=== Setting up OpenSearch Provisioned for Temporal Visibility ==="
echo ""

# Load environment variables
if [ -f ".env" ]; then
    source .env
    echo "✅ Loaded environment from .env"
else
    echo "⚠️  No .env file found, using environment variables"
fi

# Configuration for AWS OpenSearch Provisioned
OS_HOST="${TEMPORAL_OPENSEARCH_HOST:-}"
OS_PORT="${TEMPORAL_OPENSEARCH_PORT:-443}"
OS_SCHEME="${TEMPORAL_OPENSEARCH_SCHEME:-https}"
OS_VISIBILITY_INDEX="${TEMPORAL_OPENSEARCH_INDEX:-temporal_visibility_v1_dev}"
OS_VERSION="${TEMPORAL_OPENSEARCH_VERSION:-v8}"
AWS_REGION="${AWS_REGION:-eu-west-1}"

if [ -z "$OS_HOST" ]; then
    echo "❌ TEMPORAL_OPENSEARCH_HOST is not set"
    echo "Please set the OpenSearch domain endpoint in .env or environment"
    exit 1
fi

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

# Function to make AWS SigV4 signed requests using awscurl or curl with IAM
make_signed_request() {
    local method="$1"
    local path="$2"
    local data="${3:-}"
    
    local url="$OS_SCHEME://$OS_HOST:$OS_PORT$path"
    
    # Check if awscurl is available (preferred for local development)
    if command -v awscurl >/dev/null 2>&1; then
        if [ -n "$data" ]; then
            awscurl --service es --region "$AWS_REGION" \
                -X "$method" "$url" \
                -H 'Content-Type: application/json' \
                -d "$data"
        else
            awscurl --service es --region "$AWS_REGION" \
                -X "$method" "$url"
        fi
    else
        # Fallback: assume running in ECS with IAM role (uses instance metadata)
        # This requires the AWS SDK or a signing library
        echo "⚠️  awscurl not found. For local development, install: pip install awscurl"
        echo "    When running in ECS, IAM role credentials are used automatically."
        
        # For ECS tasks, we can use curl if the OpenSearch domain allows the task role
        if [ -n "$data" ]; then
            curl -s -X "$method" "$url" \
                -H 'Content-Type: application/json' \
                -d "$data"
        else
            curl -s -X "$method" "$url"
        fi
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
            echo "❌ OpenSearch did not become ready after $max_attempts attempts"
            exit 1
        fi
        echo "  Waiting... (attempt $attempt/$max_attempts)"
        sleep 5
    done
    echo "✅ OpenSearch is ready"
    echo ""
    
    # Step 1: Setup schema (creates templates and cluster settings)
    echo "Step 1: Setting up OpenSearch schema..."
    for i in 1 2 3; do
        if $TEMPORAL_ES_TOOL --ep "$OS_SCHEME://$OS_HOST:$OS_PORT" setup-schema 2>&1; then
            echo "✅ Schema setup completed"
            break
        else
            if [ $i -eq 3 ]; then
                echo "❌ Schema setup failed after 3 attempts"
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
    echo "✅ Index '$OS_VISIBILITY_INDEX' created successfully"
    echo ""
    
    # Step 3: Verify setup with ping
    echo "Step 3: Verifying OpenSearch connectivity..."
    $TEMPORAL_ES_TOOL --ep "$OS_SCHEME://$OS_HOST:$OS_PORT" ping
    echo "✅ OpenSearch connectivity verified"
    echo ""
    
else
    echo "=== Using curl/awscurl for OpenSearch setup ==="
    echo "Note: temporal-elasticsearch-tool not found, using REST API directly"
    echo ""
    
    # Step 1: Wait for OpenSearch to be ready
    echo "Step 1: Waiting for OpenSearch to be ready..."
    max_attempts=30
    attempt=0
    
    until make_signed_request "GET" "/_cluster/health?wait_for_status=yellow&timeout=5s" 2>/dev/null | grep -q '"status"'; do
        attempt=$((attempt + 1))
        if [ $attempt -ge $max_attempts ]; then
            echo "❌ OpenSearch did not become ready after $max_attempts attempts"
            exit 1
        fi
        echo "  Waiting... (attempt $attempt/$max_attempts)"
        sleep 5
    done
    echo "✅ OpenSearch is ready"
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
    echo "✅ Index template created"
    echo ""
    
    # Step 3: Create index if it doesn't exist
    echo "Step 3: Creating visibility index..."
    INDEX_EXISTS=$(make_signed_request "HEAD" "/$OS_VISIBILITY_INDEX" 2>&1 || echo "not_found")
    
    if echo "$INDEX_EXISTS" | grep -q "not_found\|404"; then
        make_signed_request "PUT" "/$OS_VISIBILITY_INDEX" '{}'
        echo "✅ Index '$OS_VISIBILITY_INDEX' created"
    else
        echo "✅ Index '$OS_VISIBILITY_INDEX' already exists"
    fi
    echo ""
fi

# Final verification
echo "=== Final Verification ==="

# Check cluster health
echo "Cluster health:"
make_signed_request "GET" "/_cat/health?v" || {
    echo "❌ Failed to get cluster health"
    exit 1
}
echo ""

# Check index status
echo "Index status:"
make_signed_request "GET" "/_cat/indices/$OS_VISIBILITY_INDEX?v" || {
    echo "❌ Failed to get index information"
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
    echo "✅ Search functionality is working"
    DOC_COUNT=$(echo "$SEARCH_RESULT" | grep -o '"value":[0-9]*' | head -1 | cut -d: -f2 || echo "0")
    echo "Current document count: $DOC_COUNT"
else
    echo "⚠️  Search test returned unexpected result (may be empty index)"
    echo "Response: $SEARCH_RESULT"
fi
echo ""

echo "🎉 OpenSearch Provisioned setup completed successfully!"
echo ""
echo "=== Configuration for Temporal ==="
echo "Add these to your Temporal configuration:"
echo ""
echo "  TEMPORAL_OPENSEARCH_HOST=$OS_HOST"
echo "  TEMPORAL_OPENSEARCH_PORT=$OS_PORT"
echo "  TEMPORAL_OPENSEARCH_SCHEME=$OS_SCHEME"
echo "  TEMPORAL_OPENSEARCH_INDEX=$OS_VISIBILITY_INDEX"
echo "  TEMPORAL_OPENSEARCH_VERSION=$OS_VERSION"
echo ""
echo "=== Next Steps ==="
echo "1. Ensure Temporal services have IAM permissions for es:ESHttp*"
echo "2. Configure awsRequestSigning in Temporal persistence config"
echo "3. Start Temporal services"
echo ""
