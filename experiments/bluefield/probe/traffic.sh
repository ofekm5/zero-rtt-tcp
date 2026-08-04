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

# Level 3 is the only decisive verification level, so the packet it inspects
# must provably be the one we sent. A unique payload signature travels with
# the packet through the e-switch — the rewrite touches the sequence number,
# not the payload — so a returned frame carrying it is ours by construction
# rather than by assumption. Without it, any inbound TCP packet whose seq
# happens to land on sent ± delta would be accepted as proof.
STAMP="${PROBE_STAMP:-ZRTT$$}"

echo "Capturing inbound on ens16f0np0 for ${CAPTURE_SECS}s while sending TCP seq=${SENT_SEQ} to ${DST_IP}:${DST_PORT}..."
echo "Capture filter: -Q in '${CAPTURE_FILTER}'"
echo "PAYLOAD_STAMP: ${STAMP}"

vm_run "sudo timeout ${CAPTURE_SECS} tcpdump -i ens16f0np0 -Q in -w ${PCAP_PATH} '${CAPTURE_FILTER}' & \
        sleep 1 && \
        sudo hping3 -c 1 -S -p ${DST_PORT} -M ${SENT_SEQ} -d ${#STAMP} -E /dev/stdin ${DST_IP} <<< '${STAMP}' ; \
        wait" \
    || fail "traffic generation/capture failed on the host VM"

# Walk the capture packet by packet, carrying the sequence number from each
# header line down to the payload lines that follow it, and emit a sequence
# number only for packets whose payload carries our stamp.
READ_PCAP="sudo tcpdump -r ${PCAP_PATH} -n -A 2>/dev/null"
STAMPED_SEQS="$(vm_run "${READ_PCAP} | awk -v stamp='${STAMP}' '
    /seq [0-9]+/ { if (match(\$0, /seq [0-9]+/)) { s = substr(\$0, RSTART + 4, RLENGTH - 4) } }
    index(\$0, stamp) > 0 && s != \"\" { print s; s = \"\" }
'")"

# Everything inbound that matched the filter, stamped or not — reported so a
# capture full of unrelated traffic is visible rather than silently ignored.
ALL_SEQS="$(vm_run "${READ_PCAP} | grep -oE 'seq [0-9]+' | awk '{print \$2}'")"
UNSTAMPED_COUNT=$(( $(echo "${ALL_SEQS}" | grep -c . ) - $(echo "${STAMPED_SEQS}" | grep -c . ) ))

RETURNED_SEQS="${STAMPED_SEQS}"

EXPECTED_SUB=$((SENT_SEQ - DELTA))
EXPECTED_ADD=$((SENT_SEQ + DELTA))

if [[ -z "${RETURNED_SEQS}" ]]; then
    # Reachable only because the capture is inbound-only: with the outgoing
    # packet excluded, an empty result genuinely means our packet did not
    # come back. This is design.md D4's split-horizon branch.
    echo "OUTCOME: nothing returned within the ${CAPTURE_SECS}s capture window"
    echo "SENT_SEQ: ${SENT_SEQ}"
    echo "UNSTAMPED_INBOUND_PACKETS: ${UNSTAMPED_COUNT}"
    if [[ "${UNSTAMPED_COUNT}" -gt 0 ]]; then
        echo "NOTE: ${UNSTAMPED_COUNT} inbound packet(s) matched the filter but did not carry the stamp, so they are not ours. Verdict is unaffected." >&2
    fi
    exit 1
fi

echo "SENT_SEQ: ${SENT_SEQ}"
echo "RETURNED_SEQS: ${RETURNED_SEQS}"
echo "UNSTAMPED_INBOUND_PACKETS: ${UNSTAMPED_COUNT}"

for seq in ${RETURNED_SEQS}; do
    if [[ "${seq}" == "${EXPECTED_SUB}" || "${seq}" == "${EXPECTED_ADD}" ]]; then
        echo "OUTCOME: returned and rewritten (seq=${seq}, delta=${DELTA})"
        exit 0
    fi
done

echo "OUTCOME: returned unmodified (seq unchanged from sent, or does not match ± delta)"
exit 2
