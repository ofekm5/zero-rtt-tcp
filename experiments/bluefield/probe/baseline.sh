#!/usr/bin/env bash
# Captures the pre-mutation DPU baseline for the eswitch-offload-probe spike.
#
# Records: ovs-vsctl show output, pf0hpf bridge membership, ARM hugepage
# count, DOCA/DPDK versions, and adapter firmware version. Aborts without
# mutating the DPU if any value cannot be read, so restore.sh always has a
# trustworthy reference to diff against.
#
# Usage: ./baseline.sh [output-file]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hosts.sh
source "${SCRIPT_DIR}/lib/hosts.sh"

BASELINE_FILE="${1:-${SCRIPT_DIR}/../reports/baseline.txt}"

fail() {
    echo "ERROR: $1 — aborting without mutating the DPU" >&2
    exit 1
}

require_nonempty() {
    local label="$1" value="$2"
    if [[ -z "$value" ]]; then
        fail "could not read ${label}"
    fi
}

mkdir -p "$(dirname "$BASELINE_FILE")"

OVS_SHOW="$(dpu_run 'ovs-vsctl show' 2>/dev/null)" || fail "ovs-vsctl show"
require_nonempty "ovs-vsctl show output" "$OVS_SHOW"

PF0HPF_MEMBERSHIP="$(dpu_run 'ovs-vsctl port-to-br pf0hpf' 2>/dev/null)" || fail "pf0hpf bridge membership"
require_nonempty "pf0hpf bridge membership" "$PF0HPF_MEMBERSHIP"

HUGEPAGE_COUNT="$(dpu_run 'grep -c HugePages_Total /proc/meminfo && grep HugePages_Total /proc/meminfo' 2>/dev/null | tail -n1)" || fail "ARM hugepage count"
require_nonempty "ARM hugepage count" "$HUGEPAGE_COUNT"

DOCA_VERSION="$(dpu_run 'cat /opt/mellanox/doca/VERSION 2>/dev/null || doca_version 2>/dev/null')" || fail "DOCA version"
require_nonempty "DOCA version" "$DOCA_VERSION"

DPDK_VERSION="$(dpu_run 'cat /opt/mellanox/dpdk/VERSION 2>/dev/null || pkg-config --modversion libdpdk 2>/dev/null')" || fail "DPDK version"
require_nonempty "DPDK version" "$DPDK_VERSION"

FW_VERSION="$(dpu_run 'mlxfwmanager --query 2>/dev/null | grep -i "FW " || flint -d /dev/mst/* q 2>/dev/null | grep -i "FW Version"')" || fail "adapter firmware version"
require_nonempty "adapter firmware version" "$FW_VERSION"

{
    echo "# eswitch-offload-probe baseline"
    echo "# captured: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "## ovs-vsctl show"
    echo "$OVS_SHOW"
    echo
    echo "## pf0hpf bridge membership"
    echo "$PF0HPF_MEMBERSHIP"
    echo
    echo "## ARM hugepage count"
    echo "$HUGEPAGE_COUNT"
    echo
    echo "## DOCA version"
    echo "$DOCA_VERSION"
    echo
    echo "## DPDK version"
    echo "$DPDK_VERSION"
    echo
    echo "## Adapter firmware version"
    echo "$FW_VERSION"
} > "$BASELINE_FILE"

echo "Baseline captured to ${BASELINE_FILE}"
