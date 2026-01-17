#!/bin/bash
# -----------------------------------------------------------------------------
# Setup Grafana Admin Secret in AWS Secrets Manager
# -----------------------------------------------------------------------------
# This script creates the Grafana admin credentials secret required before
# deploying the Terraform infrastructure. It generates a secure random password
# and stores it in Secrets Manager.
#
# Usage:
#   ./setup-grafana-secret.sh [OPTIONS]
#
# Options:
#   -r, --region REGION       AWS region (default: AWS_REGION env var or eu-west-1)
#   -n, --name SECRET_NAME    Secret name (default: grafana/admin)
#   -u, --user USERNAME       Admin username (default: admin)
#   -f, --force               Overwrite existing secret
#   -h, --help                Show this help message
#
# Requirements: 13.6, 13.7, 13.8, 13.9
# -----------------------------------------------------------------------------

set -euo pipefail

# Default values
REGION="${AWS_REGION:-eu-west-1}"
SECRET_NAME="grafana/admin"
ADMIN_USER="admin"
FORCE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Create Grafana admin credentials in AWS Secrets Manager.

Options:
    -r, --region REGION       AWS region (default: \$AWS_REGION or eu-west-1)
    -n, --name SECRET_NAME    Secret name (default: grafana/admin)
    -u, --user USERNAME       Admin username (default: admin)
    -f, --force               Overwrite existing secret
    -h, --help                Show this help message

Examples:
    $(basename "$0")                              # Use defaults
    $(basename "$0") -r us-east-1                 # Specify region
    $(basename "$0") -n myproject/grafana/admin   # Custom secret name
    $(basename "$0") -f                           # Force overwrite existing

EOF
    exit 0
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -n|--name)
            SECRET_NAME="$2"
            shift 2
            ;;
        -u|--user)
            ADMIN_USER="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

log_info "Checking for existing secret: ${SECRET_NAME} in ${REGION}"

# Check if secret already exists
SECRET_EXISTS=false
if aws secretsmanager describe-secret \
    --secret-id "${SECRET_NAME}" \
    --region "${REGION}" \
    &>/dev/null; then
    SECRET_EXISTS=true
fi

if [ "$SECRET_EXISTS" = true ]; then
    if [ "$FORCE" = true ]; then
        log_warn "Secret already exists. Overwriting due to --force flag..."
        
        # Generate new password
        PASSWORD=$(aws secretsmanager get-random-password \
            --password-length 32 \
            --exclude-punctuation \
            --require-each-included-type \
            --query RandomPassword \
            --output text \
            --region "${REGION}")
        
        # Update existing secret
        aws secretsmanager put-secret-value \
            --secret-id "${SECRET_NAME}" \
            --secret-string "{\"admin_user\":\"${ADMIN_USER}\",\"admin_password\":\"${PASSWORD}\"}" \
            --region "${REGION}"
        
        log_info "Secret updated successfully!"
        echo ""
        echo "=============================================="
        echo "  Grafana Admin Credentials (SAVE THESE!)"
        echo "=============================================="
        echo "  Username: ${ADMIN_USER}"
        echo "  Password: ${PASSWORD}"
        echo "  Secret:   ${SECRET_NAME}"
        echo "  Region:   ${REGION}"
        echo "=============================================="
        echo ""
    else
        log_info "Secret already exists: ${SECRET_NAME}"
        log_info "Use --force to overwrite, or retrieve existing password with:"
        echo ""
        echo "  aws secretsmanager get-secret-value \\"
        echo "    --secret-id ${SECRET_NAME} \\"
        echo "    --region ${REGION} \\"
        echo "    --query SecretString \\"
        echo "    --output text | jq -r '.admin_password'"
        echo ""
        exit 0
    fi
else
    log_info "Generating secure random password..."
    
    # Generate secure random password
    PASSWORD=$(aws secretsmanager get-random-password \
        --password-length 32 \
        --exclude-punctuation \
        --require-each-included-type \
        --query RandomPassword \
        --output text \
        --region "${REGION}")
    
    log_info "Creating secret: ${SECRET_NAME}"
    
    # Create the secret
    aws secretsmanager create-secret \
        --name "${SECRET_NAME}" \
        --description "Grafana admin credentials for Temporal ECS deployment" \
        --secret-string "{\"admin_user\":\"${ADMIN_USER}\",\"admin_password\":\"${PASSWORD}\"}" \
        --region "${REGION}" \
        --output text \
        --query ARN
    
    log_info "Secret created successfully!"
    echo ""
    echo "=============================================="
    echo "  Grafana Admin Credentials (SAVE THESE!)"
    echo "=============================================="
    echo "  Username: ${ADMIN_USER}"
    echo "  Password: ${PASSWORD}"
    echo "  Secret:   ${SECRET_NAME}"
    echo "  Region:   ${REGION}"
    echo "=============================================="
    echo ""
    log_info "You can now proceed with Terraform deployment."
fi
