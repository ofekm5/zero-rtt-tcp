#!/usr/bin/env bash
# Evaluates the three verification levels (Accepted / Offloaded /
# Effective, design.md D2) plus the conditional cross-check (D6) and
# emits YES, NO, or PARTIAL per the decision tables in D2, D4, and D6.
#
# A YES requires all three levels to hold. A NO is emitted only after a
# negative cross-check. A cross-check that succeeds where DOCA Flow
# failed yields PARTIAL — the capability exists but is reachable only
# through rte_flow on this build.
#
# Usage: ./verdict.sh --flow-rule-log <path> --traffic-log <path> \
#          [--crosscheck-log <path>] [--out <path>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FLOW_RULE_LOG="" TRAFFIC_LOG="" CROSSCHECK_LOG=""
OUT_FILE="${SCRIPT_DIR}/../reports/verdict.txt"

fail() {
    echo "ERROR: $1" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --flow-rule-log) FLOW_RULE_LOG="$2"; shift 2 ;;
        --traffic-log) TRAFFIC_LOG="$2"; shift 2 ;;
        --crosscheck-log) CROSSCHECK_LOG="$2"; shift 2 ;;
        --out) OUT_FILE="$2"; shift 2 ;;
        *) fail "unrecognised argument: $1" ;;
    esac
done

[[ -n "${FLOW_RULE_LOG}" && -f "${FLOW_RULE_LOG}" ]] || fail "--flow-rule-log is required and must exist"
[[ -n "${TRAFFIC_LOG}" && -f "${TRAFFIC_LOG}" ]] || fail "--traffic-log is required and must exist"

mkdir -p "$(dirname "${OUT_FILE}")"

# Level 1: Accepted — rule-creation call returned a valid handle.
ACCEPTED="no"
grep -q '^RESULT: rule accepted' "${FLOW_RULE_LOG}" && ACCEPTED="yes"

# Level 2: Offloaded — hardware counter nonzero and software-queue
# receive count is zero (a nonzero software count means the rule fell
# back to software, per SC3).
OFFLOADED="no"
if [[ "${ACCEPTED}" == "yes" ]]; then
    HW_COUNT="$(grep -oE 'total_pkts=[0-9]+' "${FLOW_RULE_LOG}" | head -n1 | grep -oE '[0-9]+' || echo 0)"
    SW_COUNT="$(grep -oE 'SW_QUEUE_RX_COUNT: [0-9]+' "${FLOW_RULE_LOG}" | head -n1 | grep -oE '[0-9]+' || echo 0)"
    if [[ "${HW_COUNT:-0}" -gt 0 && "${SW_COUNT:-0}" -eq 0 ]]; then
        OFFLOADED="yes"
    fi
fi

# Level 3: Effective — tcpdump on ens16f0np0 shows returned seq == sent ± delta.
# traffic.sh reports one of three distinct outcomes (design.md D4); keep
# them distinguished rather than collapsing to a single EFFECTIVE bit, so
# a same-port split-horizon rejection (rewrite worked, nothing returned)
# is not conflated with the rewrite never happening at all.
EFFECTIVE="no"
TRAFFIC_OUTCOME="unknown"
if grep -q '^OUTCOME: returned and rewritten' "${TRAFFIC_LOG}"; then
    EFFECTIVE="yes"
    TRAFFIC_OUTCOME="rewritten"
elif grep -q '^OUTCOME: returned unmodified' "${TRAFFIC_LOG}"; then
    TRAFFIC_OUTCOME="unmodified"
elif grep -q '^OUTCOME: nothing returned' "${TRAFFIC_LOG}"; then
    TRAFFIC_OUTCOME="nothing-returned"
fi

CROSSCHECK_RESULT="not-run"
if [[ -n "${CROSSCHECK_LOG}" && -f "${CROSSCHECK_LOG}" ]]; then
    if grep -q '^RESULT: rte_flow accepted' "${CROSSCHECK_LOG}"; then
        CROSSCHECK_RESULT="accepted"
    elif grep -q '^RESULT: rte_flow rejected' "${CROSSCHECK_LOG}"; then
        CROSSCHECK_RESULT="rejected"
    elif grep -q '^SKIPPED:' "${CROSSCHECK_LOG}"; then
        CROSSCHECK_RESULT="skipped"
    fi
fi

VERDICT=""
REASON=""

if [[ "${ACCEPTED}" == "yes" && "${OFFLOADED}" == "yes" && "${EFFECTIVE}" == "yes" ]]; then
    VERDICT="YES"
    REASON="All three verification levels hold: rule accepted, offloaded to hardware, and the rewrite is observed on the wire."
elif [[ "${ACCEPTED}" == "yes" && "${OFFLOADED}" == "yes" && "${TRAFFIC_OUTCOME}" == "nothing-returned" ]]; then
    # design.md D4, first sub-case: the rewrite matched and offloaded in
    # hardware, but nothing came back on the wire — e-switch split-horizon
    # is the likely cause, not a rewrite failure. The cross-check doesn't
    # apply here (D6 only disambiguates a DOCA Flow rejection); the named
    # architectural fallback is a Scalable Function egress instead of
    # returning out pf0hpf (design.md Alternative C).
    VERDICT="PARTIAL"
    REASON="Rule accepted and offloaded (hardware counter incremented, no software fallback), but no packet returned on ens16f0np0 within the capture window — e-switch split-horizon is the likely cause per design.md D4. The composed rewrite is not proven ineffective; the architectural fallback is a Scalable Function as egress instead of returning out pf0hpf (design.md Alternative C)."
elif [[ "${CROSSCHECK_RESULT}" == "accepted" ]]; then
    VERDICT="PARTIAL"
    REASON="DOCA Flow did not demonstrate the full capability, but the rte_flow cross-check accepted the same rewrite — the capability exists but is reachable only through rte_flow on this build."
elif [[ "${CROSSCHECK_RESULT}" == "rejected" ]]; then
    VERDICT="NO"
    REASON="DOCA Flow did not demonstrate the capability and the rte_flow cross-check also rejected the rewrite — not a DOCA Flow exposure gap."
else
    VERDICT="PARTIAL"
    REASON="DOCA Flow did not demonstrate the full capability (accepted=${ACCEPTED} offloaded=${OFFLOADED} effective=${EFFECTIVE}, traffic-outcome=${TRAFFIC_OUTCOME}) and no cross-check result is available yet to disambiguate — inconclusive pending the cross-check."
fi

{
    echo "# eswitch-offload-probe verdict"
    echo "# evaluated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "## Verification levels"
    echo "- Accepted: ${ACCEPTED}"
    echo "- Offloaded: ${OFFLOADED}"
    echo "- Effective: ${EFFECTIVE}"
    echo "- Traffic outcome: ${TRAFFIC_OUTCOME}"
    echo "- Cross-check: ${CROSSCHECK_RESULT}"
    echo
    echo "## VERDICT: ${VERDICT}"
    echo "${REASON}"
} | tee "${OUT_FILE}"

echo "Verdict written to ${OUT_FILE}"
