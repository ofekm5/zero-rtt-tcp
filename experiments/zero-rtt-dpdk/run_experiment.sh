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
EBPF_TRACE_DURATION=300   # seconds — covers full experiment including build skip

log()  { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}" >&2; }
pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; FAILURES=$((FAILURES + 1)); }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

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
    ssm_bg "$iid" "git config --global --add safe.directory $REPO_PATH 2>/dev/null || true; sudo -u ec2-user git -C $REPO_PATH pull origin main 2>&1 || true"
done
sleep 8


# ─── Cleanup any leftover processes ───────────────────────────────────────────
log "Cleaning up previous runs..."
ssm_bg "$SERVER_ID"    "pkill -f 'python3.*server.py' 2>/dev/null; rm -f /tmp/server.log"
ssm_bg "$SERVERNIC_ID" "pkill -f 'servernic/scapy' 2>/dev/null; rm -f /tmp/servernic.log; iptables -F FORWARD 2>/dev/null"
ssm_bg "$CLIENTNIC_ID" "pkill -f 'clientnic-dpdk' 2>/dev/null; pkill tcpdump 2>/dev/null; rm -f /tmp/clientnic.log /tmp/client_side.pcap /tmp/server_side.pcap /tmp/validate_0rtt.py; iptables -F FORWARD 2>/dev/null"
ssm_bg "$CLIENT_ID"   "pkill -f 'run_trace.sh' 2>/dev/null; pkill bpftrace 2>/dev/null; rm -f /tmp/tcp_trace_client.jsonl || true"
ssm_bg "$SERVER_ID"   "pkill -f 'run_trace.sh' 2>/dev/null; pkill bpftrace 2>/dev/null; rm -f /tmp/tcp_trace_server.jsonl || true"
sleep 3


# ─── Start eBPF traces on Client and Server VMs ───────────────────────────────
log "eBPF: Starting TCP state traces on Client and Server..."
TRACE_CMD="bash $REPO_PATH/observability/ebpf/run_trace.sh --duration $EBPF_TRACE_DURATION --port $SERVER_PORT"
ssm_bg "$CLIENT_ID" "setsid $TRACE_CMD --output /tmp/tcp_trace_client.jsonl < /dev/null > /tmp/ebpf_client.log 2>&1 &"
ssm_bg "$SERVER_ID" "setsid $TRACE_CMD --output /tmp/tcp_trace_server.jsonl < /dev/null > /tmp/ebpf_server.log 2>&1 &"
sleep 2  # allow bpftrace to attach before the experiment starts


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
log "Step 1: Starting Server via node script..."
ssm_bg "$SERVER_ID" \
    "setsid bash $REPO_PATH/experiments/zero-rtt-dpdk/nodes/server.sh < /dev/null >> /tmp/server.log 2>&1 &"
sleep 3

LISTEN_CHECK=$(ssm_stdout "$SERVER_ID" "ss -tlnp | grep $SERVER_PORT && echo LISTENING || echo NOT_LISTENING" 30)
if echo "$LISTEN_CHECK" | grep -q "LISTENING"; then
    pass "Server listening on :$SERVER_PORT"
else
    fail "Server not listening on :$SERVER_PORT"
    echo "  ss output: $LISTEN_CHECK"
fi


# ─── Step 2: Start ServerNIC ──────────────────────────────────────────────────
# nodes/servernic.sh handles: route, iptables DROP for port 8080, ip_forward check, forwarder
log "Step 2: Starting ServerNIC via node script..."
ssm_bg "$SERVERNIC_ID" \
    "setsid bash $REPO_PATH/experiments/zero-rtt-dpdk/nodes/servernic.sh < /dev/null >> /tmp/servernic.log 2>&1 &"
sleep 3

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
log "Task 10.3: Starting ClientNIC (DPDK) via node script..."

# Flush any stale iptables DROP rules from the smoke test before the node script runs.
ssm_bg "$CLIENTNIC_ID" "iptables -F FORWARD 2>/dev/null; iptables -F OUTPUT 2>/dev/null || true"
sleep 1

# nodes/clientnic.sh handles: cleanup, build (skipped via SKIP_BUILD=1), GW MAC (passed
# as $1 — bypasses EC2 API call from VM), tcpdump on eth0, exec binary with --server-pcap.
# SKIP_BUILD=1 because meson+ninja already ran in Task 10.1.
ssm_bg "$CLIENTNIC_ID" \
    "SKIP_BUILD=1 setsid bash $REPO_PATH/experiments/zero-rtt-dpdk/nodes/clientnic.sh $GW_MAC < /dev/null >> /tmp/clientnic.log 2>&1 &"
sleep 5  # node script: cleanup + checks + tcpdump start + DPDK EAL + ENA PMD init (~3-4 s)

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

# Stop eBPF traces early (they'd self-terminate at EBPF_TRACE_DURATION but we stop now)
ssm_bg "$CLIENT_ID" "pkill bpftrace 2>/dev/null || true"
ssm_bg "$SERVER_ID" "pkill bpftrace 2>/dev/null || true"
sleep 2

# ─── Collect eBPF traces ──────────────────────────────────────────────────────
log "Collecting eBPF traces from Client and Server..."
EBPF_CLIENT_TRACE=$(ssm_stdout "$CLIENT_ID" "cat /tmp/tcp_trace_client.jsonl 2>/dev/null || echo ''" 30) || { warn "eBPF: could not collect Client trace"; EBPF_CLIENT_TRACE=""; }
EBPF_SERVER_TRACE=$(ssm_stdout "$SERVER_ID" "cat /tmp/tcp_trace_server.jsonl 2>/dev/null || echo ''" 30) || { warn "eBPF: could not collect Server trace"; EBPF_SERVER_TRACE=""; }

EBPF_CLIENT_COUNT=$(echo "$EBPF_CLIENT_TRACE" | grep -c '"ts_ns"' 2>/dev/null || echo 0)
EBPF_SERVER_COUNT=$(echo "$EBPF_SERVER_TRACE" | grep -c '"ts_ns"' 2>/dev/null || echo 0)
log "  eBPF events: client=$EBPF_CLIENT_COUNT server=$EBPF_SERVER_COUNT"


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
    echo "**Implementation**: DPDK"
    echo "**Experiment script**: \`experiments/zero-rtt-dpdk/run_experiment.sh\`"
    echo "**Node scripts**: \`experiments/zero-rtt-dpdk/nodes/\`"
    echo "**Overall result**: $OVERALL_RESULT"
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
    echo ""
    echo "## eBPF TCP Traces"
    echo ""
    echo "### Client VM — TCP State Transitions"
    echo ""
    if [[ -n "$EBPF_CLIENT_TRACE" && "$EBPF_CLIENT_COUNT" -gt 0 ]]; then
        echo '```json'
        echo "$EBPF_CLIENT_TRACE"
        echo '```'
    else
        echo "_No events captured (bpftrace unavailable or no matching connections)_"
    fi
    echo ""
    echo "### Server VM — TCP State Transitions"
    echo ""
    if [[ -n "$EBPF_SERVER_TRACE" && "$EBPF_SERVER_COUNT" -gt 0 ]]; then
        echo '```json'
        echo "$EBPF_SERVER_TRACE"
        echo '```'
    else
        echo "_No events captured (bpftrace unavailable or no matching connections)_"
    fi
} > "$REPORT_FILE"

log "Report saved to $REPORT_FILE"

exit "$FAILURES"
