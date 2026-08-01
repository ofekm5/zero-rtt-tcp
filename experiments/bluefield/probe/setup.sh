#!/usr/bin/env bash
# Allocates hugepages on the DPU ARM, detaches pf0hpf from ovsbr1 so the
# probe can own it as a DPDK data-plane port, and brings ens16f0np0 up on
# the x86 host VM. Never touches oob_net0, over which DPU management runs
# (design.md fact 3: management is independent of the data path).
#
# Usage: ./setup.sh [image-tag]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hosts.sh
source "${SCRIPT_DIR}/lib/hosts.sh"

IMAGE_TAG="${1:-eswitch-probe:latest}"
HUGEPAGE_COUNT="${PROBE_HUGEPAGES:-1024}"

fail() {
    echo "ERROR: $1" >&2
    exit 1
}

echo "Allocating ${HUGEPAGE_COUNT} hugepages on the DPU ARM..."
dpu_run "echo ${HUGEPAGE_COUNT} | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages" \
    || fail "hugepage allocation failed"

echo "Detaching pf0hpf from ovsbr1 (data-plane port for the probe)..."
dpu_run "sudo ovs-vsctl del-port ovsbr1 pf0hpf" \
    || fail "failed to detach pf0hpf from ovsbr1"

echo "Bringing ens16f0np0 up on the x86 host VM..."
vm_run "sudo ip link set ens16f0np0 up" \
    || fail "failed to bring ens16f0np0 up"

echo "Starting the probe container (image ${IMAGE_TAG}) to initialise pf0hpf..."
dpu_run "docker run --rm --privileged --network host ${IMAGE_TAG} --help" \
    || fail "probe container failed to start"

echo "Setup complete: hugepages allocated, pf0hpf detached from ovsbr1, ens16f0np0 up."
