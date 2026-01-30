#!/bin/bash
set -euo pipefail

# Build Temporal DSQL image for ARM64 and push to ECR
# This script follows the same build process as the GitHub Actions workflow in temporal-dsql
#
# Usage: ./scripts/build-and-push-ecr.sh <path-to-temporal-dsql-repo> [aws-region]
#
# Prerequisites:
#   - Go 1.22+ installed
#   - Docker with buildx support
#   - AWS CLI configured with ECR permissions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== Temporal DSQL ECR Build and Push ==="
echo ""

# Check arguments
if [ $# -lt 1 ]; then
    echo -e "${RED}Error: Missing required argument${NC}"
    echo ""
    echo "Usage: $0 <path-to-temporal-dsql-repo> [aws-region]"
    echo ""
    echo "Arguments:"
    echo "  path-to-temporal-dsql-repo  Path to the temporal-dsql source repository"
    echo "  aws-region                  AWS region (default: eu-west-1)"
    echo ""
    echo "Example:"
    echo "  $0 ../temporal-dsql"
    echo "  $0 /home/user/temporal-dsql us-east-1"
    exit 1
fi

TEMPORAL_DSQL_PATH="$(cd "$1" && pwd)"
AWS_REGION="${2:-eu-west-1}"
TARGET_ARCH="arm64"
ALPINE_TAG="3.23"

# Validate temporal-dsql path
if [ ! -d "$TEMPORAL_DSQL_PATH" ]; then
    echo -e "${RED}Error: temporal-dsql directory not found at: $TEMPORAL_DSQL_PATH${NC}"
    exit 1
fi

if [ ! -f "$TEMPORAL_DSQL_PATH/go.mod" ]; then
    echo -e "${RED}Error: go.mod not found in temporal-dsql directory${NC}"
    exit 1
fi

if [ ! -f "$TEMPORAL_DSQL_PATH/Makefile" ]; then
    echo -e "${RED}Error: Makefile not found in temporal-dsql directory${NC}"
    exit 1
fi

echo "Configuration:"
echo "  Temporal DSQL Path: $TEMPORAL_DSQL_PATH"
echo "  AWS Region: $AWS_REGION"
echo "  Target Architecture: $TARGET_ARCH"
echo "  Alpine Tag: $ALPINE_TAG"
echo ""

# Get AWS account ID
echo -e "${BLUE}Getting AWS account ID...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "  Account ID: $AWS_ACCOUNT_ID"

# ECR repository name
ECR_REPO_NAME="temporal-dsql"
ECR_REPO_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"

echo "  ECR Repository: $ECR_REPO_URL"
echo ""

# Generate timestamp-based version tag
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
GIT_SHA=$(cd "$TEMPORAL_DSQL_PATH" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
VERSION_TAG="sha-${GIT_SHA}-${TIMESTAMP}"

echo "Image tags:"
echo "  - latest"
echo "  - $VERSION_TAG"
echo ""

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo -e "${RED}Error: Go is not installed. Please install Go 1.22+${NC}"
    exit 1
fi

GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
echo -e "${GREEN}✓ Go version: $GO_VERSION${NC}"

# Check if docker buildx is available
if ! docker buildx version &> /dev/null; then
    echo -e "${RED}Error: docker buildx is required for ARM64 builds${NC}"
    echo "Install buildx or use Docker Desktop which includes it."
    exit 1
fi
echo -e "${GREEN}✓ Docker buildx available${NC}"
echo ""

# ============================================================================
# Step 1: Build binaries for ARM64 (following GHA build-binaries action)
# ============================================================================
echo -e "${BLUE}=== Step 1: Building binaries for linux/${TARGET_ARCH} ===${NC}"
cd "$TEMPORAL_DSQL_PATH"

# Create build output directory structure (matching GHA organize-binaries)
BUILD_DIR="$TEMPORAL_DSQL_PATH/docker/build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/${TARGET_ARCH}"
mkdir -p "$BUILD_DIR/temporal/schema"

# Build binaries using Make targets (same as GHA workflow)
# Note: -trimpath strips local build paths from binaries for cleaner log output
echo "Building temporal-server..."
GOOS=linux GOARCH=$TARGET_ARCH CGO_ENABLED=0 go build -trimpath -o temporal-server ./cmd/server
cp temporal-server "$BUILD_DIR/${TARGET_ARCH}/"

echo "Building temporal-cassandra-tool..."
GOOS=linux GOARCH=$TARGET_ARCH CGO_ENABLED=0 go build -trimpath -o temporal-cassandra-tool ./cmd/tools/cassandra
cp temporal-cassandra-tool "$BUILD_DIR/${TARGET_ARCH}/"

echo "Building temporal-sql-tool..."
GOOS=linux GOARCH=$TARGET_ARCH CGO_ENABLED=0 go build -trimpath -o temporal-sql-tool ./cmd/tools/sql
cp temporal-sql-tool "$BUILD_DIR/${TARGET_ARCH}/"

echo "Building temporal-elasticsearch-tool..."
GOOS=linux GOARCH=$TARGET_ARCH CGO_ENABLED=0 go build -trimpath -o temporal-elasticsearch-tool ./cmd/tools/elasticsearch
cp temporal-elasticsearch-tool "$BUILD_DIR/${TARGET_ARCH}/"

echo "Building temporal-dsql-tool..."
GOOS=linux GOARCH=$TARGET_ARCH CGO_ENABLED=0 go build -trimpath -o temporal-dsql-tool ./tools/dsql
cp temporal-dsql-tool "$BUILD_DIR/${TARGET_ARCH}/"

echo "Building tdbg..."
GOOS=linux GOARCH=$TARGET_ARCH CGO_ENABLED=0 go build -trimpath -o tdbg ./cmd/tools/tdbg
cp tdbg "$BUILD_DIR/${TARGET_ARCH}/"

# Copy schema files (for admin-tools image)
echo "Copying schema files..."
cp -r schema/* "$BUILD_DIR/temporal/schema/"

echo -e "${GREEN}✓ Binaries built successfully${NC}"
echo ""

# ============================================================================
# Step 2: Create ECR repositories if they don't exist
# ============================================================================
echo -e "${BLUE}=== Step 2: Ensuring ECR repositories exist ===${NC}"

# Create temporal-dsql repository if it doesn't exist
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

# Create temporal-dsql-admin-tools repository if it doesn't exist
ADMIN_TOOLS_REPO_NAME="temporal-dsql-admin-tools"
if ! aws ecr describe-repositories --repository-names "$ADMIN_TOOLS_REPO_NAME" --region "$AWS_REGION" &> /dev/null; then
    echo "Creating ECR repository: $ADMIN_TOOLS_REPO_NAME"
    aws ecr create-repository \
        --repository-name "$ADMIN_TOOLS_REPO_NAME" \
        --image-scanning-configuration scanOnPush=true \
        --region "$AWS_REGION"
    
    # Add lifecycle policy
    aws ecr put-lifecycle-policy \
        --repository-name "$ADMIN_TOOLS_REPO_NAME" \
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
    echo -e "${GREEN}✓ Created ECR repository: $ADMIN_TOOLS_REPO_NAME${NC}"
else
    echo -e "${GREEN}✓ ECR repository exists: $ADMIN_TOOLS_REPO_NAME${NC}"
fi
echo ""

# ============================================================================
# Step 3: Authenticate with ECR
# ============================================================================
echo -e "${BLUE}=== Step 3: Authenticating with ECR ===${NC}"
aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
echo -e "${GREEN}✓ ECR authentication successful${NC}"
echo ""

# ============================================================================
# Step 4: Build Docker image using docker buildx (following GHA build-docker-images)
# ============================================================================
echo -e "${BLUE}=== Step 4: Building Docker image for linux/${TARGET_ARCH} ===${NC}"

# Create/use buildx builder for ARM64 builds
BUILDER_NAME="temporal-dsql-builder"
if ! docker buildx inspect "$BUILDER_NAME" &> /dev/null; then
    echo "Creating buildx builder: $BUILDER_NAME"
    docker buildx create --name "$BUILDER_NAME" --use --driver docker-container
else
    docker buildx use "$BUILDER_NAME"
fi

# Build using the official Dockerfile from temporal-dsql/docker/targets/server.Dockerfile
# but we need to be in the docker directory context
cd "$TEMPORAL_DSQL_PATH/docker"

echo "Building and pushing server image..."
docker buildx build \
    --platform "linux/${TARGET_ARCH}" \
    --build-arg "ALPINE_TAG=${ALPINE_TAG}" \
    --build-arg "TARGETARCH=${TARGET_ARCH}" \
    --file targets/server.Dockerfile \
    --tag "${ECR_REPO_URL}:latest" \
    --tag "${ECR_REPO_URL}:${VERSION_TAG}" \
    --push \
    .

echo ""
echo -e "${GREEN}✓ Server image built and pushed successfully${NC}"
echo ""

# ============================================================================
# Step 5: Build admin-tools image (contains temporal-dsql-tool, temporal-sql-tool, etc.)
# ============================================================================
echo -e "${BLUE}=== Step 5: Building admin-tools image ===${NC}"

ADMIN_TOOLS_REPO_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ADMIN_TOOLS_REPO_NAME}"

# Download Temporal CLI for admin-tools (following GHA workflow)
CLI_VERSION="1.5.1"
echo "Downloading Temporal CLI v${CLI_VERSION} for ${TARGET_ARCH}..."
CLI_URL="https://github.com/temporalio/cli/releases/download/v${CLI_VERSION}/temporal_cli_${CLI_VERSION}_linux_${TARGET_ARCH}.tar.gz"
curl -sL "$CLI_URL" | tar -xz -C "$BUILD_DIR/${TARGET_ARCH}/" temporal

echo "Building and pushing admin-tools image..."
docker buildx build \
    --platform "linux/${TARGET_ARCH}" \
    --build-arg "ALPINE_TAG=${ALPINE_TAG}" \
    --build-arg "TARGETARCH=${TARGET_ARCH}" \
    --file targets/admin-tools.Dockerfile \
    --tag "${ADMIN_TOOLS_REPO_URL}:latest" \
    --tag "${ADMIN_TOOLS_REPO_URL}:${VERSION_TAG}" \
    --push \
    .

echo ""
echo -e "${GREEN}✓ Admin-tools image built and pushed successfully${NC}"
echo ""

# ============================================================================
# Step 6: Build runtime image (extends server with config rendering)
# ============================================================================
echo -e "${BLUE}=== Step 6: Building runtime image ===${NC}"

RUNTIME_REPO_NAME="temporal-dsql-runtime"
RUNTIME_REPO_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${RUNTIME_REPO_NAME}"

# Create runtime repository if it doesn't exist
if ! aws ecr describe-repositories --repository-names "$RUNTIME_REPO_NAME" --region "$AWS_REGION" &> /dev/null; then
    echo "Creating ECR repository: $RUNTIME_REPO_NAME"
    aws ecr create-repository \
        --repository-name "$RUNTIME_REPO_NAME" \
        --image-scanning-configuration scanOnPush=true \
        --region "$AWS_REGION"
    
    # Add lifecycle policy
    aws ecr put-lifecycle-policy \
        --repository-name "$RUNTIME_REPO_NAME" \
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
    echo -e "${GREEN}✓ Created ECR repository: $RUNTIME_REPO_NAME${NC}"
else
    echo -e "${GREEN}✓ ECR repository exists: $RUNTIME_REPO_NAME${NC}"
fi

# Build runtime image from the ECS deploy docker directory
cd "$PROJECT_ROOT/docker"

echo "Building and pushing runtime image..."
docker buildx build \
    --platform "linux/${TARGET_ARCH}" \
    --build-arg "BASE_IMAGE=${ECR_REPO_URL}:latest" \
    --file runtime.Dockerfile \
    --tag "${RUNTIME_REPO_URL}:latest" \
    --tag "${RUNTIME_REPO_URL}:${VERSION_TAG}" \
    --push \
    .

echo ""
echo -e "${GREEN}✓ Runtime image built and pushed successfully${NC}"
echo ""

# ============================================================================
# Step 7: Cleanup and verify
# ============================================================================
echo -e "${BLUE}=== Step 7: Cleanup and verification ===${NC}"

# Cleanup build artifacts
rm -rf "$TEMPORAL_DSQL_PATH/docker/build"
cd "$TEMPORAL_DSQL_PATH"
rm -f temporal-server temporal-cassandra-tool temporal-sql-tool temporal-elasticsearch-tool temporal-dsql-tool tdbg

# Verify the images were pushed
echo "Verifying server image in ECR..."
aws ecr describe-images \
    --repository-name "$ECR_REPO_NAME" \
    --image-ids imageTag=latest \
    --region "$AWS_REGION" \
    --query 'imageDetails[0].{digest:imageDigest,pushedAt:imagePushedAt,size:imageSizeInBytes}' \
    --output table || echo -e "${YELLOW}Warning: Could not verify server image${NC}"

echo ""
echo "Verifying admin-tools image in ECR..."
aws ecr describe-images \
    --repository-name "temporal-dsql-admin-tools" \
    --image-ids imageTag=latest \
    --region "$AWS_REGION" \
    --query 'imageDetails[0].{digest:imageDigest,pushedAt:imagePushedAt,size:imageSizeInBytes}' \
    --output table || echo -e "${YELLOW}Warning: Could not verify admin-tools image${NC}"

echo ""
echo "Verifying runtime image in ECR..."
aws ecr describe-images \
    --repository-name "$RUNTIME_REPO_NAME" \
    --image-ids imageTag=latest \
    --region "$AWS_REGION" \
    --query 'imageDetails[0].{digest:imageDigest,pushedAt:imagePushedAt,size:imageSizeInBytes}' \
    --output table || echo -e "${YELLOW}Warning: Could not verify runtime image${NC}"

echo ""
echo -e "${GREEN}=== Build Complete ===${NC}"
echo ""
echo "Server Image (base):"
echo "  ${ECR_REPO_URL}:latest"
echo ""
echo "Admin-Tools Image:"
echo "  ${ADMIN_TOOLS_REPO_URL}:latest"
echo ""
echo "Runtime Image (for ECS services):"
echo "  ${RUNTIME_REPO_URL}:latest"
echo ""
echo "Use these in your terraform.tfvars:"
echo "  temporal_image             = \"${RUNTIME_REPO_URL}:latest\""
echo "  temporal_admin_tools_image = \"${ADMIN_TOOLS_REPO_URL}:latest\""
echo ""
echo -e "${YELLOW}Note: The runtime image contains:${NC}"
echo "  - temporal-server (ARM64)"
echo "  - Config template rendering (envsubst)"
echo "  - DSQL + OpenSearch persistence config"
echo "  - Dynamic config for DSQL optimization"
echo ""
echo -e "${YELLOW}The admin-tools image contains:${NC}"
echo "  - temporal (CLI)"
echo "  - temporal-sql-tool"
echo "  - temporal-elasticsearch-tool"
echo "  - temporal-dsql-tool"
echo "  - tdbg"
echo "  - Schema files"
echo ""
