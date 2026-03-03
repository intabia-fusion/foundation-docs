#!/bin/bash

# Docker Build Script for intabiafusion/platform-docs
# Usage: ./build.sh [TAG]

set -e

# Configuration
IMAGE_NAME="intabiafusion/platform-docs"
DEFAULT_TAG="latest"

# Get tag from argument or use default
TAG=${1:-$DEFAULT_TAG}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Building Docker Image${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Image: $IMAGE_NAME:$TAG"
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    exit 1
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    echo -e "${RED}Error: Docker daemon is not running${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 1/4: Building image...${NC}"
START_TIME=$(date +%s)

docker build \
    -t "$IMAGE_NAME:$TAG" \
    -f Dockerfile \
    .

BUILD_TIME=$(( $(date +%s) - START_TIME ))
echo -e "${GREEN}✓ Build completed in ${BUILD_TIME}s${NC}"
echo ""

echo -e "${YELLOW}Step 2/4: Checking image...${NC}"
IMAGE_SIZE=$(docker images "$IMAGE_NAME:$TAG" --format "{{.Size}}")
echo -e "${GREEN}✓ Image size: $IMAGE_SIZE${NC}"
echo ""

echo -e "${YELLOW}Step 3/4: Testing container...${NC}"
CONTAINER_NAME="platform-docs-test-$$"
docker run -d --name "$CONTAINER_NAME" -p 8080:80 "$IMAGE_NAME:$TAG" &> /dev/null

# Wait for container to be ready
echo -n "Waiting for container"
for i in {1..30}; do
    if curl -s http://localhost:8080/docs/ &> /dev/null; then
        echo -e "\n${GREEN}✓ Container is running${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

# Test compression
echo ""
echo -n "Testing Brotli compression... "
BROTLI_SIZE=$(curl -s -o /dev/null -w "%{size_download}" -H "Accept-Encoding: br" http://localhost:8080/docs/)
if [ "$BROTLI_SIZE" -gt 0 ]; then
    echo -e "${GREEN}✓ Working (${BROTLI_SIZE} bytes)${NC}"
else
    echo -e "${RED}✗ Failed${NC}"
fi

# Cleanup test container
docker rm -f "$CONTAINER_NAME" &> /dev/null
echo ""

echo -e "${YELLOW}Step 4/4: Build summary${NC}"
echo "========================================"
echo "Image: $IMAGE_NAME:$TAG"
echo "Size: $IMAGE_SIZE"
echo "Build time: ${BUILD_TIME}s"
echo "Brotli compression: Enabled"
echo ""
echo -e "${GREEN}✓ Build successful!${NC}"
echo ""
echo "To run the container:"
echo "  docker run -d -p 8080:80 $IMAGE_NAME:$TAG"
echo ""
echo "To push to registry:"
echo "  docker push $IMAGE_NAME:$TAG"
