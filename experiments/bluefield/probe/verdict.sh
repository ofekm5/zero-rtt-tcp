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
DIRECTION="" DELTA=""

fail() {
    echo "ERROR: $1" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --flow-rule-log) FLOW_RULE_LOG="$2"; shift 2 ;;
        --traffic-log) TRAFFIC_LOG="$2"; shift 2 ;;
        --crosscheck-log) CROSSCHECK_LOG="$2"; shift 2 ;;
        --direction) DIRECTION="$2"; shift 2 ;;
        --delta) DELTA="$2"; shift 2 ;;
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
    elif grep -q '^RESULT: cross-check inconclusive' "${CROSSCHECK_LOG}"; then
        # testpmd failed to start, or started but neither created nor
        # rejected the rule. Deliberately NOT treated as a rejection: that
        # would turn an environment failure into a silicon-level NO.
        CROSSCHECK_RESULT="inconclusive"
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
elif [[ "${CROSSCHECK_RESULT}" == "inconclusive" ]]; then
    VERDICT="PARTIAL"
    REASON="DOCA Flow rejected the rewrite, and the rte_flow cross-check could not be completed (see the cross-check log — testpmd did not start, or neither created nor rejected the rule). No NO may be recorded on this evidence: an environment failure is not a silicon-level answer. Fix the cross-check environment and re-run before treating the DOCA Flow rejection as decisive."
elif [[ "${ACCEPTED}" == "yes" && "${OFFLOADED}" == "yes" && "${TRAFFIC_OUTCOME}" == "unmodified" ]]; then
    # design.md D2, level 3: the rule was accepted and its hardware counter
    # incremented, but the packet came back with its original sequence
    # number — a silent no-op. The cross-check does not apply (D6
    # disambiguates a DOCA Flow *rejection*, and there was none), so this
    # is not "pending" anything; the modify action is the failing part.
    VERDICT="PARTIAL"
    REASON="Rule accepted and offloaded (hardware counter incremented), but the returned packet's sequence number was unchanged — the modify action is a silent no-op on this build (design.md D2 level 3). The cross-check does not apply: DOCA Flow accepted the rule, so there is no rejection to disambiguate."
elif [[ "${ACCEPTED}" == "yes" && "${OFFLOADED}" == "no" ]]; then
    # design.md D2, level 2 / SC3: either the counter never incremented or
    # packets landed on an ARM software queue. Both mean the rule did not
    # execute in hardware, which is a direct failure of the architecture's
    # premise rather than an API-exposure question.
    VERDICT="PARTIAL"
    REASON="Rule accepted but not confirmed offloaded (hardware counter zero, or packets observed on an ARM software queue — see SW_QUEUE_RX_COUNT in the flow-rule log). Per SC3 the rule did not execute purely in hardware; design.md D2 level 2 fails. The cross-check does not apply — DOCA Flow accepted the rule."
else
    VERDICT="PARTIAL"
    REASON="DOCA Flow did not demonstrate the full capability (accepted=${ACCEPTED} offloaded=${OFFLOADED} effective=${EFFECTIVE}, traffic-outcome=${TRAFFIC_OUTCOME}) and no cross-check result is available to disambiguate — inconclusive; re-run the cross-check stage before recording this verdict."
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
    echo
    echo "## Scope of this result — what it does and does not license"
    echo
    echo "Direction proven: ${DIRECTION:-unrecorded} (TCP sequence number only; the"
    echo "  opposite direction's acknowledgment-number rewrite was NOT exercised)."
    echo "Delta: ${DELTA:-unrecorded} — a STATIC constant supplied on the command line"
    echo "  before the flow existed."
    echo "Field string: $(grep -m1 '^SEQ_FIELD_USED:' "${FLOW_RULE_LOG}" 2>/dev/null | cut -d' ' -f2- || echo unrecorded)"
    echo "Return-packet binding: $(grep -m1 '^PAYLOAD_STAMP:' "${TRAFFIC_LOG}" 2>/dev/null | cut -d' ' -f2- || echo 'unstamped — returned packet not bound to the one sent')"
    echo
    echo "Even a YES clears the action-existence gate ONLY. It does not establish:"
    echo "  - that the acknowledgment number can be rewritten in the reverse direction;"
    echo "  - that a delta computed at runtime, after the real SYN-ACK arrives, can be"
    echo "    programmed into the e-switch at connection-setup latency (T8 needs this;"
    echo "    this run used a constant known before any packet was sent);"
    echo "  - anything about rule-install rate, concurrent flows, or e-switch table"
    echo "    capacity — all explicit non-goals of this spike (design.md Goals/Non-Goals)."
    echo
    echo "On the Offloaded level: this pipe's miss action is DROP and it configures no"
    echo "queue action, so no packet can reach the ARM software queue whether the rule"
    echo "works or not. SW_QUEUE_RX_COUNT is therefore structurally zero and carries no"
    echo "independent information; the load-bearing evidence is Accepted plus Effective."
    echo "Do not cite the Offloaded level as a third independent signal."
} | tee "${OUT_FILE}"

echo "Verdict written to ${OUT_FILE}"
