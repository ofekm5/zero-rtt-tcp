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
CONTAINER_NAME="${PROBE_CONTAINER_NAME:-eswitch-probe}"
FAILURES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --baseline-file) BASELINE_FILE="$2"; shift 2 ;;
        --image-tag) IMAGE_TAG="$2"; shift 2 ;;
        --container-name) CONTAINER_NAME="$2"; shift 2 ;;
        *) echo "ERROR: unrecognised argument: $1" >&2; exit 1 ;;
    esac
done

note_failure() {
    echo "ERROR: $1" >&2
    FAILURES=$((FAILURES + 1))
}

# Reads the single line under a "## <heading>" section of the baseline file.
baseline_section() {
    [[ -f "${BASELINE_FILE}" ]] || return 1
    awk -v want="## $1" '$0==want{getline; print; exit}' "${BASELINE_FILE}"
}

# Every step below is conditional on the DPU actually being in the mutated
# state. run_probe.sh's EXIT trap fires on early aborts too — including
# before setup.sh ran — and an unconditional restore would then "fail" at
# re-adding a port that was never removed, reporting RESTORE INCOMPLETE for
# a DPU that was never touched.

# The probe now runs detached and is deliberately not --rm (run_probe.sh
# reads its counters out of `docker logs` after it exits), so the stopped
# container is state this script owns. It must go before the image can be
# removed, and it holds pf0hpf if the run was aborted mid-hold.
echo "Removing the probe container (${CONTAINER_NAME})..."
if dpu_run "docker container inspect ${CONTAINER_NAME}" >/dev/null 2>&1; then
    dpu_run "docker rm -f ${CONTAINER_NAME}" >/dev/null 2>&1 \
        || note_failure "failed to remove the probe container ${CONTAINER_NAME}"
else
    echo "No probe container present; nothing to remove."
fi

echo "Re-attaching pf0hpf to ovsbr1..."
if dpu_run "ovs-vsctl port-to-br pf0hpf" >/dev/null 2>&1; then
    echo "pf0hpf is already on a bridge; nothing to re-attach."
else
    dpu_run "sudo ovs-vsctl add-port ovsbr1 pf0hpf" || note_failure "failed to re-attach pf0hpf to ovsbr1"
fi

# Restore the recorded hugepage count rather than hardcoding zero — the DPU
# is shared, and another user's allocation must survive this spike.
BASELINE_HUGEPAGES="$(baseline_section 'ARM hugepage count' | grep -oE '[0-9]+' | tail -n1)"
if [[ -z "${BASELINE_HUGEPAGES}" ]]; then
    note_failure "could not read the baseline hugepage count; leaving hugepages untouched"
else
    echo "Restoring hugepages to the recorded baseline (${BASELINE_HUGEPAGES})..."
    dpu_run "echo ${BASELINE_HUGEPAGES} | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages" \
        || note_failure "failed to restore hugepages"
fi

echo "Removing the loaded probe image (${IMAGE_TAG})..."
if dpu_run "docker image inspect ${IMAGE_TAG}" >/dev/null 2>&1; then
    dpu_run "docker rmi ${IMAGE_TAG}" || note_failure "failed to remove probe image"
else
    echo "Probe image is not loaded; nothing to remove."
fi

# Put ens16f0np0 back where baseline.sh found it, rather than assuming down.
BASELINE_IFACE_STATE="$(baseline_section 'ens16f0np0 admin state')"
if [[ -z "${BASELINE_IFACE_STATE}" ]]; then
    note_failure "could not read ens16f0np0's recorded admin state; leaving the interface untouched"
elif [[ "${BASELINE_IFACE_STATE}" == "UP" ]]; then
    echo "ens16f0np0 was recorded UP; leaving it up."
else
    echo "Returning ens16f0np0 to its recorded ${BASELINE_IFACE_STATE} state on the x86 VM..."
    vm_run "sudo ip link set ens16f0np0 down" || note_failure "failed to bring ens16f0np0 down"
fi

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
