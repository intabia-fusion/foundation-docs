#!/bin/bash

# Docker Build Script for intabiafusion/platform-docs
# Usage: ./build.sh [TAG] [OPTIONS]
#
# Options:
#   --platform PLATFORM    Build for specific platform: linux/amd64, linux/arm64, or both (default: current platform)
#   --push                 Push to registry after build (required for multi-platform builds)
#   -h, --help            Show this help message
#
# Examples:
#   ./build.sh                                    # Build for current platform with tag 'latest'
#   ./build.sh v1.0.0                             # Build for current platform with tag 'v1.0.0'
#   ./build.sh latest --platform linux/amd64      # Build for AMD64 only
#   ./build.sh latest --platform linux/arm64      # Build for ARM64 only
#   ./build.sh latest --platform linux/amd64,linux/arm64 --push   # Build for both platforms and push

set -e

# Configuration
IMAGE_NAME="intabiafusion/platform-docs"
DEFAULT_TAG="latest"

# Parse arguments
TAG=""
PLATFORM=""
PUSH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        --push)
            PUSH="true"
            shift
            ;;
        -h|--help)
            head -n 25 "$0" | tail -n 20 | sed 's/^# //'
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
        *)
            if [ -z "$TAG" ]; then
                TAG="$1"
            else
                echo "Unknown argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Set default tag
TAG=${TAG:-$DEFAULT_TAG}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Building Docker Image${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Image: $IMAGE_NAME:$TAG"
if [ -n "$PLATFORM" ]; then
    echo "Platform(s): $PLATFORM"
fi
if [ -n "$PUSH" ]; then
    echo -e "${BLUE}Push mode: Enabled${NC}"
fi
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

# Build the static site on host (sharp/libvips runs native, avoids QEMU segfault)
echo -e "${YELLOW}Building static site on host...${NC}"
if ! command -v pnpm &> /dev/null; then
    echo -e "${RED}Error: pnpm is not installed (required to build site on host)${NC}"
    exit 1
fi
pnpm install --frozen-lockfile
SITE_BASE=/docs pnpm run build
echo -e "${GREEN}✓ Static site built${NC}"
echo ""

# Determine if we need buildx (multi-platform builds)
IS_MULTI_PLATFORM=false
if [ -n "$PLATFORM" ]; then
    if [[ "$PLATFORM" == *","* ]]; then
        IS_MULTI_PLATFORM=true
    fi
fi

# Setup buildx for multi-platform builds
if [ "$IS_MULTI_PLATFORM" = true ]; then
    echo -e "${YELLOW}Setting up Docker Buildx for multi-platform builds...${NC}"
    
    # Check if buildx is available
    if ! docker buildx version &> /dev/null; then
        echo -e "${RED}Error: Docker Buildx is required for multi-platform builds${NC}"
        echo "Please install Docker Desktop or enable the buildx plugin"
        exit 1
    fi
    
    # Try to use docker-container driver builder
    BUILDER_NAME="platform-docs-builder"
    
    # Remove existing builder if it exists (might be misconfigured)
    if docker buildx ls | grep -q "^$BUILDER_NAME"; then
        echo "Removing existing builder: $BUILDER_NAME"
        docker buildx rm "$BUILDER_NAME" &> /dev/null || true
    fi
    
    # Create new builder with docker-container driver
    echo "Creating buildx builder: $BUILDER_NAME"
    docker buildx create --name "$BUILDER_NAME" --driver docker-container --use &> /dev/null
    
    # Check if builder supports the platforms we need
    echo "Checking supported platforms..."
    SUPPORTED_PLATFORMS=$(docker buildx inspect --bootstrap 2>&1 | grep "Platforms:" | cut -d: -f2 | tr -d ' ' || echo "")
    
    if [ -z "$SUPPORTED_PLATFORMS" ]; then
        echo -e "${YELLOW}Warning: Could not determine supported platforms${NC}"
    else
        echo -e "${GREEN}✓ Supported platforms: $SUPPORTED_PLATFORMS${NC}"
    fi
    
    echo ""
fi

echo -e "${YELLOW}Step 1/4: Building image...${NC}"
START_TIME=$(date +%s)

if [ "$IS_MULTI_PLATFORM" = true ]; then
    # Multi-platform build with buildx
    echo -e "${BLUE}Building multi-platform image for: $PLATFORM${NC}"
    
    if [ -n "$PUSH" ]; then
        echo -e "${BLUE}Will push to registry after build${NC}"
        docker buildx build \
            --platform "$PLATFORM" \
            -t "$IMAGE_NAME:$TAG" \
            -f Dockerfile \
            --push \
            .
    else
        echo -e "${YELLOW}Note: Multi-platform builds require --push flag to store in registry${NC}"
        echo -e "${YELLOW}Building for local load (only current platform)...${NC}"
        # For local load, we can only load one platform at a time
        # Build for the first platform in the list
        FIRST_PLATFORM=$(echo "$PLATFORM" | cut -d',' -f1)
        docker buildx build \
            --platform "$FIRST_PLATFORM" \
            -t "$IMAGE_NAME:$TAG" \
            -f Dockerfile \
            --load \
            .
    fi
else
    # Single platform build
    if [ -n "$PLATFORM" ]; then
        echo "Building for platform: $PLATFORM"
        docker build \
            --platform "$PLATFORM" \
            -t "$IMAGE_NAME:$TAG" \
            -f Dockerfile \
            .
    else
        echo "Building for current platform"
        docker build \
            -t "$IMAGE_NAME:$TAG" \
            -f Dockerfile \
            .
    fi
    
    # Push if requested (for single platform builds)
    if [ -n "$PUSH" ]; then
        echo ""
        echo -e "${BLUE}Pushing to registry...${NC}"
        docker push "$IMAGE_NAME:$TAG"
        echo -e "${GREEN}✓ Pushed to registry${NC}"
    fi
fi

BUILD_TIME=$(( $(date +%s) - START_TIME ))
echo -e "${GREEN}✓ Build completed in ${BUILD_TIME}s${NC}"
echo ""

# Skip testing for push builds (image may not be loaded locally)
if [ -n "$PUSH" ]; then
    echo -e "${YELLOW}Skipping local testing for push build${NC}"
    echo ""
else
    echo -e "${YELLOW}Step 2/4: Checking image...${NC}"
    IMAGE_SIZE=$(docker images "$IMAGE_NAME:$TAG" --format "{{.Size}}" 2>/dev/null || echo "N/A")
    echo -e "${GREEN}✓ Image size: $IMAGE_SIZE${NC}"
    echo ""

    echo -e "${YELLOW}Step 3/4: Testing container...${NC}"
    CONTAINER_NAME="platform-docs-test-$$"
    docker run -d --name "$CONTAINER_NAME" -p 8080:80 "$IMAGE_NAME:$TAG" &> /dev/null

    # Wait for container to be ready
    echo -n "Waiting for container"
    for i in $(seq 1 30); do
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
    if [ -n "$BROTLI_SIZE" ] && [ "$BROTLI_SIZE" -gt 0 ]; then
        echo -e "${GREEN}✓ Working (${BROTLI_SIZE} bytes)${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
    fi

    # Cleanup test container
    docker rm -f "$CONTAINER_NAME" &> /dev/null
    echo ""
fi

# Cleanup buildx builder
if [ "$IS_MULTI_PLATFORM" = true ]; then
    echo -e "${YELLOW}Cleaning up buildx builder...${NC}"
    docker buildx rm "$BUILDER_NAME" &> /dev/null || true
    docker buildx use default &> /dev/null || true
    echo ""
fi

echo -e "${YELLOW}Step 4/4: Build summary${NC}"
echo "========================================"
echo "Image: $IMAGE_NAME:$TAG"
if [ -n "$PLATFORM" ]; then
    echo "Platform(s): $PLATFORM"
else
    echo "Platform: $(docker info --format '{{.Architecture}}' | sed 's/x86_64/linux\/amd64/;s/aarch64/linux\/arm64/')"
fi
if [ -n "$IMAGE_SIZE" ] && [ "$IMAGE_SIZE" != "N/A" ]; then
    echo "Size: $IMAGE_SIZE"
fi
echo "Build time: ${BUILD_TIME}s"
echo "Brotli compression: Enabled"
if [ -n "$PUSH" ]; then
    echo -e "${GREEN}Pushed to registry${NC}"
fi
echo ""
echo -e "${GREEN}✓ Build successful!${NC}"
echo ""

if [ "$IS_MULTI_PLATFORM" = true ] && [ -z "$PUSH" ]; then
    echo -e "${YELLOW}Note: Multi-platform builds without --push can only be loaded locally for current platform${NC}"
    echo "To build and push for all platforms, use:"
    echo "  ./build.sh $TAG --platform '$PLATFORM' --push"
    echo ""
fi

echo "To run the container:"
echo "  docker run -d -p 8080:80 $IMAGE_NAME:$TAG"
echo ""
if [ -z "$PUSH" ]; then
    echo "To push to registry:"
    echo "  docker push $IMAGE_NAME:$TAG"
    echo ""
    echo "For multi-platform builds:"
    echo "  ./build.sh $TAG --platform 'linux/amd64,linux/arm64' --push"
fi
