#!/usr/bin/env bash
# Sends a TCP packet with a known sequence number out ens16f0np0 on the
# x86 host VM while capturing on the same interface, and reports the
# sequence numbers of any returned packets alongside the sequence number
# sent. Distinguishes three outcomes per design.md D4: returned and
# rewritten, returned unmodified, and nothing returned within the capture
# window.
#
# Usage: ./traffic.sh --dst-ip <ip> --dst-port <port> --seq <uint32> \
#          --delta <int32> [--capture-secs <n>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hosts.sh
source "${SCRIPT_DIR}/lib/hosts.sh"

CAPTURE_SECS="5"
DST_IP=""
DST_PORT=""
SENT_SEQ=""
DELTA=""

fail() {
    echo "ERROR: $1" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dst-ip) DST_IP="$2"; shift 2 ;;
        --dst-port) DST_PORT="$2"; shift 2 ;;
        --seq) SENT_SEQ="$2"; shift 2 ;;
        --delta) DELTA="$2"; shift 2 ;;
        --capture-secs) CAPTURE_SECS="$2"; shift 2 ;;
        *) fail "unrecognised argument: $1" ;;
    esac
done

[[ -n "${DST_IP}" && -n "${DST_PORT}" && -n "${SENT_SEQ}" && -n "${DELTA}" ]] \
    || fail "missing required argument (need --dst-ip --dst-port --seq --delta)"

PCAP_PATH="/tmp/eswitch_probe_traffic_$$.pcap"

# Capture and transmit share one interface, so without a direction filter
# tcpdump records this script's own outgoing packet and every run looks like
# something came back. Two independent guards, because -Q is silently
# ignored on some capture paths: the kernel direction filter, and dropping
# frames whose source MAC is our own.
LOCAL_MAC="$(vm_run "cat /sys/class/net/ens16f0np0/address")" \
    || fail "could not read ens16f0np0's MAC address on the host VM"
[[ -n "${LOCAL_MAC}" ]] || fail "ens16f0np0 MAC address came back empty"

CAPTURE_FILTER="tcp and dst port ${DST_PORT} and not ether src ${LOCAL_MAC}"

echo "Capturing inbound on ens16f0np0 for ${CAPTURE_SECS}s while sending TCP seq=${SENT_SEQ} to ${DST_IP}:${DST_PORT}..."
echo "Capture filter: -Q in '${CAPTURE_FILTER}'"

vm_run "sudo timeout ${CAPTURE_SECS} tcpdump -i ens16f0np0 -Q in -w ${PCAP_PATH} '${CAPTURE_FILTER}' & \
        sleep 1 && \
        sudo hping3 -c 1 -S -p ${DST_PORT} -M ${SENT_SEQ} ${DST_IP} ; \
        wait" \
    || fail "traffic generation/capture failed on the host VM"

RETURNED_SEQS="$(vm_run "sudo tcpdump -r ${PCAP_PATH} -n 2>/dev/null | grep -oE 'seq [0-9]+' | awk '{print \$2}'")"

EXPECTED_SUB=$((SENT_SEQ - DELTA))
EXPECTED_ADD=$((SENT_SEQ + DELTA))

if [[ -z "${RETURNED_SEQS}" ]]; then
    # Reachable only because the capture is inbound-only: with the outgoing
    # packet excluded, an empty pcap genuinely means nothing came back.
    # This is design.md D4's split-horizon branch.
    echo "OUTCOME: nothing returned within the ${CAPTURE_SECS}s capture window"
    echo "SENT_SEQ: ${SENT_SEQ}"
    exit 1
fi

echo "SENT_SEQ: ${SENT_SEQ}"
echo "RETURNED_SEQS: ${RETURNED_SEQS}"

for seq in ${RETURNED_SEQS}; do
    if [[ "${seq}" == "${EXPECTED_SUB}" || "${seq}" == "${EXPECTED_ADD}" ]]; then
        echo "OUTCOME: returned and rewritten (seq=${seq}, delta=${DELTA})"
        exit 0
    fi
done

echo "OUTCOME: returned unmodified (seq unchanged from sent, or does not match ± delta)"
exit 2
