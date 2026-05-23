#!/bin/bash
# Usage: ./save_doca.sh [IMAGE_NAME]
# Example: ./save_doca.sh nvcr.io/nvidia/doca/doca:3.0.0-devel

set -euo pipefail

# Args & defaults
IMAGE_NAME="${1:-nvcr.io/nvidia/doca/doca:2.9.3-devel}"
DT="$(date -u +%Y%m%dT%H%M%SZ)"
TAR_NAME="doca_${DT}.tar"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

fail() {
  echo -e "${RED}[✗] $1${NC}"
  exit 1
}

log() {
  echo -e "${GREEN}[*] $1${NC}"
}

log "Using image: ${IMAGE_NAME}"
log "Tarball will be: ${TAR_NAME}"

# Pull and save
log "Pulling DOCA image..."
sudo docker pull --platform=linux/arm64 "$IMAGE_NAME" || fail "Failed to pull DOCA image."

log "Saving image to '${TAR_NAME}'..."
sudo docker save "$IMAGE_NAME" -o "$TAR_NAME" || fail "Failed to save DOCA image."

# Permissions for transfer
sudo chmod 644 "$TAR_NAME" || fail "Failed to set permissions on tarball."

log "Vanilla DOCA image tarball is ready: ${TAR_NAME}"
