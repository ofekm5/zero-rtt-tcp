#!/usr/bin/env bash
# Full end-to-end integration test for the 0-RTT TCP demo.
#
# What this script proves:
#   A TCP client can send application data immediately on the first packet —
#   without waiting for the server to complete the 3-way handshake — because
#   the ClientNIC intercepts the client's SYN and instantly spoofs a SYN-ACK
#   back. This saves one round-trip (1 RTT, typically 50-200ms on a real WAN).
#
# 4-VM chain topology (all in AWS, eu-central-1):
#
#   Client ──eth0──► ClientNIC ──eth1──► ServerNIC ──eth1──► Server
#                    (0-RTT core)        (stateless             (real
#                    spoofed SYN-ACK,    forwarder)             TCP server)
#                    seq# translation
#
# This script runs locally and drives all 4 VMs over AWS SSM (no SSH needed).
# SSM sends shell commands to EC2 instances and returns their stdout/stderr.
#
# Orchestrates all 4 VMs via AWS SSM in the correct startup order:
#   Server → ServerNIC → ClientNIC → Client
#   (Server must be ready before ClientNIC can confirm connectivity;
#    ClientNIC must be ready before the Client sends its first SYN.)
#
# Prerequisites (run locally):
#   - aws CLI configured with credentials that have SSM access
#   - python3 in PATH
#
# Usage:
#   ./experiments/scapy/run_experiment.sh
#
# Exit code: 0 = all checks passed, non-zero = number of failures

set -uo pipefail

# shellcheck source=../utils/ssm.sh
source "$(dirname "$0")/../utils/ssm.sh"
# shellcheck source=../utils/measure.sh
source "$(dirname "$0")/../utils/measure.sh"
# shellcheck source=../lib/report.sh
source "$(dirname "$0")/../lib/report.sh"

REPO_PATH="/home/ec2-user/zero-rtt-tcp"
SERVER_PORT=8080

# Legacy Scapy data plane: single app port, userspace Python — not suited to the
# high-parallel multi-port load. Pin to one port / low parallelism so the shared
# measure.sh defaults (100000 conns across 4 ports) don't overwhelm it.
export LOAD_PORTS=1
export LOAD_PARALLEL="${LOAD_PARALLEL:-1}"

# shellcheck source=../lib/output.sh
source "$(dirname "$0")/../lib/output.sh"

FAILURES=0


# ─── Step 0: Discover instances ───────────────────────────────────────────────
log "Step 0: Discovering EC2 instances..."

SERVER_ID=$(get_iid "smartnics-server")
SERVERNIC_ID=$(get_iid "smartnics-servernic")
CLIENTNIC_ID=$(get_iid "smartnics-clientnic")
CLIENT_ID=$(get_iid "smartnics-client")
SERVER_IP=$(get_ip "smartnics-server")

log "  Server:    $SERVER_ID  ($SERVER_IP)"
log "  ServerNIC: $SERVERNIC_ID"
log "  ClientNIC: $CLIENTNIC_ID"
log "  Client:    $CLIENT_ID"

for var in SERVER_ID SERVERNIC_ID CLIENTNIC_ID CLIENT_ID SERVER_IP; do
    val="${!var}"
    if [[ -z "$val" || "$val" == "None" ]]; then
        echo -e "${RED}ERROR: could not find running instance for $var${NC}" >&2
        exit 1
    fi
done


# ─── Pull latest code on all VMs ──────────────────────────────────────────────
log "Pulling latest code on all VMs..."
for iid in "$SERVER_ID" "$SERVERNIC_ID" "$CLIENTNIC_ID" "$CLIENT_ID"; do
    # SSM runs as root without $HOME set, which causes git to error on config lookups.
    # Use sudo -u ec2-user so git finds the correct user context and credentials.
    ssm_bg "$iid" "sudo -u ec2-user git -C $REPO_PATH pull origin main 2>&1 || true"
done
sleep 8   # give git pulls time to complete before starting anything


# ─── Cleanup any leftover processes ───────────────────────────────────────────
# Kill any services left over from a previous test run. Without this, a second
# run would find the server already listening (ok) but also two conflicting
# Scapy sniffers on the NIC VMs (bad — duplicate spoofed SYN-ACKs, double seq deltas).
# Also flush iptables FORWARD rules to avoid stale DROP rules from a prior run.
log "Cleaning up previous runs..."
ssm_bg "$SERVER_ID"    "pkill -f loadgen.py 2>/dev/null; rm -f /tmp/server.log"
ssm_bg "$SERVERNIC_ID" "pkill -f 'servernic/scapy' 2>/dev/null; rm -f /tmp/servernic.log; iptables -F FORWARD 2>/dev/null"
ssm_bg "$CLIENTNIC_ID" "pkill -f 'clientnic/scapy' 2>/dev/null; pkill tcpdump 2>/dev/null; rm -f /tmp/clientnic.log /tmp/client_side.pcap /tmp/server_side.pcap; iptables -F FORWARD 2>/dev/null"
sleep 3


# ─── Step 1: Start Server ─────────────────────────────────────────────────────
# The server is a plain unmodified TCP server — it knows nothing about 0-RTT.
# It must be running BEFORE ClientNIC starts, because ClientNIC will forward the
# real SYN to the server and needs a real SYN-ACK back to compute the ISN delta.
# If the server isn't up yet, ClientNIC never gets the real SYN-ACK and the
# flow table entry stays incomplete — all client data packets get buffered forever.
#
# 'setsid' detaches the process from the SSM session's process group so it keeps
# running after SSM closes the connection. 'nohup ... &' would be killed when
# SSM tears down.
log "Step 1: Starting Server..."
ssm_bg "$SERVER_ID" \
    "LOAD_PORTS=1 setsid bash $REPO_PATH/experiments/nodes/server.sh < /dev/null >> /tmp/server.log 2>&1 &"
sleep 3
# Confirm the server actually bound to the port before proceeding.
# 'ss -tlnp' shows TCP listening sockets with the process name.
LISTEN_CHECK=$(ssm_stdout "$SERVER_ID" "ss -tlnp | grep $SERVER_PORT && echo LISTENING || echo NOT_LISTENING" 30)
if echo "$LISTEN_CHECK" | grep -q "LISTENING"; then
    pass "Server listening on :$SERVER_PORT"
else
    fail "Server not listening on :$SERVER_PORT"
    echo "  ss output: $LISTEN_CHECK"
fi


# ─── Step 2: Start ServerNIC ──────────────────────────────────────────────────
# ServerNIC is a stateless forwarder: it passes packets between ClientNIC (eth0)
# and Server (eth1) without inspecting or modifying them. It has no 0-RTT logic.
#
# Why the OS route? Scapy's send() (Layer 3) uses the kernel routing table to
# pick the output interface, ignoring any iface= parameter. Without this route,
# return packets from the server subnet would be routed incorrectly.
#
# Why iptables DROP on FORWARD? Scapy captures packets directly via AF_PACKET
# (raw sockets). If the kernel ALSO forwards them, each packet gets sent twice —
# once by Scapy and once by the kernel's IP stack. The DROP rule blocks the kernel
# from touching port-8080 traffic so only Scapy handles it.
log "Step 2: Starting ServerNIC..."
ssm_bg "$SERVERNIC_ID" \
    "ip route replace 10.1.0.0/24 via 10.1.1.1 dev eth0 2>/dev/null || true"
ssm_bg "$SERVERNIC_ID" \
    "iptables -F FORWARD 2>/dev/null; iptables -A FORWARD -p tcp --dport 8080 -j DROP; iptables -A FORWARD -p tcp --sport 8080 -j DROP"
ssm_bg "$SERVERNIC_ID" \
    "echo '=== '\$(date -u +%Y-%m-%dT%H:%M:%SZ)' ===' >> /tmp/servernic.log && setsid python3 -u $REPO_PATH/src/servernic/scapy/main.py --client-iface eth0 --server-iface eth1 < /dev/null >> /tmp/servernic.log 2>&1 &"
sleep 2

# IP forwarding must be enabled at the OS level so the kernel doesn't drop
# packets that arrive on one interface destined for another subnet.
# (CDK sets this persistently via sysctl.conf; this checks it actually took effect.)
FWRD=$(ssm_stdout "$SERVERNIC_ID" "cat /proc/sys/net/ipv4/ip_forward" 30)
if [[ "$FWRD" == "1" ]]; then
    pass "ServerNIC: IP forwarding enabled"
else
    fail "ServerNIC: IP forwarding NOT enabled (got '$FWRD')"
fi


# ─── Step 3: Start ClientNIC + packet captures ────────────────────────────────
# ClientNIC is the core 0-RTT component. When a SYN arrives from the client:
#   1. It immediately sends a spoofed SYN-ACK back (with a random ISN it chose).
#      The client thinks the handshake is done and sends data right away (0-RTT!).
#   2. It also forwards the real SYN to the server via ServerNIC.
#   3. When the real SYN-ACK comes back, it records the server's real ISN.
#   4. It calculates: delta = spoofed_ISN - real_ISN
#   5. All subsequent packets are rewritten: client ACKs have delta subtracted,
#      server SEQs have delta added — so both sides see consistent sequence numbers.
#
# Same iptables/route setup as ServerNIC (see Step 2 comments).
log "Step 3: Starting ClientNIC + packet captures..."

ssm_bg "$CLIENTNIC_ID" \
    "ip route replace 10.1.2.0/24 via 10.1.1.1 dev eth1 2>/dev/null || true"
ssm_bg "$CLIENTNIC_ID" \
    "iptables -F FORWARD 2>/dev/null; iptables -A FORWARD -p tcp --dport 8080 -j DROP; iptables -A FORWARD -p tcp --sport 8080 -j DROP"
sleep 1

# Start tcpdump BEFORE launching ClientNIC so we capture the very first SYN
# and the spoofed SYN-ACK. These are the critical packets for 0-RTT validation:
#   - client_side.pcap (eth0): shows the SYN from client and the spoofed SYN-ACK
#     going back. The spoofed SYN-ACK timestamp should be earlier than the real one.
#   - server_side.pcap (eth1): shows the real SYN forwarded to server and the
#     real SYN-ACK coming back (which ClientNIC drops after recording the ISN).
ssm_bg "$CLIENTNIC_ID" \
    "setsid tcpdump -i eth0 -nn -tttt 'tcp port $SERVER_PORT' -w /tmp/client_side.pcap < /dev/null > /tmp/tcpdump_eth0.log 2>&1 &"
ssm_bg "$CLIENTNIC_ID" \
    "setsid tcpdump -i eth1 -nn -tttt 'tcp port $SERVER_PORT' -w /tmp/server_side.pcap < /dev/null > /tmp/tcpdump_eth1.log 2>&1 &"
sleep 1

ssm_bg "$CLIENTNIC_ID" \
    "echo '=== '\$(date -u +%Y-%m-%dT%H:%M:%SZ)' ===' >> /tmp/clientnic.log && setsid python3 -u $REPO_PATH/src/clientnic/scapy/main.py < /dev/null >> /tmp/clientnic.log 2>&1 &"
sleep 2

FWRD=$(ssm_stdout "$CLIENTNIC_ID" "cat /proc/sys/net/ipv4/ip_forward" 30)
if [[ "$FWRD" == "1" ]]; then
    pass "ClientNIC: IP forwarding enabled (set persistently by CDK)"
else
    fail "ClientNIC: IP forwarding NOT enabled — check CDK user data / sysctl.conf"
fi


# ─── Step 4: Run client test ──────────────────────────────────────────────────
# The client opens 3 TCP connections to the server — from its perspective a
# completely normal TCP session. ClientNIC spoofed the SYN-ACK so it knows
# nothing about 0-RTT. Success means seq/ack translation held for the full
# connection (handshake + data + teardown).
log "Step 4: Running client test (3 connections)..."
run_ttfb_measurement "$CLIENT_ID" "$SERVER_IP" "$SERVER_PORT" 3 "$REPO_PATH" 60

# Give tcpdump time to flush the last packets to disk before we kill it.
# TCP FIN/RST packets from connection teardown arrive slightly after the
# data exchange and we want them in the pcap for complete analysis.
sleep 3


# ─── Step 5: Stop captures ────────────────────────────────────────────────────
log "Step 5: Stopping packet captures..."
ssm_run "$CLIENTNIC_ID" "pkill tcpdump 2>/dev/null || true; sleep 1" 30 > /dev/null
pass "tcpdump stopped"


# ─── Step 6: Verify server received data ──────────────────────────────────────
# If sequence number translation was applied correctly, the server's TCP stack
# accepted the data as a valid in-order stream and passed it to the application.
# If translation was wrong, the server would see out-of-window or duplicate
# packets and silently discard the data — the application layer would never see it.
log "Step 6: Verifying server received data..."
SERVER_LOG=$(ssm_stdout "$SERVER_ID" "cat /tmp/server.log" 30)
echo "--- Server log ---"
echo "$SERVER_LOG"
echo "------------------"

if echo "$SERVER_LOG" | grep -qiE "Received|bytes"; then
    pass "Server received data from client"
else
    fail "Server log shows no received data"
fi


# ─── Step 7: Check ClientNIC flow table ───────────────────────────────────────
# This confirms the 0-RTT logic actually fired, not just that packets were forwarded.
# Key log entries to look for:
#   - "SYN received" / "syn received": ClientNIC intercepted the client's SYN
#   - "spoofed": the fake SYN-ACK was sent back to the client
#   - "delta" / "flow created": the real SYN-ACK arrived and the ISN delta was computed
# If none of these appear, ClientNIC may have started too late or the SYN was
# not captured (wrong interface, wrong BPF filter, or kernel forwarded it first).
log "Step 7: Checking ClientNIC flow table activity..."
CLIENTNIC_LOG=$(ssm_stdout "$CLIENTNIC_ID" "cat /tmp/clientnic.log" 30)
echo "--- ClientNIC log ---"
echo "$CLIENTNIC_LOG"
echo "---------------------"

if echo "$CLIENTNIC_LOG" | grep -qiE "delta|flow created|syn received|spoofed"; then
    pass "ClientNIC: flow table entries seen in log"
else
    fail "ClientNIC: no flow table activity in log"
fi


# ─── Step 8: Analyze packet captures ──────────────────────────────────────────
# validate_0rtt_capture.py reads both pcap files and checks:
#   1. Spoofed SYN-ACK is present on the client-side (eth0) pcap
#   2. The spoofed SYN-ACK arrived BEFORE the real one (the 0-RTT timing claim)
#   3. Spoofed ISN differs from real server ISN (proves it was generated locally)
#   4. Delta is applied correctly on all subsequent data packets
#   5. No bad TCP checksums (rewriting seq/ack must be followed by checksum recalc)
#
# File sizes are logged first — a 0-byte or missing pcap means tcpdump never ran
# or the capture file wasn't flushed before we killed it.
log "Step 8: Running packet capture analysis..."

PCAP_SIZES=$(ssm_stdout "$CLIENTNIC_ID" \
    "ls -lh /tmp/client_side.pcap /tmp/server_side.pcap 2>&1 || echo 'pcap files not found'" 30)
echo "pcap files: $PCAP_SIZES"

ANALYSIS_RESULT=$(ssm_run "$CLIENTNIC_ID" \
    "python3 $REPO_PATH/src/clientnic/validate_0rtt_capture.py \
        --client-pcap /tmp/client_side.pcap \
        --server-pcap /tmp/server_side.pcap" \
    45)

ANALYSIS_STATUS=$(echo "$ANALYSIS_RESULT" | json_idx 0)
ANALYSIS_STDOUT=$(echo "$ANALYSIS_RESULT" | json_idx 1)
ANALYSIS_STDERR=$(echo "$ANALYSIS_RESULT" | json_idx 2)

echo "--- Packet analysis (status: $ANALYSIS_STATUS) ---"
echo "$ANALYSIS_STDOUT"
[[ -n "$ANALYSIS_STDERR" ]] && echo "stderr: $ANALYSIS_STDERR"
echo "-----------------------"

if [[ "$ANALYSIS_STATUS" == "Success" ]] && echo "$ANALYSIS_STDOUT" | grep -q "All checks passed"; then
    pass "Packet capture analysis: all checks passed"
else
    NFAIL=$(printf '%s' "$ANALYSIS_STDOUT" | grep -c '\[FAIL\]' || true)
    fail "Packet capture analysis: $NFAIL check(s) failed (status=$ANALYSIS_STATUS)"
fi


# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}  ALL CHECKS PASSED${NC}"
else
    echo -e "${RED}  $FAILURES CHECK(S) FAILED${NC}"
fi
echo "════════════════════════════════════════"


# ─── Write report ─────────────────────────────────────────────────────────────
REPORT_DIR="$(dirname "$0")/reports"
mkdir -p "$REPORT_DIR"
REPORT_FILE="$REPORT_DIR/integration-test-report-$(date +%Y-%m-%d).md"

if [[ $FAILURES -eq 0 ]]; then
    OVERALL_RESULT="ALL PASSED ✅"
else
    OVERALL_RESULT="$FAILURES FAILURE(S) ❌"
fi

IMPL_INFO=$(
    echo "**Implementation**: Scapy"
    echo "**Experiment script**: \`experiments/scapy/run_experiment.sh\`"
    echo "**Node scripts**: \`experiments/scapy/\` (clientnic/servernic), \`experiments/nodes/\` (client/server)"
)

SERVERNIC_LOG=$(ssm_stdout "$SERVERNIC_ID" "cat /tmp/servernic.log 2>/dev/null || echo '(no log)'" 30)

{
    report_header "" "$IMPL_INFO" "$OVERALL_RESULT"
    report_section "Client Output" "$CLIENT_STDOUT"
    report_section "ClientNIC Log (0-RTT activity)" "$CLIENTNIC_LOG" 50
    report_section "ServerNIC Log" "$SERVERNIC_LOG" 30
    report_section "Server Log" "$SERVER_LOG" 20
    report_section "Packet Analysis" "$ANALYSIS_STDOUT" "" 1
} > "$REPORT_FILE"

log "Report saved to $REPORT_FILE"

exit "$FAILURES"
