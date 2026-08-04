#!/usr/bin/env bash
# End-to-end orchestrator for the eswitch-offload-probe spike: runs
# baseline capture, image build and transport, setup, rule installation,
# traffic generation/capture, the conditional rte_flow cross-check, and
# verdict evaluation in sequence. Invokes restore.sh on every exit path,
# including early failure, via a trap — the DPU must never be left
# mutated by an aborted run (design.md D5, tasks.md task 11).
#
# Usage: ./run_probe.sh --src-ip <ip> --dst-ip <ip> --src-port <port> \
#          --dst-port <port> --seq <uint32> --delta <int32> \
#          [--direction sub|add] [--port-id <id>] [--image-tag <tag>]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hosts.sh
source "${SCRIPT_DIR}/lib/hosts.sh"
REPORTS_DIR="${SCRIPT_DIR}/../reports"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_REPORTS_DIR="${REPORTS_DIR}/${RUN_ID}"

SRC_IP="" DST_IP="" SRC_PORT="" DST_PORT="" SEQ="" DELTA=""
DIRECTION="sub"
PORT_ID="0"
IMAGE_TAG="eswitch-probe:latest"
# The rule's lifetime. Must cover step 5's capture window plus SSH latency;
# traffic.sh defaults to a 5s capture.
HOLD_SECS="${PROBE_HOLD_SECS:-30}"
CONTAINER_NAME="${PROBE_CONTAINER_NAME:-eswitch-probe}"
# How long to wait for the detached probe to finish its hold window.
COUNTER_WAIT_SECS="${PROBE_COUNTER_WAIT_SECS:-90}"

fail_usage() {
    echo "ERROR: $1" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --src-ip) SRC_IP="$2"; shift 2 ;;
        --dst-ip) DST_IP="$2"; shift 2 ;;
        --src-port) SRC_PORT="$2"; shift 2 ;;
        --dst-port) DST_PORT="$2"; shift 2 ;;
        --seq) SEQ="$2"; shift 2 ;;
        --delta) DELTA="$2"; shift 2 ;;
        --direction) DIRECTION="$2"; shift 2 ;;
        --port-id) PORT_ID="$2"; shift 2 ;;
        --image-tag) IMAGE_TAG="$2"; shift 2 ;;
        *) fail_usage "unrecognised argument: $1" ;;
    esac
done

[[ -n "${SRC_IP}" && -n "${DST_IP}" && -n "${SRC_PORT}" && -n "${DST_PORT}" && -n "${SEQ}" && -n "${DELTA}" ]] \
    || fail_usage "missing required argument (need --src-ip --dst-ip --src-port --dst-port --seq --delta)"

mkdir -p "${RUN_REPORTS_DIR}"

# Waits for the detached probe to finish its hold window, then emits the
# COUNTER / SW_QUEUE_RX_COUNT lines it printed on the way out. These are the
# post-traffic readings — the numbers verdict.sh evaluates for SC3.
collect_probe_counters() {
    echo "Waiting up to ${COUNTER_WAIT_SECS}s for the probe to close its hold window..."
    dpu_run "timeout ${COUNTER_WAIT_SECS} docker wait ${CONTAINER_NAME}" >/dev/null 2>&1 \
        || echo "WARNING: probe container did not exit within ${COUNTER_WAIT_SECS}s; reading logs as-is" >&2
    dpu_run "docker logs ${CONTAINER_NAME} 2>&1" \
        || echo "WARNING: could not read probe container logs" >&2
}

RESTORED=0
restore_once() {
    if [[ "${RESTORED}" -eq 1 ]]; then
        return 0
    fi
    RESTORED=1
    echo "=== Restoring DPU (runs on every exit path) ==="
    "${SCRIPT_DIR}/restore.sh" --baseline-file "${REPORTS_DIR}/baseline.txt" --image-tag "${IMAGE_TAG}" \
        --container-name "${CONTAINER_NAME}" \
        > "${RUN_REPORTS_DIR}/restore.log" 2>&1
    RESTORE_RC=$?
    cat "${RUN_REPORTS_DIR}/restore.log"
    if [[ "${RESTORE_RC}" -ne 0 ]]; then
        echo "WARNING: restore.sh reported a non-zero exit — inspect ${RUN_REPORTS_DIR}/restore.log" >&2
    fi
}
# EXIT covers normal completion and early failure alike. An ERR trap would
# fire on every failing command, including ones this script handles itself,
# so restore would run mid-flight; EXIT runs exactly once, at the end.
trap restore_once EXIT

echo "=== Step 1: baseline ==="
"${SCRIPT_DIR}/baseline.sh" "${REPORTS_DIR}/baseline.txt" | tee "${RUN_REPORTS_DIR}/baseline.log"
[[ "${PIPESTATUS[0]}" -eq 0 ]] || { echo "baseline capture failed, aborting" >&2; exit 1; }

echo "=== Step 2: build and transport probe image ==="
"${SCRIPT_DIR}/build_image.sh" "${IMAGE_TAG}" | tee "${RUN_REPORTS_DIR}/build_image.log"
[[ "${PIPESTATUS[0]}" -eq 0 ]] || { echo "image build/transport failed, aborting" >&2; exit 1; }

echo "=== Step 3: setup (hugepages, pf0hpf, ens16f0np0) ==="
"${SCRIPT_DIR}/setup.sh" "${IMAGE_TAG}" | tee "${RUN_REPORTS_DIR}/setup.log"
[[ "${PIPESTATUS[0]}" -eq 0 ]] || { echo "setup failed, aborting" >&2; exit 1; }

echo "=== Step 4: install the composed e-switch rule (probe left running) ==="
# flow_rule.sh starts the probe detached and returns once the rule is live.
# The container keeps it installed for HOLD_SECS, which must cover step 5 —
# the whole point is that traffic hits a rule that is actually in hardware.
"${SCRIPT_DIR}/flow_rule.sh" --src-ip "${SRC_IP}" --dst-ip "${DST_IP}" --src-port "${SRC_PORT}" \
    --dst-port "${DST_PORT}" --delta "${DELTA}" --direction "${DIRECTION}" --port-id "${PORT_ID}" \
    --image-tag "${IMAGE_TAG}" --baseline-file "${REPORTS_DIR}/baseline.txt" \
    --hold-secs "${HOLD_SECS}" --container-name "${CONTAINER_NAME}" \
    | tee "${RUN_REPORTS_DIR}/flow_rule.log"
FLOW_RULE_RC="${PIPESTATUS[0]}"

echo "=== Step 5: generate and capture traffic (rule is live) ==="
"${SCRIPT_DIR}/traffic.sh" --dst-ip "${DST_IP}" --dst-port "${DST_PORT}" --seq "${SEQ}" --delta "${DELTA}" \
    | tee "${RUN_REPORTS_DIR}/traffic.log"

echo "=== Step 5b: close the hold window and collect the probe's counters ==="
# The hardware counter and software-queue count are only meaningful once
# traffic has run, so they are read here rather than at install time and
# appended to flow_rule.log, where verdict.sh reads them.
if [[ "${FLOW_RULE_RC}" -eq 0 ]]; then
    collect_probe_counters | tee -a "${RUN_REPORTS_DIR}/flow_rule.log"
else
    echo "Rule install failed; no counters to collect." | tee -a "${RUN_REPORTS_DIR}/flow_rule.log"
fi

DOCA_RESULT="accepted"
if grep -q '^RESULT: rule rejected' "${RUN_REPORTS_DIR}/flow_rule.log" || [[ "${FLOW_RULE_RC}" -ne 0 ]]; then
    DOCA_RESULT="rejected"
fi

# A tooling limitation — an unrecognised field string, or a DOCA build that
# predates the action — is not a negative result about the hardware, so it
# must not reach the cross-check. Feeding it in would compare a DOCA name we
# got wrong against rte_flow's own grammar, and an rte_flow acceptance would
# then be written up as "the capability is reachable only through rte_flow".
if grep -qE '^RESULT: (rule rejected — )?tooling limitation' "${RUN_REPORTS_DIR}/flow_rule.log"; then
    DOCA_RESULT="tooling-limitation"
fi

CROSSCHECK_LOG_ARG=()
if [[ "${DOCA_RESULT}" == "rejected" ]]; then
    echo "=== Step 6: DOCA Flow returned negative — running the rte_flow cross-check ==="
    "${SCRIPT_DIR}/crosscheck.sh" --src-ip "${SRC_IP}" --dst-ip "${DST_IP}" --src-port "${SRC_PORT}" \
        --dst-port "${DST_PORT}" --delta "${DELTA}" --doca-result "${DOCA_RESULT}" \
        | tee "${RUN_REPORTS_DIR}/crosscheck.log"
    CROSSCHECK_LOG_ARG=(--crosscheck-log "${RUN_REPORTS_DIR}/crosscheck.log")
elif [[ "${DOCA_RESULT}" == "tooling-limitation" ]]; then
    echo "=== Step 6: tooling limitation, not a hardware negative — cross-check skipped ==="
    echo "Fix the tooling issue reported in flow_rule.log and re-run; no verdict about the silicon can be drawn from this run."
else
    echo "=== Step 6: DOCA Flow accepted the rule — cross-check skipped (design.md D6) ==="
fi

echo "=== Step 7: evaluate the verdict ==="
"${SCRIPT_DIR}/verdict.sh" --flow-rule-log "${RUN_REPORTS_DIR}/flow_rule.log" \
    --traffic-log "${RUN_REPORTS_DIR}/traffic.log" "${CROSSCHECK_LOG_ARG[@]}" \
    --direction "${DIRECTION}" --delta "${DELTA}" \
    --out "${RUN_REPORTS_DIR}/verdict.txt"
VERDICT_RC=$?

echo "Run evidence and verdict written under ${RUN_REPORTS_DIR}"
exit "${VERDICT_RC}"
