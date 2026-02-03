#!/bin/bash
# -----------------------------------------------------------------------------
# Clear Connection Lease Table
# -----------------------------------------------------------------------------
# Safely clears all items from the DynamoDB connection lease table.
# Use this when stale leases are blocking new connections after service crashes.
#
# IMPORTANT: Only run this when all Temporal services are scaled to 0!
#
# Usage:
#   ./scripts/clear-conn-lease-table.sh [--from-terraform|--table <name>] [--region <region>]
#
# Options:
#   --from-terraform    Read table name and region from Terraform state
#   --table <name>      DynamoDB table name (default: temporal-bench-dsql-conn-lease)
#   --region <region>   AWS region (default: eu-west-1)
#   --dry-run           Show what would be done without executing
#   --force             Skip confirmation prompt
# -----------------------------------------------------------------------------

set -euo pipefail

# Default values
TABLE_NAME="temporal-bench-dsql-conn-lease"
REGION="eu-west-1"
DRY_RUN=false
FORCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --from-terraform)
            cd "$(dirname "$0")/../terraform/envs/bench"
            TABLE_NAME=$(terraform output -raw dsql_conn_lease_table 2>/dev/null || echo "temporal-bench-dsql-conn-lease")
            REGION=$(terraform output -raw region 2>/dev/null || echo "eu-west-1")
            cd - > /dev/null
            shift
            ;;
        --table)
            TABLE_NAME="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "=============================================="
echo "Clear Connection Lease Table"
echo "=============================================="
echo "Table:  $TABLE_NAME"
echo "Region: $REGION"
echo "=============================================="
echo ""

# Get item count first
echo "Checking table item count..."
ITEM_COUNT=$(aws dynamodb describe-table \
    --table-name "$TABLE_NAME" \
    --region "$REGION" \
    --query 'Table.ItemCount' \
    --output text 2>/dev/null || echo "0")

echo "Current item count: $ITEM_COUNT"
echo ""

if [[ "$ITEM_COUNT" == "0" ]]; then
    echo "Table is already empty. Nothing to do."
    exit 0
fi

# Confirmation
if ! $FORCE && ! $DRY_RUN; then
    echo "⚠️  WARNING: This will delete all $ITEM_COUNT items from the table."
    echo "   Only proceed if all Temporal services are scaled to 0!"
    echo ""
    read -p "Are you sure? (yes/no): " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        echo "Aborted."
        exit 1
    fi
fi

if $DRY_RUN; then
    echo "[DRY-RUN] Would delete all items from $TABLE_NAME"
    exit 0
fi

echo ""
echo "Deleting items in batches..."

# Delete items in batches using scan + batch-write-item
DELETED=0
while true; do
    # Scan for items (get pk only, limit to 25 for batch delete)
    ITEMS=$(aws dynamodb scan \
        --table-name "$TABLE_NAME" \
        --region "$REGION" \
        --projection-expression "pk" \
        --limit 25 \
        --output json 2>/dev/null)
    
    COUNT=$(echo "$ITEMS" | jq '.Items | length')
    
    if [[ "$COUNT" == "0" ]]; then
        break
    fi
    
    # Build batch delete request
    DELETE_REQUESTS=$(echo "$ITEMS" | jq -c '[.Items[] | {DeleteRequest: {Key: {pk: .pk}}}]')
    
    # Execute batch delete
    aws dynamodb batch-write-item \
        --region "$REGION" \
        --request-items "{\"$TABLE_NAME\": $DELETE_REQUESTS}" \
        --no-cli-pager > /dev/null
    
    DELETED=$((DELETED + COUNT))
    echo "  Deleted $DELETED items..."
done

echo ""
echo "=============================================="
echo "✓ Cleared $DELETED items from $TABLE_NAME"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. Verify DSQL connections are at 0 in console"
echo "  2. Run staggered startup: ./scripts/staggered-startup.sh"
echo "=============================================="
