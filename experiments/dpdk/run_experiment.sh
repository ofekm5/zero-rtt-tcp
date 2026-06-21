#!/usr/bin/env bash
# End-to-end integration test for the 0-RTT TCP demo — T8 ISN ack-num translation shift.
#
# T8 topology (all in AWS, eu-central-1):
#
#   Client ──eth0──► ClientNIC (dpdk-forwarder) ──eth1──► ServerNIC (servernic-dpdk) ──eth2──► Server
#
# ClientNIC (dpdk-forwarder):
#   eth0: AF_PACKET raw socket (client-facing, kernel stack)
#   eth1: DPDK ENA PMD via vfio-pci (server-facing, Middle subnet)
#   Role: spoof SYN-ACK, stamp V in forwarded SYN ack-num, transparent forward otherwise
#
# ServerNIC (servernic-dpdk):
#   eth0: kernel/management
#   eth1: DPDK ENA PMD via vfio-pci (ClientNIC-facing, Middle subnet)
#   eth2: AF_PACKET (Server-facing, Server subnet)
#   Role: extract V, translate all seq/ack, drop real SYN-ACK after delta compute
#
# This script runs locally and drives all 4 VMs over AWS SSM.
#
# Prerequisites (run locally):
#   - aws CLI configured with credentials that have SSM access
#   - python3 in PATH
#   - ClientNIC and ServerNIC VMs provisioned with infra/dpdk CDK stack
#
# Usage:
#   ./experiments/dpdk/run_experiment.sh
#
# Exit code: 0 = all checks passed, non-zero = number of failures

set -uo pipefail

# Force UTF-8 I/O for the AWS CLI (also Python) so non-ASCII chars in VM log
# output (em-dashes, arrows) don't cause cp1252 encode errors on Windows.
export PYTHONUTF8=1
export PYTHONIOENCODING=utf-8

# shellcheck source=../utils/ssm.sh
source "$(dirname "$0")/../utils/ssm.sh"
# shellcheck source=../utils/measure.sh
source "$(dirname "$0")/../utils/measure.sh"

REPO_PATH="/home/ec2-user/zero-rtt-demo"
DPDK_BUILD="$REPO_PATH/clientnic/dpdk-forwarder/builddir"
BINARY="$DPDK_BUILD/clientnic-dpdk-forwarder"
SERVERNIC_BINARY="$REPO_PATH/servernic/dpdk/builddir/servernic-dpdk"
SERVER_PORT=8080

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# Number of sequential connections to run. Override via env: CONNECTIONS=20 ./run_experiment.sh
CONNECTIONS="${CONNECTIONS:-5}"

FAILURES=0

log()  { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}" >&2; }
pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; FAILURES=$((FAILURES + 1)); }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }


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


# ─── Pull latest code ─────────────────────────────────────────────────────────
log "Pulling latest code on all VMs..."
for iid in "$SERVER_ID" "$SERVERNIC_ID" "$CLIENTNIC_ID" "$CLIENT_ID"; do
    ssm_bg "$iid" "git config --global --add safe.directory $REPO_PATH 2>/dev/null || true; sudo -u ec2-user git -C $REPO_PATH pull origin main 2>&1 || true"
done
sleep 8

# ─── Disable TCP options on Client + Server ───────────────────────────────────
# The 0-RTT spoofed SYN-ACK has no TCP options (bare 20-byte header). If the
# real SYN/SYN-ACK carry window-scale, timestamps, or SACK, the client and server
# end up with inconsistent negotiated state → window stalls at ~11 Kbits/sec.
# These options are unnecessary in this intra-VPC demo environment.
log "Disabling TCP timestamps/window-scaling/SACK on Client and Server..."
ssm_bg "$CLIENT_ID" "sysctl -w net.ipv4.tcp_timestamps=0 net.ipv4.tcp_window_scaling=0 net.ipv4.tcp_sack=0"
ssm_bg "$SERVER_ID" "sysctl -w net.ipv4.tcp_timestamps=0 net.ipv4.tcp_window_scaling=0 net.ipv4.tcp_sack=0"
sleep 2


# ─── Accuracy knobs: offload-off + netem on endpoint NICs ─────────────────────
# GRO/LRO/TSO/GSO coalesce multiple segments into one super-segment before the
# kernel timestamps them, corrupting the per-segment timing events (send_unlock,
# server_gap) that the metrics pipeline measures.  Disabling all four on Client
# and Server is the single biggest per-packet fidelity lever.
# tc netem 50 ms/side inflates the RTT to ~100 ms so the ~1-RTT 0-RTT saving
# is two orders of magnitude above tens-of-µs pcap jitter (design D5/X2 hard
# dependency: sub-ms LAN would make the saving invisible in the noise floor).
log "Accuracy knobs: disabling GRO/LRO/TSO/GSO on Client and Server NICs..."
ssm_bg "$CLIENT_ID" "ethtool -K eth0 gro off lro off tso off gso off 2>/dev/null || true"
ssm_bg "$SERVER_ID" "ethtool -K eth0 gro off lro off tso off gso off 2>/dev/null || true"

log "Accuracy knobs: applying tc netem 50ms delay on Client and Server egress..."
ssm_bg "$CLIENT_ID" \
    "tc qdisc del dev eth0 root 2>/dev/null || true; \
     tc qdisc add dev eth0 root netem delay 50ms 2>/dev/null || true"
ssm_bg "$SERVER_ID" \
    "tc qdisc del dev eth0 root 2>/dev/null || true; \
     tc qdisc add dev eth0 root netem delay 50ms 2>/dev/null || true"
sleep 2


# ─── Cleanup any leftover processes ───────────────────────────────────────────
# ClientNIC cleanup is blocking (ssm_run) so the DPDK lock is released before
# the smoke test tries to start a new primary process.
log "Cleaning up previous runs..."
ssm_bg "$SERVER_ID"    "pkill -9 -f iperf 2>/dev/null; conntrack -F 2>/dev/null || true; rm -f /tmp/server.log"
ssm_bg "$SERVERNIC_ID" "pkill -x servernic-dpdk 2>/dev/null; pkill -f 'servernic/scapy' 2>/dev/null; rm -f /tmp/servernic.log; iptables -F FORWARD 2>/dev/null; iptables -F OUTPUT 2>/dev/null"
ssm_run "$CLIENTNIC_ID" "pkill -f clientnic-dpdk-forwarder 2>/dev/null; pkill -f clientnic-dpdk 2>/dev/null; pkill tcpdump 2>/dev/null; sleep 5; pkill -9 -f clientnic-dpdk-forwarder 2>/dev/null; sleep 2; rm -rf /var/run/dpdk/rte/ 2>/dev/null; rm -f /tmp/clientnic.log /tmp/client_side.pcap /tmp/validate_0rtt.py; iptables -F FORWARD 2>/dev/null; echo CLEANUP_DONE" 30 > /dev/null
sleep 5  # let stale TCP retransmits drain so new iperf3 server starts clean


# ─── Build step: build dpdk-forwarder (ClientNIC) + servernic-dpdk (ServerNIC) ─
# The CDK user data builds both binaries at provision time, but we rebuild after
# pulling the latest code to pick up any changes made since the instance launched.
log "Build: Building clientnic-dpdk-forwarder on ClientNIC VM..."

BUILD_RESULT=$(ssm_run "$CLIENTNIC_ID" \
    "export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig; \
     cd $REPO_PATH/clientnic/dpdk-forwarder; \
     rm -rf builddir; \
     /usr/local/bin/meson setup builddir 2>&1 && \
     cd builddir && /usr/local/bin/ninja 2>&1 && \
     echo 'BUILD_SUCCESS'" \
    600)

BUILD_STATUS=$(echo "$BUILD_RESULT" | json_idx 0)
BUILD_STDOUT=$(echo "$BUILD_RESULT" | json_idx 1)
BUILD_STDERR=$(echo "$BUILD_RESULT" | json_idx 2)

echo "--- ClientNIC build output (last 20 lines) ---"
echo "$BUILD_STDOUT" | tail -20
[[ -n "$BUILD_STDERR" ]] && echo "stderr: $BUILD_STDERR" | tail -10
echo "----------------------------------------------"

if echo "$BUILD_STDOUT" | grep -q "BUILD_SUCCESS"; then
    pass "Build: clientnic-dpdk-forwarder meson + ninja build succeeded"
else
    fail "Build: clientnic-dpdk-forwarder build failed (status=$BUILD_STATUS)"
    echo "Full build output:"
    echo "$BUILD_STDOUT"
fi

log "Build: Building servernic-dpdk on ServerNIC VM..."

SERVERNIC_BUILD_RESULT=$(ssm_run "$SERVERNIC_ID" \
    "export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig; \
     cd $REPO_PATH/servernic/dpdk; \
     rm -rf builddir; \
     /usr/local/bin/meson setup builddir 2>&1 && \
     cd builddir && /usr/local/bin/ninja 2>&1 && \
     echo 'BUILD_SUCCESS'" \
    600)

SERVERNIC_BUILD_STATUS=$(echo "$SERVERNIC_BUILD_RESULT" | json_idx 0)
SERVERNIC_BUILD_STDOUT=$(echo "$SERVERNIC_BUILD_RESULT" | json_idx 1)

echo "--- ServerNIC build output (last 20 lines) ---"
echo "$SERVERNIC_BUILD_STDOUT" | tail -20
echo "----------------------------------------------"

if echo "$SERVERNIC_BUILD_STDOUT" | grep -q "BUILD_SUCCESS"; then
    pass "Build: servernic-dpdk meson + ninja build succeeded"
else
    fail "Build: servernic-dpdk build failed (status=$SERVERNIC_BUILD_STATUS)"
    echo "Full build output:"
    echo "$SERVERNIC_BUILD_STDOUT"
fi


# ─── Smoke test: binaries start without errors ───────────────────────────────
# Gateway MAC for ClientNIC: ServerNIC eth1 MAC (DeviceIndex=1, Middle subnet, DPDK port).
# eth1 is DPDK-controlled so the kernel can't ARP for it — read from EC2 API.
log "Smoke test: discovering ServerNIC eth1 MAC (ClientNIC gateway)..."

GW_MAC=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=smartnics-servernic" "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==\`1\`].MacAddress" \
    --output text --region eu-central-1 2>/dev/null | tr -d '[:space:]')

# ClientNIC eth1 MAC (DeviceIndex=1) → ServerNIC needs this as --gw-mac
CLIENTNIC_ETH1_MAC=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=smartnics-clientnic" "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==\`1\`].MacAddress" \
    --output text --region eu-central-1 2>/dev/null | tr -d '[:space:]')

# Server eth0 MAC (DeviceIndex=0) → ServerNIC needs this as --server-gw-mac
SERVER_ETH0_MAC=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=smartnics-server" "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==\`0\`].MacAddress" \
    --output text --region eu-central-1 2>/dev/null | tr -d '[:space:]')

log "  ClientNIC eth1 MAC (ServerNIC --gw-mac):      ${CLIENTNIC_ETH1_MAC:-UNKNOWN}"
log "  Server eth0 MAC (ServerNIC --server-gw-mac):  ${SERVER_ETH0_MAC:-UNKNOWN}"

if [[ -z "$GW_MAC" || "$GW_MAC" == "None" ]]; then
    fail "Smoke test: could not discover ServerNIC eth1 MAC (DeviceIndex=1)"
else
    log "  Gateway MAC (ServerNIC eth1, DPDK port): $GW_MAC"

    # Smoke-test clientnic-dpdk-forwarder: run 3 s, check for busy-poll
    ssm_run "$CLIENTNIC_ID" \
        "rm -f /tmp/clientnic_smoke.log; \
         setsid $BINARY -l 0 -- --port=$SERVER_PORT --gw-mac=$GW_MAC \
             < /dev/null > /tmp/clientnic_smoke.log 2>&1 & \
         BPID=\$!; sleep 3; kill \$BPID 2>/dev/null; wait \$BPID 2>/dev/null; true" \
        30 > /dev/null

    SMOKE_LOG=$(ssm_stdout "$CLIENTNIC_ID" "cat /tmp/clientnic_smoke.log 2>/dev/null || echo MISSING" 30)
    echo "--- ClientNIC forwarder smoke log ---"
    echo "$SMOKE_LOG"
    echo "-------------------------------------"

    if echo "$SMOKE_LOG" | grep -qiE "busy-poll loop|Entering busy-poll"; then
        pass "Smoke test: clientnic-dpdk-forwarder entered busy-poll loop"
    elif echo "$SMOKE_LOG" | grep -qiE "port.*started|DPDK.*start"; then
        pass "Smoke test: clientnic-dpdk-forwarder DPDK port initialised"
    elif echo "$SMOKE_LOG" | grep -qiE "EAL.*FATAL|Cannot create lock|EAL init failed"; then
        fail "Smoke test: clientnic-dpdk-forwarder EAL init failed (stale DPDK lock?)"
    else
        fail "Smoke test: clientnic-dpdk-forwarder did not reach expected startup state"
    fi
fi


# ─── Step 1: Start Server ─────────────────────────────────────────────────────
log "Step 1: Starting Server via node script..."
ssm_bg "$SERVER_ID" \
    "setsid bash $REPO_PATH/experiments/nodes/server.sh < /dev/null >> /tmp/server.log 2>&1 &"
sleep 3

LISTEN_CHECK=$(ssm_stdout "$SERVER_ID" "ss -tlnp | grep $SERVER_PORT && echo LISTENING || echo NOT_LISTENING" 30)
if echo "$LISTEN_CHECK" | grep -q "LISTENING"; then
    pass "Server listening on :$SERVER_PORT"
else
    fail "Server not listening on :$SERVER_PORT"
    echo "  ss output: $LISTEN_CHECK"
fi


# ─── Step 2: Start ServerNIC (DPDK binary) ───────────────────────────────────
# nodes/servernic.sh: discovers ClientNIC eth1 MAC + Server eth0 MAC via EC2 API,
# builds (or skips with SKIP_BUILD=1), installs iptables rules, launches servernic-dpdk.
log "Step 2: Starting ServerNIC DPDK binary via node script..."
ssm_bg "$SERVERNIC_ID" \
    "SKIP_BUILD=1 CLIENTNIC_GW_MAC=$CLIENTNIC_ETH1_MAC SERVER_GW_MAC=$SERVER_ETH0_MAC MIDDLE_ENI_MAC=$GW_MAC setsid bash $REPO_PATH/experiments/dpdk/servernic.sh < /dev/null >> /tmp/servernic.log 2>&1 &"
sleep 5  # DPDK EAL + vfio-pci bind + ENA PMD init (~3-4 s)

SERVERNIC_RUNNING=$(ssm_stdout "$SERVERNIC_ID" "pgrep -f servernic-dpdk && echo RUNNING || echo NOT_RUNNING" 30)
if echo "$SERVERNIC_RUNNING" | grep -q "RUNNING"; then
    pass "ServerNIC: servernic-dpdk process is running"
else
    fail "ServerNIC: servernic-dpdk process not found — startup failed"
    SERVERNIC_LOG_EARLY=$(ssm_stdout "$SERVERNIC_ID" "cat /tmp/servernic.log 2>/dev/null || echo '(no log)'" 30)
    echo "--- ServerNIC early log ---"
    echo "$SERVERNIC_LOG_EARLY"
    echo "---------------------------"
fi

FWRD=$(ssm_stdout "$SERVERNIC_ID" "cat /proc/sys/net/ipv4/ip_forward" 30)
if [[ "$FWRD" == "1" ]]; then
    pass "ServerNIC: IP forwarding enabled"
else
    fail "ServerNIC: IP forwarding NOT enabled (got '$FWRD')"
fi


# ─── Step 3: Start ClientNIC (dpdk-forwarder) ────────────────────────────────
# Uses the T8 dpdk-forwarder binary — transparent forwarding with V-stamping.
# The binary manages its own iptables rules (install_iptables() in main.c).
#
# Gateway MAC is ServerNIC's eth1 MAC (Middle subnet DPDK port, next hop).
# eth1 must already be bound to vfio-pci (done by CDK user data at boot).
log "Step 3: Starting ClientNIC (dpdk-forwarder) via node script..."

# Flush any stale iptables DROP rules from the smoke test before the node script runs.
ssm_bg "$CLIENTNIC_ID" "iptables -F FORWARD 2>/dev/null; iptables -F OUTPUT 2>/dev/null || true"
sleep 1

# nodes/clientnic.sh handles: cleanup, build (skipped via SKIP_BUILD=1), GW MAC (passed
# as $1 — bypasses EC2 API call from VM), tcpdump on eth0, exec forwarder binary.
# SKIP_BUILD=1 because meson+ninja already ran in the build step above.
ssm_bg "$CLIENTNIC_ID" \
    "SKIP_BUILD=1 setsid bash $REPO_PATH/experiments/dpdk/clientnic.sh $GW_MAC < /dev/null >> /tmp/clientnic.log 2>&1 &"
sleep 5  # node script: cleanup + checks + tcpdump start + DPDK EAL + ENA PMD init (~3-4 s)

FWRD=$(ssm_stdout "$CLIENTNIC_ID" "cat /proc/sys/net/ipv4/ip_forward" 30)
if [[ "$FWRD" == "1" ]]; then
    pass "ClientNIC: IP forwarding enabled"
else
    fail "ClientNIC: IP forwarding NOT enabled"
fi

# Confirm the forwarder binary is running
DPDK_RUNNING=$(ssm_stdout "$CLIENTNIC_ID" "pgrep -f clientnic-dpdk-forwarder && echo RUNNING || echo NOT_RUNNING" 30)
if echo "$DPDK_RUNNING" | grep -q "RUNNING"; then
    pass "Step 3: clientnic-dpdk-forwarder process is running"
else
    fail "Step 3: clientnic-dpdk-forwarder process not found — startup failed"
    DPDK_LOG=$(ssm_stdout "$CLIENTNIC_ID" "cat /tmp/clientnic.log" 30)
    echo "--- ClientNIC forwarder log ---"
    echo "$DPDK_LOG"
    echo "-------------------------------"
fi


# ─── Step 3b: Start endpoint captures on Client and Server ───────────────────
# These are endpoint-side (application host) captures, yielding the accurate
# FCT, send_unlock, and server_gap metrics consumed by analyze_metrics.py.
# High-precision hardware timestamping is requested via --time-stamp-precision=nano
# where supported; we fall back gracefully to host_hiprec (software nanosecond)
# and finally to standard µs timestamps if neither flag is accepted.
log "Step 3b: Starting endpoint tcpdump captures (Client host + Server host)..."
ssm_run "$CLIENT_ID" "pkill tcpdump 2>/dev/null || true; rm -f /tmp/client_side.pcap" 15 > /dev/null
ssm_run "$SERVER_ID" "pkill tcpdump 2>/dev/null || true; rm -f /tmp/server_side.pcap" 15 > /dev/null

# Detect high-precision tcpdump flag on each host synchronously, then start
# the chosen tcpdump in the background as a single unconditional & command.
# Probe order:
#   1. --time-stamp-precision=nano  (tcpdump 4.5+, preferred)
#   2. -j adapter (some older distros use -j to select timestamp type)
#   3. No high-precision flag (standard µs fallback)
# Detection uses a dry-run (-d: dump BPF bytecode) which exits 0 immediately
# with the flag accepted or non-zero if the flag is unrecognised — no capture
# is started during probing, so the async & does not corrupt exit status.
host_hiprec_start() {
    local iid="$1" iface="$2" filter="$3" outfile="$4"
    ssm_bg "$iid" "
if tcpdump --time-stamp-precision=nano -d -i lo 2>/dev/null | grep -q .; then
    HIPREC_FLAG='--time-stamp-precision=nano'
    echo TCPDUMP_HIPREC_NANO
elif tcpdump -j adapter -d -i lo 2>/dev/null | grep -q .; then
    HIPREC_FLAG='-j adapter'
    echo TCPDUMP_HIPREC_ADAPTER
else
    HIPREC_FLAG=''
    echo TCPDUMP_STANDARD
fi
tcpdump \$HIPREC_FLAG -i $iface -nn -s 128 '$filter' -w $outfile </dev/null >/tmp/tcpdump_hiprec.log 2>&1 &
echo TCPDUMP_PID=\$!
"
}

host_hiprec_start "$CLIENT_ID" "eth0" "tcp port $SERVER_PORT" "/tmp/client_side.pcap"
host_hiprec_start "$SERVER_ID" "eth0" "tcp port $SERVER_PORT" "/tmp/server_side.pcap"
sleep 2  # allow tcpdump processes to open pcap files before traffic starts


# ─── Step 4: Run client test ──────────────────────────────────────────────────
log "Step 4: Running client test ($CONNECTIONS connection(s))..."
run_ttfb_measurement "$CLIENT_ID" "$SERVER_IP" "$SERVER_PORT" "$CONNECTIONS" "$REPO_PATH" 120

sleep 3


# ─── Step 5: Stop captures and binaries ──────────────────────────────────────
log "Step 5: Stopping packet captures and DPDK binaries..."
# Stop endpoint captures first (Client + Server hosts)
ssm_run "$CLIENT_ID"   "pkill tcpdump 2>/dev/null || true; sleep 1" 30 > /dev/null
ssm_run "$SERVER_ID"   "pkill tcpdump 2>/dev/null || true; sleep 1" 30 > /dev/null
# Stop NIC-side captures and DPDK binaries
ssm_run "$CLIENTNIC_ID" "pkill tcpdump 2>/dev/null || true; sleep 1" 30 > /dev/null
ssm_run "$CLIENTNIC_ID" "pkill -f clientnic-dpdk-forwarder 2>/dev/null || true; sleep 2" 30 > /dev/null
ssm_run "$SERVERNIC_ID" "pkill -f servernic-dpdk 2>/dev/null || true; sleep 2" 30 > /dev/null
pass "Captures stopped, DPDK binaries signalled"


# ─── Step 6: Verify server received data ──────────────────────────────────────
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


# ─── Step 7: Collect and check per-VM logs ───────────────────────────────────
log "Step 7: Collecting per-VM logs..."

SERVERNIC_LOG=$(ssm_stdout "$SERVERNIC_ID" "cat /tmp/servernic.log 2>/dev/null || echo '(no log)'" 30)
echo "--- ServerNIC log ---"
echo "$SERVERNIC_LOG"
echo "---------------------"

CLIENTNIC_LOG=$(ssm_stdout "$CLIENTNIC_ID" "cat /tmp/clientnic.log" 30)
echo "--- ClientNIC DPDK log ---"
echo "$CLIENTNIC_LOG"
echo "--------------------------"

if echo "$CLIENTNIC_LOG" | grep -qiE "flow created|spoofed SYN-ACK|SYN forwarded|V="; then
    pass "ClientNIC dpdk-forwarder: 0-RTT flow table activity confirmed"
else
    fail "ClientNIC dpdk-forwarder: no flow table activity in log"
fi

if echo "$SERVERNIC_LOG" | grep -qiE "PENDING|delta|SYN-ACK.*drop|flush|V="; then
    pass "ServerNIC dpdk: translation activity confirmed"
else
    warn "ServerNIC dpdk: no translation activity in log (may indicate no SYN-ACK received yet)"
fi


# ─── Packet capture analysis ──────────────────────────────────────────────────
# analyze_metrics.py computes three endpoint-observed metrics from the pcaps:
#   - fct         (client pcap): first SYN out → last data byte or FIN
#   - send_unlock (client pcap): first SYN out → first outbound payload segment
#   - server_gap  (server pcap): first SYN-ACK out → first inbound payload segment
# Captures are at the endpoint hosts (Client + Server), not at the NICs.
log "Packet analysis: Collecting endpoint pcap sizes..."

CLIENT_PCAP_SIZE=$(ssm_stdout "$CLIENT_ID" \
    "ls -lh /tmp/client_side.pcap 2>&1 || echo 'pcap file not found'" 30)
SERVER_PCAP_SIZE=$(ssm_stdout "$SERVER_ID" \
    "ls -lh /tmp/server_side.pcap 2>&1 || echo 'pcap file not found'" 30)
echo "  client_side.pcap: $CLIENT_PCAP_SIZE"
echo "  server_side.pcap: $SERVER_PCAP_SIZE"

# Fetch pcaps from endpoint hosts to the ClientNIC for analysis
# (analyzer runs where scapy is available — ClientNIC has it from CDK setup)
log "Packet analysis: Fetching server_side.pcap from Server host to ClientNIC..."
SERVER_PCAP_B64=$(ssm_stdout "$SERVER_ID" \
    "base64 /tmp/server_side.pcap 2>/dev/null || echo ''" 30)
if [[ -n "$SERVER_PCAP_B64" ]]; then
    ssm_bg "$CLIENTNIC_ID" \
        "echo '$SERVER_PCAP_B64' | base64 -d > /tmp/server_side.pcap"
    sleep 1
fi

log "Packet analysis: Fetching client_side.pcap from Client host to ClientNIC..."
CLIENT_PCAP_B64=$(ssm_stdout "$CLIENT_ID" \
    "base64 /tmp/client_side.pcap 2>/dev/null || echo ''" 30)
if [[ -n "$CLIENT_PCAP_B64" ]]; then
    ssm_bg "$CLIENTNIC_ID" \
        "echo '$CLIENT_PCAP_B64' | base64 -d > /tmp/client_side_endpoint.pcap"
    sleep 1
fi

# Run analyze_metrics.py on the endpoint pcaps
log "Packet analysis: Running analyze_metrics.py on endpoint pcaps..."
ANALYSIS_RESULT=$(ssm_run "$CLIENTNIC_ID" \
    "python3 $REPO_PATH/experiments/utils/analyze_metrics.py \
        --client-pcap /tmp/client_side_endpoint.pcap \
        --server-pcap /tmp/server_side.pcap" \
    60)

ANALYSIS_STATUS=$(echo "$ANALYSIS_RESULT" | json_idx 0)
ANALYSIS_STDOUT=$(echo "$ANALYSIS_RESULT" | json_idx 1)
ANALYSIS_STDERR=$(echo "$ANALYSIS_RESULT" | json_idx 2)

echo "--- Endpoint metric analysis (status: $ANALYSIS_STATUS) ---"
echo "$ANALYSIS_STDOUT"
[[ -n "$ANALYSIS_STDERR" ]] && echo "stderr: $ANALYSIS_STDERR"
echo "------------------------------------------------------------"

if [[ "$ANALYSIS_STATUS" == "Success" ]] && ! echo "$ANALYSIS_STDOUT" | grep -q "^missing="; then
    pass "Packet analysis: all endpoint metrics computed"
else
    NMISSING=$(printf '%s' "$ANALYSIS_STDOUT" | grep -c '^missing=' || true)
    fail "Packet analysis: $NMISSING missing metric event(s) (status=$ANALYSIS_STATUS)"
fi

# Feed analyze_metrics.py output into measure.sh summarize_metric for latency summary
ENDPOINT_METRICS="$ANALYSIS_STDOUT"


# ─── Latency metrics: TTFB at 3 points + FCT + endpoint pcap metrics ─────────
# Each TTFB is an intra-host interval (SYN ingress → first s2c data byte), so the
# three points need no clock sync. FCT is the client connect→FIN lifetime.
# Endpoint pcap metrics (fct, send_unlock, server_gap) come from analyze_metrics.py
# and are fed into measure.sh's summarize_metric for consistent output format.
log "Latency metrics: aggregating TTFB (ClientNIC, ServerNIC, Client) + FCT + endpoint pcap metrics..."
METRICS_SUMMARY=$(
    report_nic_ttfb "$CLIENTNIC_LOG" "clientnic"
    report_nic_ttfb "$SERVERNIC_LOG" "servernic"
    echo "$CLIENT_STDOUT" | summarize_metric "ttfb" "client" "Client TTFB   "
    echo "$CLIENT_STDOUT" | summarize_metric "fct"  "client" "Client FCT    "
    echo "${ENDPOINT_METRICS:-}" | summarize_metric "fct"         "client" "Pcap FCT      "
    echo "${ENDPOINT_METRICS:-}" | summarize_metric "send_unlock" "client" "Send unlock   "
    echo "${ENDPOINT_METRICS:-}" | summarize_metric "server_gap"  "server" "Server gap    "
)
echo "--- Latency summary ---"
echo "$METRICS_SUMMARY"
echo "-----------------------"

if echo "$METRICS_SUMMARY" | grep -q "clientnic TTFB.*n=[1-9]"; then
    pass "Metrics: ClientNIC in-app TTFB samples collected"
else
    warn "Metrics: no ClientNIC in-app TTFB samples (binary may predate instrumentation)"
fi
if echo "$METRICS_SUMMARY" | grep -q "servernic TTFB.*n=[1-9]"; then
    pass "Metrics: ServerNIC in-app TTFB samples collected"
else
    warn "Metrics: no ServerNIC in-app TTFB samples (binary may predate instrumentation)"
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

{
    echo "# Integration Test Report — $(date +%Y-%m-%d)"
    echo ""
    echo "**Implementation**: DPDK (T8 ISN ack-num translation shift)"
    echo "**ClientNIC binary**: \`clientnic/dpdk-forwarder/\` (transparent forwarder + V-stamp)"
    echo "**ServerNIC binary**: \`servernic/dpdk/\` (full translator)"
    echo "**Experiment script**: \`experiments/dpdk/run_experiment.sh\`"
    echo "**Node scripts**: \`experiments/dpdk/\` (clientnic/servernic), \`experiments/nodes/\` (client/server)"
    echo "**Overall result**: $OVERALL_RESULT"
    echo ""
    echo "## Latency Summary (TTFB @ 3 points + FCT)"
    echo ""
    echo '```'
    echo "$METRICS_SUMMARY"
    echo '```'
    echo ""
    echo "## Client Output"
    echo ""
    echo '```'
    echo "$CLIENT_STDOUT"
    echo '```'
    echo ""
    echo "## ClientNIC Log (0-RTT activity)"
    echo ""
    echo '```'
    echo "$CLIENTNIC_LOG" | tail -50
    echo '```'
    echo ""
    echo "## ServerNIC Log"
    echo ""
    echo '```'
    echo "$SERVERNIC_LOG" | tail -30
    echo '```'
    echo ""
    echo "## Server Log"
    echo ""
    echo '```'
    echo "$SERVER_LOG" | tail -20
    echo '```'
    echo ""
    echo "## Packet Analysis"
    echo ""
    echo '```'
    echo "$ANALYSIS_STDOUT"
    echo '```'
} > "$REPORT_FILE"

log "Report saved to $REPORT_FILE"

exit "$FAILURES"
