#!/bin/bash

# Build script for Hyperlane package Docker images
# Uses specific versions instead of latest

set -e

echo "Building Hyperlane Docker images with specific versions..."

# Version configurations
CLI_VERSION="16.2.0"
CONFIG_GEN_VERSION="1.0.0"
IMAGE_TAG="v1.0.25"
USER_NAME="fravlaca"

# Build hyperlane-cli image
echo "Building hyperlane-cli:${IMAGE_TAG}..."
docker build \
  -t ${USER_NAME}/hyperlane-cli:${IMAGE_TAG} \
  -t ${USER_NAME}/hyperlane-cli:latest \
  --build-arg CLI_VERSION=${CLI_VERSION} \
  -f src/deployments/hyperlane-deployer/Dockerfile \
  src/deployments/hyperlane-deployer/

# Build agent-config-gen image  
echo "Building agent-config-gen:${IMAGE_TAG}..."
docker build \
  -t ${USER_NAME}/agent-config-gen:${IMAGE_TAG} \
  -t ${USER_NAME}/agent-config-gen:latest \
  -f src/deployments/config-generator/Dockerfile \
  src/deployments/config-generator/

echo "Docker images built successfully!"
echo ""
echo "Images created:"
echo "  - ${USER_NAME}/hyperlane-cli:${IMAGE_TAG} (also tagged as latest)"
echo "  - ${USER_NAME}/agent-config-gen:${IMAGE_TAG} (also tagged as latest)"
echo ""
echo "To use specific versions in deployment, update your config to use:"
echo "  cli_version: ${IMAGE_TAG}"
echo "  Or keep using 'latest' which points to ${IMAGE_TAG}"