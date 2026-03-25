#!/bin/bash
# Build and run DPDK tests inside a Linux container (no hardware required).
#
# Usage (from repo root or clientnic/dpdk):
#   bash clientnic/dpdk/tests/run_tests_docker.sh
#
# Requires: Docker

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DPDK_DIR="$(dirname "$SCRIPT_DIR")"
IMAGE="clientnic-dpdk-test:latest"

echo "=== Building Docker image ==="
docker build -t "$IMAGE" -f "$SCRIPT_DIR/Dockerfile" "$DPDK_DIR"

echo ""
echo "=== Running DPDK tests ==="
# --privileged: EAL needs /sys/bus access
# --no-huge via test script fallback (no hugepages in container)
docker run --rm --privileged "$IMAGE"
