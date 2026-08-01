#!/usr/bin/env bash
# Builds the eswitch-offload-probe DOCA Flow program inside the DOCA devel
# container (which ships meson/ninja), saves it to a tarball, and
# transfers + loads it on the DPU — following the existing
# infra/bluefield/deployment/Dockerfile and compress_doca_image.sh pattern.
#
# Runs entirely on the developer's machine (which has DNS to pull the base
# image); performs no registry pull or DNS resolution from the DPU itself.
#
# Usage: ./build_image.sh [image-tag]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hosts.sh
source "${SCRIPT_DIR}/lib/hosts.sh"

IMAGE_TAG="${1:-eswitch-probe:latest}"
DT="$(date -u +%Y%m%dT%H%M%SZ)"
TAR_NAME="eswitch_probe_${DT}.tar"
DOCKERFILE_DIR="${SCRIPT_DIR}/docaprobe"

fail() {
    echo "ERROR: $1" >&2
    exit 1
}

echo "Building ${IMAGE_TAG} from ${DOCKERFILE_DIR} (linux/arm64)..."
docker build \
    --platform=linux/arm64 \
    -t "${IMAGE_TAG}" \
    -f "${DOCKERFILE_DIR}/Dockerfile" \
    "${DOCKERFILE_DIR}" || fail "docker build failed"

echo "Saving ${IMAGE_TAG} to ${TAR_NAME}..."
docker save "${IMAGE_TAG}" -o "${TAR_NAME}" || fail "docker save failed"
chmod 644 "${TAR_NAME}" || fail "failed to set permissions on tarball"

echo "Transferring ${TAR_NAME} to DPU (${DPU_HOST})..."
scp -i "${PROBE_SSH_KEY}" ${PROBE_SSH_OPTS} "${TAR_NAME}" "${DPU_USER}@${DPU_HOST}:/tmp/${TAR_NAME}" \
    || fail "scp to DPU failed"

echo "Loading ${TAR_NAME} on the DPU (no registry pull, no DNS resolution on-device)..."
dpu_run "docker load -i /tmp/${TAR_NAME}" || fail "docker load on DPU failed"

echo "Image ${IMAGE_TAG} built, transferred and loaded on the DPU."
