#!/bin/sh
set -eu

# Render Temporal config template and start the server
# This script:
# 1. Resolves network binding addresses (with ECS metadata support)
# 2. Renders the persistence config template using environment variables
# 3. Starts temporal-server with the rendered config

TEMPLATE_PATH="${TEMPORAL_PERSISTENCE_TEMPLATE:-/etc/temporal/config/persistence-dsql-opensearch.template.yaml}"
OUTPUT_PATH="${TEMPORAL_PERSISTENCE_CONFIG:-/etc/temporal/config/persistence-dsql.yaml}"

echo "=== Temporal DSQL Runtime Startup ==="
echo "Template: $TEMPLATE_PATH"
echo "Output: $OUTPUT_PATH"

# Determine the broadcast address for cluster membership
# In ECS with awsvpc mode, we need to get the task's private IP from the metadata endpoint
if [ -z "${TEMPORAL_BROADCAST_ADDRESS:-}" ]; then
    if [ -n "${ECS_CONTAINER_METADATA_URI_V4:-}" ]; then
        # ECS Fargate/EC2 with awsvpc mode - get IP from metadata endpoint
        echo "Detecting IP from ECS metadata endpoint..."
        TASK_METADATA=$(curl -s --max-time 5 "${ECS_CONTAINER_METADATA_URI_V4}/task" 2>/dev/null || echo "")
        if [ -n "$TASK_METADATA" ]; then
            # Extract the first IPv4 address from the task metadata
            # The metadata structure is: {"Containers":[{"Networks":[{"IPv4Addresses":["10.0.x.x"]}]}]}
            TASK_IP=$(echo "$TASK_METADATA" | sed -n 's/.*"IPv4Addresses":\["\([^"]*\)".*/\1/p' | head -1)
            if [ -n "$TASK_IP" ]; then
                TEMPORAL_BROADCAST_ADDRESS="$TASK_IP"
                echo "Detected ECS task IP from metadata: $TEMPORAL_BROADCAST_ADDRESS"
            fi
        fi
    fi
    
    # Fallback: try to get IP from hostname resolution
    if [ -z "${TEMPORAL_BROADCAST_ADDRESS:-}" ]; then
        HOSTNAME_IP=$(getent hosts "$(hostname)" 2>/dev/null | awk '{print $1}' || echo "")
        if [ -n "$HOSTNAME_IP" ]; then
            TEMPORAL_BROADCAST_ADDRESS="$HOSTNAME_IP"
            echo "Using hostname-resolved IP: $TEMPORAL_BROADCAST_ADDRESS"
        else
            # Last resort: use the first non-loopback IP from ip command
            FIRST_IP=$(ip -4 addr show scope global 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}' | head -1 || echo "")
            if [ -n "$FIRST_IP" ]; then
                TEMPORAL_BROADCAST_ADDRESS="$FIRST_IP"
                echo "Using first non-loopback IP: $TEMPORAL_BROADCAST_ADDRESS"
            else
                echo "WARNING: Could not determine broadcast address, using 127.0.0.1"
                TEMPORAL_BROADCAST_ADDRESS="127.0.0.1"
            fi
        fi
    fi
else
    echo "Using provided TEMPORAL_BROADCAST_ADDRESS: $TEMPORAL_BROADCAST_ADDRESS"
fi
export TEMPORAL_BROADCAST_ADDRESS

# Set bind IP to 0.0.0.0 to listen on all interfaces (required for ECS awsvpc mode)
BIND_ON_IP="${BIND_ON_IP:-0.0.0.0}"
export BIND_ON_IP
echo "Bind IP: $BIND_ON_IP"
echo "Broadcast Address: $TEMPORAL_BROADCAST_ADDRESS"

# Validate required environment variables
echo "Validating configuration..."

check_var() {
    eval val=\$$1
    if [ -z "$val" ]; then
        echo "ERROR: Required environment variable $1 is not set"
        exit 1
    fi
}

check_var TEMPORAL_SQL_HOST
check_var TEMPORAL_SQL_PORT
check_var TEMPORAL_SQL_DATABASE
check_var TEMPORAL_SQL_USER
check_var TEMPORAL_SQL_PLUGIN_NAME
check_var TEMPORAL_SQL_TLS_ENABLED
check_var TEMPORAL_SQL_MAX_CONNS
check_var TEMPORAL_SQL_MAX_IDLE_CONNS
check_var TEMPORAL_SQL_CONNECTION_TIMEOUT
check_var TEMPORAL_SQL_MAX_CONN_LIFETIME
check_var TEMPORAL_HISTORY_SHARDS
check_var TEMPORAL_ELASTICSEARCH_HOST
check_var TEMPORAL_ELASTICSEARCH_INDEX
check_var TEMPORAL_ELASTICSEARCH_VERSION
check_var AWS_REGION

echo "All required variables present"

# Render the config template
echo "Rendering config template..."

if [ ! -f "$TEMPLATE_PATH" ]; then
    echo "ERROR: Template file not found: $TEMPLATE_PATH"
    exit 1
fi

# Use envsubst for simple variable substitution
# Note: envsubst is part of gettext package in Alpine
cat "$TEMPLATE_PATH" | envsubst > "$OUTPUT_PATH"

if [ ! -f "$OUTPUT_PATH" ]; then
    echo "ERROR: Failed to create config file: $OUTPUT_PATH"
    exit 1
fi

echo "Config rendered successfully to $OUTPUT_PATH"

# Determine which service to start
SERVICE="${SERVICES:-}"
if [ -z "$SERVICE" ]; then
    echo "ERROR: SERVICES environment variable not set"
    echo "Set SERVICES to one of: frontend, history, matching, worker"
    exit 1
fi

echo "Starting Temporal $SERVICE service..."

# Start temporal-server with the rendered config
exec temporal-server \
    --config-file "$OUTPUT_PATH" \
    --allow-no-auth \
    start \
    --service "$SERVICE"
