#!/usr/bin/env bash
# Restores the DPU to its pre-spike state: re-attaches pf0hpf to ovsbr1,
# frees the hugepages, removes the loaded probe image, returns
# ens16f0np0 to its recorded state on the x86 VM, then diffs the
# resulting `ovs-vsctl show` against the recorded baseline and exits
# non-zero when they differ — restoration is a success criterion (SC5,
# design.md D5), not a trailing cleanup step. Runs for every verdict,
# including failure paths.
#
# Usage: ./restore.sh [--baseline-file <path>] [--image-tag <tag>]
set -uo pipefail
# Deliberately not `set -e`: every restore step must be attempted even if
# an earlier one fails, so failures are collected and reported together
# rather than aborting the restore partway through.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hosts.sh
source "${SCRIPT_DIR}/lib/hosts.sh"

BASELINE_FILE="${SCRIPT_DIR}/../reports/baseline.txt"
IMAGE_TAG="eswitch-probe:latest"
FAILURES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --baseline-file) BASELINE_FILE="$2"; shift 2 ;;
        --image-tag) IMAGE_TAG="$2"; shift 2 ;;
        *) echo "ERROR: unrecognised argument: $1" >&2; exit 1 ;;
    esac
done

note_failure() {
    echo "ERROR: $1" >&2
    FAILURES=$((FAILURES + 1))
}

echo "Re-attaching pf0hpf to ovsbr1..."
dpu_run "sudo ovs-vsctl add-port ovsbr1 pf0hpf" || note_failure "failed to re-attach pf0hpf to ovsbr1"

echo "Freeing hugepages..."
dpu_run "echo 0 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages" || note_failure "failed to free hugepages"

echo "Removing the loaded probe image (${IMAGE_TAG})..."
dpu_run "docker rmi ${IMAGE_TAG}" || note_failure "failed to remove probe image"

echo "Returning ens16f0np0 to its prior (down) state on the x86 VM..."
vm_run "sudo ip link set ens16f0np0 down" || note_failure "failed to bring ens16f0np0 down"

if [[ ! -f "${BASELINE_FILE}" ]]; then
    note_failure "no baseline file at ${BASELINE_FILE}; cannot verify restoration"
else
    CURRENT_OVS="$(dpu_run 'ovs-vsctl show' 2>/dev/null)"
    RECORDED_OVS="$(awk '/^## ovs-vsctl show$/{flag=1;next}/^## /{flag=0}flag' "${BASELINE_FILE}")"
    if ! diff <(echo "${CURRENT_OVS}") <(echo "${RECORDED_OVS}") >/dev/null; then
        note_failure "post-restore ovs-vsctl show does not match the recorded baseline"
    else
        echo "ovs-vsctl show matches the recorded pre-spike baseline."
    fi
fi

if [[ "${FAILURES}" -gt 0 ]]; then
    echo "RESTORE INCOMPLETE: ${FAILURES} step(s) failed — see errors above" >&2
    exit 1
fi

echo "Restore complete: DPU matches its pre-spike baseline."
exit 0
