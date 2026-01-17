#!/bin/bash
set -euo pipefail

# Build Temporal Benchmark Runner image for ARM64 and push to ECR
#
# Usage: ./scripts/build-benchmark.sh [aws-region]
#
# Prerequisites:
#   - Docker with buildx support
#   - AWS CLI configured with ECR permissions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BENCHMARK_DIR="$PROJECT_ROOT/benchmark"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== Temporal Benchmark Runner ECR Build and Push ==="
echo ""

# Parse arguments
AWS_REGION="${1:-eu-west-1}"
TARGET_ARCH="arm64"

# Validate benchmark directory exists
if [ ! -d "$BENCHMARK_DIR" ]; then
    echo -e "${RED}Error: benchmark directory not found at: $BENCHMARK_DIR${NC}"
    exit 1
fi

if [ ! -f "$BENCHMARK_DIR/Dockerfile" ]; then
    echo -e "${RED}Error: Dockerfile not found in benchmark directory${NC}"
    exit 1
fi

if [ ! -f "$BENCHMARK_DIR/go.mod" ]; then
    echo -e "${RED}Error: go.mod not found in benchmark directory${NC}"
    exit 1
fi

echo "Configuration:"
echo "  Benchmark Directory: $BENCHMARK_DIR"
echo "  AWS Region: $AWS_REGION"
echo "  Target Architecture: $TARGET_ARCH"
echo ""

# Get AWS account ID
echo -e "${BLUE}Getting AWS account ID...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "  Account ID: $AWS_ACCOUNT_ID"

# ECR repository name
ECR_REPO_NAME="temporal-benchmark"
ECR_REPO_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"

echo "  ECR Repository: $ECR_REPO_URL"
echo ""

# Generate timestamp-based version tag
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
GIT_SHA=$(cd "$PROJECT_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
VERSION_TAG="sha-${GIT_SHA}-${TIMESTAMP}"

echo "Image tags:"
echo "  - latest"
echo "  - $VERSION_TAG"
echo ""

# Check if docker buildx is available
if ! docker buildx version &> /dev/null; then
    echo -e "${RED}Error: docker buildx is required for ARM64 builds${NC}"
    echo "Install buildx or use Docker Desktop which includes it."
    exit 1
fi
echo -e "${GREEN}✓ Docker buildx available${NC}"
echo ""

# ============================================================================
# Step 1: Create ECR repository if it doesn't exist
# ============================================================================
echo -e "${BLUE}=== Step 1: Ensuring ECR repository exists ===${NC}"

if ! aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" --region "$AWS_REGION" &> /dev/null; then
    echo "Creating ECR repository: $ECR_REPO_NAME"
    aws ecr create-repository \
        --repository-name "$ECR_REPO_NAME" \
        --image-scanning-configuration scanOnPush=true \
        --region "$AWS_REGION"
    
    # Add lifecycle policy to retain only last 10 untagged images
    aws ecr put-lifecycle-policy \
        --repository-name "$ECR_REPO_NAME" \
        --lifecycle-policy-text '{
            "rules": [{
                "rulePriority": 1,
                "description": "Keep only last 10 untagged images",
                "selection": {
                    "tagStatus": "untagged",
                    "countType": "imageCountMoreThan",
                    "countNumber": 10
                },
                "action": {"type": "expire"}
            }]
        }' \
        --region "$AWS_REGION"
    echo -e "${GREEN}✓ Created ECR repository: $ECR_REPO_NAME${NC}"
else
    echo -e "${GREEN}✓ ECR repository exists: $ECR_REPO_NAME${NC}"
fi
echo ""

# ============================================================================
# Step 2: Authenticate with ECR
# ============================================================================
echo -e "${BLUE}=== Step 2: Authenticating with ECR ===${NC}"
aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
echo -e "${GREEN}✓ ECR authentication successful${NC}"
echo ""

# ============================================================================
# Step 3: Build Docker image using docker buildx
# ============================================================================
echo -e "${BLUE}=== Step 3: Building Docker image for linux/${TARGET_ARCH} ===${NC}"

# Create/use buildx builder for ARM64 builds
BUILDER_NAME="temporal-benchmark-builder"
if ! docker buildx inspect "$BUILDER_NAME" &> /dev/null; then
    echo "Creating buildx builder: $BUILDER_NAME"
    docker buildx create --name "$BUILDER_NAME" --use --driver docker-container
else
    docker buildx use "$BUILDER_NAME"
fi

cd "$BENCHMARK_DIR"

echo "Building and pushing benchmark image..."
docker buildx build \
    --platform "linux/${TARGET_ARCH}" \
    --build-arg "TARGETARCH=${TARGET_ARCH}" \
    --build-arg "ALPINE_TAG=3.23" \
    --file Dockerfile \
    --tag "${ECR_REPO_URL}:latest" \
    --tag "${ECR_REPO_URL}:${VERSION_TAG}" \
    --push \
    .

echo ""
echo -e "${GREEN}✓ Benchmark image built and pushed successfully${NC}"
echo ""

# ============================================================================
# Step 4: Verify the image was pushed
# ============================================================================
echo -e "${BLUE}=== Step 4: Verification ===${NC}"

echo "Verifying benchmark image in ECR..."
aws ecr describe-images \
    --repository-name "$ECR_REPO_NAME" \
    --image-ids imageTag=latest \
    --region "$AWS_REGION" \
    --query 'imageDetails[0].{digest:imageDigest,pushedAt:imagePushedAt,size:imageSizeInBytes}' \
    --output table || echo -e "${YELLOW}Warning: Could not verify benchmark image${NC}"

echo ""
echo -e "${GREEN}=== Build Complete ===${NC}"
echo ""
echo "Benchmark Image:"
echo "  ${ECR_REPO_URL}:latest"
echo "  ${ECR_REPO_URL}:${VERSION_TAG}"
echo ""
echo "Use this in your terraform.tfvars:"
echo "  benchmark_image = \"${ECR_REPO_URL}:latest\""
echo ""
echo -e "${YELLOW}Note: The benchmark image contains:${NC}"
echo "  - Temporal benchmark runner binary (ARM64)"
echo "  - Prometheus metrics endpoint on port 9090"
echo "  - Configurable via environment variables"
echo ""
echo "Environment variables for configuration:"
echo "  BENCHMARK_WORKFLOW_TYPE    - Workflow type: simple, multi-activity, timer, child-workflow"
echo "  BENCHMARK_TARGET_RATE      - Target workflows per second (default: 100)"
echo "  BENCHMARK_DURATION         - Test duration (default: 5m)"
echo "  BENCHMARK_RAMP_UP          - Ramp-up period (default: 30s)"
echo "  BENCHMARK_WORKER_COUNT     - Number of parallel workers (default: 4)"
echo "  TEMPORAL_ADDRESS           - Temporal frontend address (default: temporal-frontend:7233)"
echo ""
