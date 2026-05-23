#!/bin/bash
# Build Docker image for wire-example DPDK application
# Usage: ./build_wire_image.sh [IMAGE_TAG] [--save]
# Example: ./build_wire_image.sh wire-app:latest --save

set -euo pipefail

# Args & defaults
IMAGE_TAG="${1:-wire-app:latest}"
SAVE_IMAGE="${2:-}"
DT="$(date -u +%Y%m%dT%H%M%SZ)"
TAR_NAME="wire_app_${DT}.tar"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

fail() {
  echo -e "${RED}[✗] $1${NC}"
  exit 1
}

log() {
  echo -e "${GREEN}[*] $1${NC}"
}

warn() {
  echo -e "${YELLOW}[!] $1${NC}"
}

# Validate we're in the right directory
if [[ ! -f "$SCRIPT_DIR/wire.c" ]]; then
  fail "wire.c not found in $SCRIPT_DIR. Run this script from apps/wire-example/"
fi

if [[ ! -f "$SCRIPT_DIR/Dockerfile" ]]; then
  fail "Dockerfile not found in $SCRIPT_DIR. Please create Dockerfile first."
fi

log "Building wire-example Docker image..."
log "Image tag: ${IMAGE_TAG}"
log "Build context: ${SCRIPT_DIR}"

# Build the image for ARM64 (Bluefield architecture)
log "Starting Docker build (this may take a few minutes)..."
sudo docker build \
  --platform=linux/arm64 \
  -t "$IMAGE_TAG" \
  -f "$SCRIPT_DIR/Dockerfile" \
  "$SCRIPT_DIR" || fail "Docker build failed."

log "✓ Image built successfully: ${IMAGE_TAG}"

# Show image details
IMAGE_SIZE=$(sudo docker images "$IMAGE_TAG" --format "{{.Size}}" | head -n1)
log "Image size: ${IMAGE_SIZE}"

# Optionally save to tarball
if [[ "$SAVE_IMAGE" == "--save" ]]; then
  log "Saving image to '${TAR_NAME}'..."
  sudo docker save "$IMAGE_TAG" -o "$TAR_NAME" || fail "Failed to save image."

  # Set permissions for transfer
  sudo chmod 644 "$TAR_NAME" || fail "Failed to set permissions on tarball."

  log "✓ Image tarball ready: ${TAR_NAME}"
  log "To load on Bluefield DPU: sudo docker load -i ${TAR_NAME}"
fi

# Print usage instructions
echo ""
log "=== Build Complete ==="
echo ""
echo "To run the image:"
echo "  1. List ports:"
echo "     sudo docker run --rm --privileged --network host \\"
echo "       -v /dev/hugepages:/dev/hugepages \\"
echo "       ${IMAGE_TAG}"
echo ""
echo "  2. Start wire between ports (example: ports 2 and 3):"
echo "     sudo docker run --rm --privileged --network host \\"
echo "       -v /dev/hugepages:/dev/hugepages \\"
echo "       ${IMAGE_TAG} -l 0-2 -- 2 3"
echo ""
if [[ "$SAVE_IMAGE" == "--save" ]]; then
  echo "Transfer ${TAR_NAME} to your Bluefield DPU and load with:"
  echo "  sudo docker load -i ${TAR_NAME}"
  echo ""
fi
