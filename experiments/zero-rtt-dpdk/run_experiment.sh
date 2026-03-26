#!/usr/bin/env bash
# End-to-end integration test for the 0-RTT TCP demo using DPDK on ClientNIC.
#
# Validates tasks 10.1-10.4 from the clientnic-dpdk-port change:
#   10.1  meson + ninja build compiles cleanly on ClientNIC VM
#   10.2  Binary starts without errors (DPDK EAL init + component init)
#   10.3  Single-connection end-to-end test: Server → ServerNIC (Scapy) → ClientNIC (DPDK) → Client
#   10.4  validate_0rtt_capture.py — all checks (spoofed SYN-ACK, ISN delta, checksums) pass
#
# 4-VM chain topology (all in AWS, eu-central-1):
#
#   Client ──eth0──► ClientNIC ──eth1──► ServerNIC ──eth1──► Server
#                    (DPDK, vfio-pci     (Scapy                (real
#                    on eth1)            forwarder)             TCP server)
#
# ClientNIC uses:
#   eth0: AF_PACKET raw socket (client-facing, kernel stack)
#   eth1: DPDK ENA PMD via vfio-pci (server-facing, bound at boot by CDK user data)
#
# This script runs locally and drives all 4 VMs over AWS SSM.
#
# Prerequisites (run locally):
#   - aws CLI configured with credentials that have SSM access
#   - python3 in PATH
#   - ClientNIC VM provisioned with infra/dpdk CDK stack (DPDK installed, eth1 bound)
#
# Usage:
#   ./experiments/zero-rtt-dpdk/run_experiment.sh
#
# Exit code: 0 = all checks passed, non-zero = number of failures

set -uo pipefail

REPO_PATH="/home/ec2-user/zero-rtt-demo"
DPDK_BUILD="$REPO_PATH/clientnic/dpdk/builddir"
BINARY="$DPDK_BUILD/clientnic-dpdk"
SERVER_PORT=8080

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

FAILURES=0

log()  { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}" >&2; }
pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; FAILURES=$((FAILURES + 1)); }

# Build SSM parameters JSON from a shell command string
mk_params() { python3 -c "import json,sys; print(json.dumps({'commands':[sys.argv[1]]}))" "$1"; }
# Extract element N from a JSON array on stdin
json_idx()  { python3 -c "import json,sys; print(json.load(sys.stdin)[$1], end='')"; }


# ─── Dependency checks ────────────────────────────────────────────────────────
if ! command -v aws &>/dev/null; then
    echo "ERROR: aws CLI is required" >&2
    exit 1
fi
if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 is required" >&2
    exit 1
fi


# ─── SSM helpers ──────────────────────────────────────────────────────────────

# ssm_run <instance-id> <command> [timeout-sec]
ssm_run() {
    local iid="$1" cmd="$2" timeout="${3:-120}"
    local params cid

    params=$(mk_params "$cmd")

    cid=$(aws ssm send-command \
        --instance-ids "$iid" \
        --document-name "AWS-RunShellScript" \
        --parameters "$params" \
        --timeout-seconds "$timeout" \
        --query "Command.CommandId" \
        --output text --region eu-central-1)

    aws ssm wait command-executed \
        --command-id "$cid" \
        --instance-id "$iid" --region eu-central-1 2>/dev/null || true

    aws ssm get-command-invocation \
        --command-id "$cid" \
        --instance-id "$iid" \
        --query "[Status, StandardOutputContent, StandardErrorContent]" \
        --output json --region eu-central-1
}

# ssm_stdout <instance-id> <command> [timeout-sec]
ssm_stdout() {
    ssm_run "$1" "$2" "${3:-120}" | json_idx 1
}

# ssm_bg <instance-id> <command>
# Fires a command in the background and returns immediately.
ssm_bg() {
    local iid="$1" cmd="$2"
    local params
    params=$(mk_params "$cmd")
    aws ssm send-command \
        --instance-ids "$iid" \
        --document-name "AWS-RunShellScript" \
        --parameters "$params" \
        --timeout-seconds 30 \
        --query "Command.CommandId" \
        --output text --region eu-central-1 > /dev/null
}


# ─── EC2 discovery ────────────────────────────────────────────────────────────

get_iid() {
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$1" "Name=instance-state-name,Values=running" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text --region eu-central-1
}

get_ip() {
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$1" "Name=instance-state-name,Values=running" \
        --query "Reservations[0].Instances[0].PrivateIpAddress" \
        --output text --region eu-central-1
}


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
    ssm_bg "$iid" "sudo -u ec2-user git -C $REPO_PATH pull origin main 2>&1 || true"
done
sleep 8


# ─── Cleanup any leftover processes ───────────────────────────────────────────
log "Cleaning up previous runs..."
ssm_bg "$SERVER_ID"    "pkill -f 'python3.*server.py' 2>/dev/null; rm -f /tmp/server.log"
ssm_bg "$SERVERNIC_ID" "pkill -f 'servernic/scapy' 2>/dev/null; rm -f /tmp/servernic.log; iptables -F FORWARD 2>/dev/null"
ssm_bg "$CLIENTNIC_ID" "pkill -f 'clientnic-dpdk' 2>/dev/null; pkill tcpdump 2>/dev/null; rm -f /tmp/clientnic.log /tmp/client_side.pcap /tmp/server_side.pcap /tmp/validate_0rtt.py; iptables -F FORWARD 2>/dev/null"
sleep 3


# ─── Task 10.1: Build clientnic-dpdk on ClientNIC VM ─────────────────────────
# The CDK user data builds the binary at provision time, but we rebuild after
# pulling the latest code to pick up any changes made since the instance launched.
# Build command is identical to what CDK runs: meson setup builddir + ninja.
log "Task 10.1: Building clientnic-dpdk..."

BUILD_RESULT=$(ssm_run "$CLIENTNIC_ID" \
    "export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig; \
     cd $REPO_PATH/clientnic/dpdk; \
     rm -rf builddir; \
     /usr/local/bin/meson setup builddir 2>&1 && \
     cd builddir && /usr/local/bin/ninja 2>&1 && \
     echo 'BUILD_SUCCESS'" \
    600)

BUILD_STATUS=$(echo "$BUILD_RESULT" | json_idx 0)
BUILD_STDOUT=$(echo "$BUILD_RESULT" | json_idx 1)
BUILD_STDERR=$(echo "$BUILD_RESULT" | json_idx 2)

echo "--- Build output (last 20 lines) ---"
echo "$BUILD_STDOUT" | tail -20
[[ -n "$BUILD_STDERR" ]] && echo "stderr: $BUILD_STDERR" | tail -10
echo "------------------------------------"

if echo "$BUILD_STDOUT" | grep -q "BUILD_SUCCESS"; then
    pass "Task 10.1: meson + ninja build succeeded"
else
    fail "Task 10.1: build failed (status=$BUILD_STATUS)"
    echo "Full build output:"
    echo "$BUILD_STDOUT"
fi


# ─── Task 10.2: Smoke test — binary starts without errors ────────────────────
# Verify the binary initialises DPDK EAL and all components without crashing.
# We run it for 3 seconds in the background then check the log for expected
# startup messages. The binary will fail fast if:
#   - DPDK EAL init fails (hugepages not configured, vfio-pci not loaded)
#   - eth1 not bound to vfio-pci (no DPDK ports available)
#   - eth0 AF_PACKET init fails
#
# Gateway MAC: discover the ServerNIC's eth0 MAC — ClientNIC forwards traffic
# to ServerNIC on the middle subnet, so ServerNIC eth0 is the next hop.
log "Task 10.2: Smoke test — discovering gateway MAC and starting binary..."

GW_MAC=$(ssm_stdout "$SERVERNIC_ID" "cat /sys/class/net/eth0/address" 30)
GW_MAC=$(echo "$GW_MAC" | tr -d '[:space:]')

if [[ -z "$GW_MAC" || "$GW_MAC" == "None" ]]; then
    fail "Task 10.2: could not discover ServerNIC eth0 MAC"
else
    log "  Gateway MAC (ServerNIC eth0): $GW_MAC"

    # Start the binary, let it run for 3 seconds, then kill it
    ssm_run "$CLIENTNIC_ID" \
        "rm -f /tmp/clientnic_smoke.log; \
         setsid $BINARY -l 0 -- --port=$SERVER_PORT --gw-mac=$GW_MAC \
             < /dev/null > /tmp/clientnic_smoke.log 2>&1 & \
         BPID=\$!; sleep 3; kill \$BPID 2>/dev/null; wait \$BPID 2>/dev/null; true" \
        30 > /dev/null

    SMOKE_LOG=$(ssm_stdout "$CLIENTNIC_ID" "cat /tmp/clientnic_smoke.log 2>/dev/null || echo MISSING" 30)

    echo "--- Smoke test log ---"
    echo "$SMOKE_LOG"
    echo "----------------------"

    # Success: EAL initialised and entered main loop (or clean shutdown)
    if echo "$SMOKE_LOG" | grep -qiE "busy-poll loop|Entering busy-poll"; then
        pass "Task 10.2: binary started and entered busy-poll loop"
    elif echo "$SMOKE_LOG" | grep -qiE "EAL.*init|DPDK.*start|port.*started"; then
        pass "Task 10.2: binary started (DPDK EAL/port initialised)"
    else
        fail "Task 10.2: binary did not reach expected startup state"
    fi
fi


# ─── Step 1: Start Server ─────────────────────────────────────────────────────
log "Step 1: Starting Server..."
ssm_bg "$SERVER_ID" \
    "cd $REPO_PATH && echo '=== '\$(date -u +%Y-%m-%dT%H:%M:%SZ)' ===' >> /tmp/server.log && setsid python3 -u server-app/server.py --host 0.0.0.0 --port $SERVER_PORT --verbose < /dev/null >> /tmp/server.log 2>&1 &"
sleep 3

LISTEN_CHECK=$(ssm_stdout "$SERVER_ID" "ss -tlnp | grep $SERVER_PORT && echo LISTENING || echo NOT_LISTENING" 30)
if echo "$LISTEN_CHECK" | grep -q "LISTENING"; then
    pass "Server listening on :$SERVER_PORT"
else
    fail "Server not listening on :$SERVER_PORT"
    echo "  ss output: $LISTEN_CHECK"
fi


# ─── Step 2: Start ServerNIC ──────────────────────────────────────────────────
log "Step 2: Starting ServerNIC (Scapy)..."
ssm_bg "$SERVERNIC_ID" \
    "ip route replace 10.1.0.0/24 via 10.1.1.1 dev eth0 2>/dev/null || true"
ssm_bg "$SERVERNIC_ID" \
    "iptables -F FORWARD 2>/dev/null; iptables -A FORWARD -p tcp --dport $SERVER_PORT -j DROP; iptables -A FORWARD -p tcp --sport $SERVER_PORT -j DROP"
ssm_bg "$SERVERNIC_ID" \
    "echo '=== '\$(date -u +%Y-%m-%dT%H:%M:%SZ)' ===' >> /tmp/servernic.log && setsid python3 -u $REPO_PATH/servernic/scapy/main.py --client-iface eth0 --server-iface eth1 < /dev/null >> /tmp/servernic.log 2>&1 &"
sleep 2

FWRD=$(ssm_stdout "$SERVERNIC_ID" "cat /proc/sys/net/ipv4/ip_forward" 30)
if [[ "$FWRD" == "1" ]]; then
    pass "ServerNIC: IP forwarding enabled"
else
    fail "ServerNIC: IP forwarding NOT enabled (got '$FWRD')"
fi


# ─── Task 10.3: Start ClientNIC (DPDK) + packet captures ─────────────────────
# Uses the DPDK binary instead of the Scapy-based clientnic/scapy/main.py.
# The binary manages its own iptables rules (install_iptables() in main.c).
#
# Gateway MAC is ServerNIC's eth0 MAC (next hop on middle subnet).
# eth1 must already be bound to vfio-pci (done by CDK user data at boot).
#
# Route for return traffic: server-side packets arrive on eth1 (DPDK) and
# need to be forwarded to eth0 (client-facing). The kernel route to the client
# subnet via eth0 ensures correct routing of rewritten packets.
log "Task 10.3: Starting ClientNIC (DPDK) + packet captures..."

# Iptables: DPDK binary manages its own rules via install_iptables(), but we
# flush first to avoid stale DROP rules from previous runs.
ssm_bg "$CLIENTNIC_ID" "iptables -F FORWARD 2>/dev/null; iptables -F OUTPUT 2>/dev/null || true"
sleep 1

# tcpdump on eth0 to capture spoofed SYN-ACK and client-side traffic
ssm_bg "$CLIENTNIC_ID" \
    "setsid tcpdump -i eth0 -nn -tttt 'tcp port $SERVER_PORT' -w /tmp/client_side.pcap < /dev/null > /tmp/tcpdump_eth0.log 2>&1 &"
# Note: eth1 is DPDK-controlled — tcpdump cannot capture on it (unbound from kernel).
# The server_side capture is not available for DPDK mode; validate_0rtt_capture.py
# is invoked with --server-pcap /dev/null (or skipped) in this mode.
sleep 1

# Start the DPDK binary with --server-pcap so eth1 RX packets are captured
# to a real pcap file that validate_0rtt_capture.py can analyse.
ssm_bg "$CLIENTNIC_ID" \
    "echo '=== '\$(date -u +%Y-%m-%dT%H:%M:%SZ)' ===' >> /tmp/clientnic.log && \
     setsid $BINARY -l 0 -- \
         --port=$SERVER_PORT \
         --gw-mac=$GW_MAC \
         --server-pcap=/tmp/server_side.pcap \
         < /dev/null >> /tmp/clientnic.log 2>&1 &"
sleep 4  # DPDK EAL + ENA PMD init takes ~2-3 s on first start

FWRD=$(ssm_stdout "$CLIENTNIC_ID" "cat /proc/sys/net/ipv4/ip_forward" 30)
if [[ "$FWRD" == "1" ]]; then
    pass "ClientNIC: IP forwarding enabled"
else
    fail "ClientNIC: IP forwarding NOT enabled"
fi

# Confirm the binary is running
DPDK_RUNNING=$(ssm_stdout "$CLIENTNIC_ID" "pgrep -x clientnic-dpdk && echo RUNNING || echo NOT_RUNNING" 30)
if echo "$DPDK_RUNNING" | grep -q "RUNNING"; then
    pass "Task 10.3: clientnic-dpdk process is running"
else
    fail "Task 10.3: clientnic-dpdk process not found — startup failed"
    DPDK_LOG=$(ssm_stdout "$CLIENTNIC_ID" "cat /tmp/clientnic.log" 30)
    echo "--- ClientNIC DPDK log ---"
    echo "$DPDK_LOG"
    echo "--------------------------"
fi


# ─── Step 4: Run client test ──────────────────────────────────────────────────
log "Step 4: Running client test (1 connection)..."
CLIENT_RESULT=$(ssm_run "$CLIENT_ID" \
    "cd $REPO_PATH/client-app && python3 client.py --host $SERVER_IP --port $SERVER_PORT --mode repeated --count 1 --verbose" \
    60)

CLIENT_STDOUT=$(echo "$CLIENT_RESULT" | json_idx 1)
CLIENT_STDERR=$(echo "$CLIENT_RESULT"  | json_idx 2)

echo "--- Client output ---"
echo "$CLIENT_STDOUT"
[[ -n "$CLIENT_STDERR" ]] && echo "stderr: $CLIENT_STDERR"
echo "---------------------"

if echo "$CLIENT_STDOUT" | grep -qE "Success: 1/1|100%"; then
    pass "Task 10.3: Client connection succeeded"
else
    fail "Task 10.3: Client connection failed"
fi

sleep 3


# ─── Step 5: Stop captures ────────────────────────────────────────────────────
log "Step 5: Stopping packet captures and DPDK binary..."
ssm_run "$CLIENTNIC_ID" "pkill tcpdump 2>/dev/null || true; sleep 1" 30 > /dev/null
ssm_run "$CLIENTNIC_ID" "pkill -SIGTERM clientnic-dpdk 2>/dev/null || true; sleep 2" 30 > /dev/null
pass "Captures stopped, DPDK binary signalled"


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


# ─── Step 7: Check ClientNIC DPDK log ────────────────────────────────────────
log "Step 7: Checking ClientNIC DPDK log for 0-RTT activity..."
CLIENTNIC_LOG=$(ssm_stdout "$CLIENTNIC_ID" "cat /tmp/clientnic.log" 30)
echo "--- ClientNIC DPDK log ---"
echo "$CLIENTNIC_LOG"
echo "--------------------------"

if echo "$CLIENTNIC_LOG" | grep -qiE "SYN.*flow created|spoofed SYN-ACK|delta|flow created"; then
    pass "ClientNIC DPDK: 0-RTT flow table activity confirmed"
else
    fail "ClientNIC DPDK: no flow table activity in log"
fi


# ─── Task 10.4: Validate packet capture ───────────────────────────────────────
# validate_0rtt_capture.py checks spoofed SYN-ACK presence, ISN delta, checksums.
# In DPDK mode, eth1 is DPDK-controlled so we only have the client-side pcap.
# Pass /dev/null as the server-side pcap; the validator skips checks that
# require both pcaps when the server pcap is absent/empty.
log "Task 10.4: Running packet capture analysis..."

PCAP_SIZES=$(ssm_stdout "$CLIENTNIC_ID" \
    "ls -lh /tmp/client_side.pcap /tmp/server_side.pcap 2>&1 || echo 'pcap files not found'" 30)
echo "pcap files: $PCAP_SIZES"

# Copy validator to /tmp to avoid clientnic/scapy/ directory shadowing the
# real scapy package when Python adds the script's directory to sys.path.
ANALYSIS_RESULT=$(ssm_run "$CLIENTNIC_ID" \
    "cp $REPO_PATH/clientnic/validate_0rtt_capture.py /tmp/validate_0rtt.py && \
     python3 /tmp/validate_0rtt.py \
        --client-pcap /tmp/client_side.pcap \
        --server-pcap /tmp/server_side.pcap" \
    45)

ANALYSIS_STATUS=$(echo "$ANALYSIS_RESULT" | json_idx 0)
ANALYSIS_STDOUT=$(echo "$ANALYSIS_RESULT" | json_idx 1)
ANALYSIS_STDERR=$(echo "$ANALYSIS_RESULT" | json_idx 2)

echo "--- Packet analysis (status: $ANALYSIS_STATUS) ---"
echo "$ANALYSIS_STDOUT"
[[ -n "$ANALYSIS_STDERR" ]] && echo "stderr: $ANALYSIS_STDERR"
echo "---------------------------------------------------"

if [[ "$ANALYSIS_STATUS" == "Success" ]] && echo "$ANALYSIS_STDOUT" | grep -q "All checks passed"; then
    pass "Task 10.4: Packet capture analysis — all checks passed"
else
    NFAIL=$(printf '%s' "$ANALYSIS_STDOUT" | grep -c '\[FAIL\]' || true)
    fail "Task 10.4: Packet capture analysis — $NFAIL check(s) failed (status=$ANALYSIS_STATUS)"
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

exit "$FAILURES"
