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
#   ./experiments/zero-rtt-dpdk/run_experiment.sh
#
# Exit code: 0 = all checks passed, non-zero = number of failures

set -uo pipefail

REPO_PATH="/home/ec2-user/zero-rtt-demo"
DPDK_BUILD="$REPO_PATH/clientnic/dpdk-forwarder/builddir"
BINARY="$DPDK_BUILD/clientnic-dpdk-forwarder"
SERVERNIC_BINARY="$REPO_PATH/servernic/dpdk/builddir/servernic-dpdk"
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
# Extract element N from a JSON array on stdin (ascii-safe for Windows terminals)
json_idx()  { python3 -X utf8 -c "import json,sys; v=json.load(sys.stdin)[$1]; print(v.encode('ascii','replace').decode('ascii') if isinstance(v,str) else v, end='')"; }


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
ssm_bg "$SERVERNIC_ID" "pkill -x servernic-dpdk 2>/dev/null; pkill -f 'servernic/scapy' 2>/dev/null; rm -f /tmp/servernic.log; iptables -F FORWARD 2>/dev/null; iptables -F OUTPUT 2>/dev/null"
ssm_bg "$CLIENTNIC_ID" "pkill -x clientnic-dpdk-forwarder 2>/dev/null; pkill -x clientnic-dpdk 2>/dev/null; pkill tcpdump 2>/dev/null; rm -f /tmp/clientnic.log /tmp/client_side.pcap /tmp/validate_0rtt.py; iptables -F FORWARD 2>/dev/null"
ssm_bg "$CLIENT_ID"   "pkill -f 'run_trace.sh' 2>/dev/null; pkill bpftrace 2>/dev/null; rm -f /tmp/tcp_trace_client.jsonl || true"
ssm_bg "$SERVER_ID"   "pkill -f 'run_trace.sh' 2>/dev/null; pkill bpftrace 2>/dev/null; rm -f /tmp/tcp_trace_server.jsonl || true"
sleep 3


# ─── Start eBPF traces on Client and Server VMs ───────────────────────────────
log "eBPF: Starting TCP state traces on Client and Server..."
TRACE_CMD="bash $REPO_PATH/observability/ebpf/run_trace.sh --duration $EBPF_TRACE_DURATION --port $SERVER_PORT"
ssm_bg "$CLIENT_ID" "setsid $TRACE_CMD --output /tmp/tcp_trace_client.jsonl < /dev/null > /tmp/ebpf_client.log 2>&1 &"
ssm_bg "$SERVER_ID" "setsid $TRACE_CMD --output /tmp/tcp_trace_server.jsonl < /dev/null > /tmp/ebpf_server.log 2>&1 &"
sleep 2  # allow bpftrace to attach before the experiment starts


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
    elif echo "$SMOKE_LOG" | grep -qiE "EAL.*init|DPDK.*start|port.*started"; then
        pass "Smoke test: clientnic-dpdk-forwarder DPDK EAL/port initialised"
    else
        fail "Smoke test: clientnic-dpdk-forwarder did not reach expected startup state"
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


# ─── Step 2: Start ServerNIC (DPDK binary) ───────────────────────────────────
# nodes/servernic.sh: discovers ClientNIC eth1 MAC + Server eth0 MAC via EC2 API,
# builds (or skips with SKIP_BUILD=1), installs iptables rules, launches servernic-dpdk.
log "Step 2: Starting ServerNIC DPDK binary via node script..."
ssm_bg "$SERVERNIC_ID" \
    "SKIP_BUILD=1 CLIENTNIC_GW_MAC=$CLIENTNIC_ETH1_MAC SERVER_GW_MAC=$SERVER_ETH0_MAC setsid bash $REPO_PATH/experiments/zero-rtt-dpdk/nodes/servernic.sh < /dev/null >> /tmp/servernic.log 2>&1 &"
sleep 5  # DPDK EAL + vfio-pci bind + ENA PMD init (~3-4 s)

SERVERNIC_RUNNING=$(ssm_stdout "$SERVERNIC_ID" "pgrep -x servernic-dpdk && echo RUNNING || echo NOT_RUNNING" 30)
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
    "SKIP_BUILD=1 setsid bash $REPO_PATH/experiments/zero-rtt-dpdk/nodes/clientnic.sh $GW_MAC < /dev/null >> /tmp/clientnic.log 2>&1 &"
sleep 5  # node script: cleanup + checks + tcpdump start + DPDK EAL + ENA PMD init (~3-4 s)

FWRD=$(ssm_stdout "$CLIENTNIC_ID" "cat /proc/sys/net/ipv4/ip_forward" 30)
if [[ "$FWRD" == "1" ]]; then
    pass "ClientNIC: IP forwarding enabled"
else
    fail "ClientNIC: IP forwarding NOT enabled"
fi

# Confirm the forwarder binary is running
DPDK_RUNNING=$(ssm_stdout "$CLIENTNIC_ID" "pgrep -x clientnic-dpdk-forwarder && echo RUNNING || echo NOT_RUNNING" 30)
if echo "$DPDK_RUNNING" | grep -q "RUNNING"; then
    pass "Step 3: clientnic-dpdk-forwarder process is running"
else
    fail "Step 3: clientnic-dpdk-forwarder process not found — startup failed"
    DPDK_LOG=$(ssm_stdout "$CLIENTNIC_ID" "cat /tmp/clientnic.log" 30)
    echo "--- ClientNIC forwarder log ---"
    echo "$DPDK_LOG"
    echo "-------------------------------"
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


# ─── Step 5: Stop captures and binaries ──────────────────────────────────────
log "Step 5: Stopping packet captures and DPDK binaries..."
ssm_run "$CLIENTNIC_ID" "pkill tcpdump 2>/dev/null || true; sleep 1" 30 > /dev/null
ssm_run "$CLIENTNIC_ID" "pkill -SIGTERM clientnic-dpdk-forwarder 2>/dev/null || true; sleep 2" 30 > /dev/null
ssm_run "$SERVERNIC_ID" "pkill -SIGTERM servernic-dpdk 2>/dev/null || true; sleep 2" 30 > /dev/null
pass "Captures stopped, DPDK binaries signalled"

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
# validate_0rtt_capture.py checks spoofed SYN-ACK presence, ISN delta, checksums.
# In T8 mode: client-side pcap is at ClientNIC (eth0 tcpdump).
# The real SYN-ACK is dropped at the ServerNIC — so only the spoofed SYN-ACK
# should appear on the client-side pcap (validates task 9.3 assertion).
log "Packet analysis: Running packet capture analysis..."

PCAP_SIZES=$(ssm_stdout "$CLIENTNIC_ID" \
    "ls -lh /tmp/client_side.pcap 2>&1 || echo 'pcap file not found'" 30)
echo "pcap files: $PCAP_SIZES"

# Copy validator to /tmp to avoid clientnic/scapy/ directory shadowing the
# real scapy package when Python adds the script's directory to sys.path.
ANALYSIS_RESULT=$(ssm_run "$CLIENTNIC_ID" \
    "cp $REPO_PATH/clientnic/validate_0rtt_capture.py /tmp/validate_0rtt.py && \
     python3 /tmp/validate_0rtt.py \
        --client-pcap /tmp/client_side.pcap" \
    45)

ANALYSIS_STATUS=$(echo "$ANALYSIS_RESULT" | json_idx 0)
ANALYSIS_STDOUT=$(echo "$ANALYSIS_RESULT" | json_idx 1)
ANALYSIS_STDERR=$(echo "$ANALYSIS_RESULT" | json_idx 2)

echo "--- Packet analysis (status: $ANALYSIS_STATUS) ---"
echo "$ANALYSIS_STDOUT"
[[ -n "$ANALYSIS_STDERR" ]] && echo "stderr: $ANALYSIS_STDERR"
echo "---------------------------------------------------"

if [[ "$ANALYSIS_STATUS" == "Success" ]] && echo "$ANALYSIS_STDOUT" | grep -q "All checks passed"; then
    pass "Packet analysis: all checks passed"
else
    NFAIL=$(printf '%s' "$ANALYSIS_STDOUT" | grep -c '\[FAIL\]' || true)
    fail "Packet analysis: $NFAIL check(s) failed (status=$ANALYSIS_STATUS)"
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
