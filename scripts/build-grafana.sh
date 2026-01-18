#!/bin/bash
set -euo pipefail

# Build and push custom Grafana image with pre-configured dashboards
#
# Usage: ./scripts/build-grafana.sh [aws-region]
#
# Arguments:
#   aws-region    AWS region (default: eu-west-1)
#
# Examples:
#   ./scripts/build-grafana.sh
#   ./scripts/build-grafana.sh us-east-1
#
# The script can also use --from-terraform to read region from Terraform outputs.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Parse arguments
FROM_TERRAFORM=false
AWS_REGION=""

for arg in "$@"; do
    case $arg in
        --from-terraform)
            FROM_TERRAFORM=true
            ;;
        *)
            # Positional argument - treat as region
            if [ -z "$AWS_REGION" ]; then
                AWS_REGION="$arg"
            fi
            ;;
    esac
done

# Get configuration
if [ "$FROM_TERRAFORM" = true ]; then
    cd "$PROJECT_ROOT/terraform"
    if terraform state list &>/dev/null && terraform output -json 2>/dev/null | grep -q '"region"'; then
        AWS_REGION=$(terraform output -raw region)
        AWS_ACCOUNT_ID=$(terraform output -raw aws_account_id 2>/dev/null || aws sts get-caller-identity --query Account --output text)
    else
        echo "Note: Terraform state not found or no outputs. Using defaults and AWS CLI."
        AWS_REGION="${AWS_REGION:-eu-west-1}"
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    cd "$PROJECT_ROOT"
else
    # Default to eu-west-1 if not specified
    AWS_REGION="${AWS_REGION:-eu-west-1}"
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
fi

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

IMAGE_NAME="temporal-grafana"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE="${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "=== Building Grafana Image ==="
echo "Region: $AWS_REGION"
echo "Registry: $ECR_REGISTRY"
echo "Image: $FULL_IMAGE"
echo ""

# Authenticate with ECR
echo "Authenticating with ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"

# Create ECR repository if it doesn't exist
echo "Ensuring ECR repository exists..."
aws ecr describe-repositories --repository-names "$IMAGE_NAME" --region "$AWS_REGION" 2>/dev/null || \
    aws ecr create-repository --repository-name "$IMAGE_NAME" --region "$AWS_REGION"

# Build the image
echo "Building Grafana image..."
cd "$PROJECT_ROOT/grafana"
docker build --platform linux/arm64 -t "$IMAGE_NAME:$IMAGE_TAG" .
docker tag "$IMAGE_NAME:$IMAGE_TAG" "$FULL_IMAGE"

# Push to ECR
echo "Pushing to ECR..."
docker push "$FULL_IMAGE"

echo ""
echo "✅ Grafana image built and pushed successfully!"
echo "Image: $FULL_IMAGE"
echo ""
echo "Update terraform.tfvars with:"
echo "  grafana_image = \"$FULL_IMAGE\""
