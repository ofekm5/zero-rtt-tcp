#!/usr/bin/env bash
# Conditional rte_flow cross-check (design.md D6): runs only when the
# DOCA Flow probe returned a negative result, and attempts the same TCP
# sequence-number modification through rte_flow via the preinstalled
# dpdk-testpmd, to distinguish a silicon limit from a DOCA Flow exposure
# gap. Needs no build, image transport, or package installation.
#
# Scope is disambiguation only: no hairpin, no traffic generation, no
# capture — it only asks "does any API on this card expose a per-flow
# TCP seq/ack modify?"
#
# Usage: ./crosscheck.sh --src-ip <ip> --dst-ip <ip> --src-port <port> \
#          --dst-port <port> --delta <int32> [--doca-result <accepted|rejected>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hosts.sh
source "${SCRIPT_DIR}/lib/hosts.sh"

SRC_IP="" DST_IP="" SRC_PORT="" DST_PORT="" DELTA=""
DOCA_RESULT="rejected"

fail() {
    echo "ERROR: $1" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --src-ip) SRC_IP="$2"; shift 2 ;;
        --dst-ip) DST_IP="$2"; shift 2 ;;
        --src-port) SRC_PORT="$2"; shift 2 ;;
        --dst-port) DST_PORT="$2"; shift 2 ;;
        --delta) DELTA="$2"; shift 2 ;;
        --doca-result) DOCA_RESULT="$2"; shift 2 ;;
        *) fail "unrecognised argument: $1" ;;
    esac
done

[[ -n "${SRC_IP}" && -n "${DST_IP}" && -n "${SRC_PORT}" && -n "${DST_PORT}" && -n "${DELTA}" ]] \
    || fail "missing required argument (need --src-ip --dst-ip --src-port --dst-port --delta)"

if [[ "${DOCA_RESULT}" != "rejected" ]]; then
    echo "SKIPPED: cross-check runs only on a negative DOCA Flow result (doca-result=${DOCA_RESULT})"
    exit 0
fi

# rte_flow syntax per design.md D1 — same 5-tuple match and modify_field
# shape as the DOCA Flow probe, expressed in testpmd's flow-create grammar.
TESTPMD_CMDS="flow create 0 transfer ingress group 0 \
pattern eth / ipv4 src is ${SRC_IP} dst is ${DST_IP} / tcp src is ${SRC_PORT} dst is ${DST_PORT} / end \
actions modify_field op sub dst_type tcp_seq_num src_type value src_value ${DELTA} width 32 / represented_port ethdev_port_id 0 / count / end"

echo "Running rte_flow cross-check via dpdk-testpmd (DOCA Flow returned negative)..."
OUTPUT="$(dpu_run "echo '${TESTPMD_CMDS}' | dpdk-testpmd -l 0-1 -n 4 -a ${PROBE_EAL_DEV} -- -i --disable-device-start 2>&1" 2>&1)" || true
echo "${OUTPUT}"

# testpmd never reaching the flow-create prompt is an environment failure,
# not a hardware answer. Recording it as "rte_flow rejected" would launder a
# broken EAL device argument or a missing binary into a silicon-level
# verdict, so it is reported as INCONCLUSIVE and left for a human.
if ! echo "${OUTPUT}" | grep -q 'testpmd>'; then
    echo "RESULT: cross-check inconclusive — dpdk-testpmd did not reach its interactive prompt."
    echo "This is an environment failure (EAL device argument, missing binary, or port probe), not evidence about the silicon. Inspect the output above and re-run."
    exit 3
fi

# Match only testpmd's own flow-create failure reporting, not any occurrence
# of "error"/"fail" anywhere in its banner and port summary.
if echo "${OUTPUT}" | grep -qiE 'Caught error type|Flow rule validation failed|^Bad arguments'; then
    echo "RESULT: rte_flow rejected the rule (silicon-level limit, not a DOCA Flow gap)"
    exit 1
fi

if echo "${OUTPUT}" | grep -qE 'Flow rule #[0-9]+ created'; then
    echo "RESULT: rte_flow accepted the rule (DOCA Flow exposure gap, not a silicon limit)"
    exit 0
fi

echo "RESULT: cross-check inconclusive — testpmd started but neither confirmed nor rejected the rule."
echo "Neither a 'Flow rule #N created' nor a 'Caught error type' line was found. Inspect the output above."
exit 3
