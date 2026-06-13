#!/usr/bin/env bash
# Baseline TCP experiment — plain kernel forwarding, no 0-RTT middleware.
#
# Uses the infra/baseline CDK stack (BaselineStack):
#   baseline-client → baseline-clientnic → baseline-servernic → baseline-server
#
# ClientNIC and ServerNIC are plain IP routers (ip_forward=1, static cross-subnet
# routes configured at boot).  No DPDK, no Scapy, no vfio-pci.
#
# Purpose: measure plain-TCP TTFB for comparison with the 0-RTT experiment.
#
# Prerequisites:
#   - aws CLI configured with SSM + EC2 describe access
#   - python3 in PATH
#   - infra/baseline CDK stack deployed (.\infra\baseline\deploy.ps1)
#
# Usage:
#   ./experiments/baseline-tcp/run_experiment.sh
#
# Exit code: 0 = all checks passed, non-zero = number of failures

set -uo pipefail

export PYTHONUTF8=1
export PYTHONIOENCODING=utf-8

# shellcheck source=../utils/ssm.sh
source "$(dirname "$0")/../utils/ssm.sh"
# shellcheck source=../utils/measure.sh
source "$(dirname "$0")/../utils/measure.sh"

REPO_PATH="/home/ec2-user/zero-rtt-demo"
SERVER_PORT=8080
# Override via env: CONNECTIONS=50 ./run_experiment.sh
BASELINE_CONNECTIONS="${CONNECTIONS:-20}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

FAILURES=0

log()  { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}" >&2; }
pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; FAILURES=$((FAILURES + 1)); }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }


# ─── Step 0: Discover instances ───────────────────────────────────────────────
log "Step 0: Discovering baseline EC2 instances..."

SERVER_ID=$(get_iid "baseline-server")
SERVERNIC_ID=$(get_iid "baseline-servernic")
CLIENTNIC_ID=$(get_iid "baseline-clientnic")
CLIENT_ID=$(get_iid "baseline-client")
SERVER_IP=$(get_ip "baseline-server")

log "  Server:    $SERVER_ID  ($SERVER_IP)"
log "  ServerNIC: $SERVERNIC_ID"
log "  ClientNIC: $CLIENTNIC_ID"
log "  Client:    $CLIENT_ID"

for var in SERVER_ID SERVERNIC_ID CLIENTNIC_ID CLIENT_ID SERVER_IP; do
    val="${!var}"
    if [[ -z "$val" || "$val" == "None" ]]; then
        echo -e "${RED}ERROR: could not find running instance for $var${NC}" >&2
        echo "  Deploy infra/baseline first: cd infra/baseline && ./deploy.ps1" >&2
        exit 1
    fi
done


# ─── Pull latest code ─────────────────────────────────────────────────────────
log "Pulling latest code on all VMs..."
for iid in "$SERVER_ID" "$SERVERNIC_ID" "$CLIENTNIC_ID" "$CLIENT_ID"; do
    ssm_bg "$iid" "git config --global --add safe.directory $REPO_PATH 2>/dev/null || true; sudo -u ec2-user git -C $REPO_PATH pull origin main 2>&1 || true"
done
sleep 5


# ─── Step 1: Pre-flight checks on NIC VMs ────────────────────────────────────
log "Step 1: Pre-flight — verifying IP forwarding and routes on NIC VMs..."

CLIENTNIC_FWD=$(ssm_stdout "$CLIENTNIC_ID" "cat /proc/sys/net/ipv4/ip_forward" 30)
SERVERNIC_FWD=$(ssm_stdout "$SERVERNIC_ID"  "cat /proc/sys/net/ipv4/ip_forward" 30)

[[ "$CLIENTNIC_FWD" == "1" ]] && pass "ClientNIC: IP forwarding enabled" \
    || { fail "ClientNIC: IP forwarding NOT enabled — ensure infra/baseline deploy completed"; }
[[ "$SERVERNIC_FWD" == "1" ]] && pass "ServerNIC: IP forwarding enabled" \
    || { fail "ServerNIC: IP forwarding NOT enabled — ensure infra/baseline deploy completed"; }

CLIENTNIC_ROUTE=$(ssm_stdout "$CLIENTNIC_ID" "ip route show 10.1.2.0/24 2>/dev/null || echo MISSING" 30)
SERVERNIC_ROUTE=$(ssm_stdout "$SERVERNIC_ID"  "ip route show 10.1.0.0/24 2>/dev/null || echo MISSING" 30)

if echo "$CLIENTNIC_ROUTE" | grep -q "10.1.2.0/24"; then
    pass "ClientNIC: static route to Server subnet present ($CLIENTNIC_ROUTE)"
else
    warn "ClientNIC: static route to 10.1.2.0/24 missing — adding now..."
    ssm_bg "$CLIENTNIC_ID" "ip route add 10.1.2.0/24 via 10.1.1.1 dev eth1 2>/dev/null || true"
fi

if echo "$SERVERNIC_ROUTE" | grep -q "10.1.0.0/24"; then
    pass "ServerNIC: static route to Client subnet present ($SERVERNIC_ROUTE)"
else
    warn "ServerNIC: static route to 10.1.0.0/24 missing — adding now..."
    ssm_bg "$SERVERNIC_ID" "ip route add 10.1.0.0/24 via 10.1.1.1 dev eth0 2>/dev/null || true"
fi
sleep 2


# ─── Step 2: Cleanup any leftover server processes ───────────────────────────
log "Step 2: Cleaning up any leftover server processes..."
ssm_bg "$SERVER_ID" "pkill -f 'iperf -s' 2>/dev/null; rm -f /tmp/server.log"
sleep 2


# ─── Step 3: Start Server ─────────────────────────────────────────────────────
log "Step 3: Starting Server..."
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


# ─── Step 4: Run baseline TTFB measurements ──────────────────────────────────
log "Step 4: Running baseline TTFB ($BASELINE_CONNECTIONS connections)..."
run_ttfb_measurement "$CLIENT_ID" "$SERVER_IP" "$SERVER_PORT" "$BASELINE_CONNECTIONS" "$REPO_PATH" 120 "Baseline TTFB"

# Aggregate client-side latency (no NIC data plane in baseline — kernel forwarding).
METRICS_SUMMARY=$(
    echo "$CLIENT_STDOUT" | summarize_metric "ttfb" "client" "Client TTFB"
    echo "$CLIENT_STDOUT" | summarize_metric "fct"  "client" "Client FCT "
)
echo "--- Latency summary ---"
echo "$METRICS_SUMMARY"
echo "-----------------------"


# ─── Step 5: Stop Server and collect logs ────────────────────────────────────
log "Step 5: Stopping Server and collecting logs..."
ssm_bg "$SERVER_ID" "pkill -f 'iperf -s' 2>/dev/null || true"
sleep 2

SERVER_LOG=$(ssm_stdout "$SERVER_ID" "cat /tmp/server.log" 30)
echo "--- Server log ---"
echo "$SERVER_LOG"
echo "------------------"

if echo "$SERVER_LOG" | grep -qiE "Accepted|bytes|connection"; then
    pass "Server received data from client"
else
    fail "Server log shows no received data"
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
REPORT_FILE="$REPORT_DIR/baseline-report-$(date +%Y-%m-%d-%H%M%S).md"

if [[ $FAILURES -eq 0 ]]; then OVERALL_RESULT="ALL PASSED ✅"; else OVERALL_RESULT="$FAILURES FAILURE(S) ❌"; fi

{
    echo "# Baseline TCP Report — $(date +%Y-%m-%d-%H%M%S)"
    echo ""
    echo "**Mode**: Plain TCP (no 0-RTT middleware)"
    echo "**Infra**: \`infra/baseline\` CDK stack (BaselineStack) — 4× t3.micro, kernel forwarding"
    echo "**Connections**: $BASELINE_CONNECTIONS sequential"
    echo "**Overall result**: $OVERALL_RESULT"
    echo ""
    echo "## Latency Summary (Client TTFB + FCT)"
    echo ""
    echo '```'
    echo "$METRICS_SUMMARY"
    echo '```'
    echo ""
    echo "## TTFB Measurements"
    echo ""
    echo '```'
    echo "$CLIENT_STDOUT"
    echo '```'
    echo ""
    echo "## Server Log"
    echo ""
    echo '```'
    echo "$SERVER_LOG" | tail -20
    echo '```'
    echo ""
    echo "## Notes"
    echo ""
    echo "- Traffic path: Client → ClientNIC (kernel forward) → ServerNIC (kernel forward) → Server"
    echo "- ClientNIC: ip_forward=1, static route 10.1.2.0/24 via 10.1.1.1 dev eth1"
    echo "- ServerNIC: ip_forward=1, static route 10.1.0.0/24 via 10.1.1.1 dev eth0"
    echo "- Compare TTFB min/mean/p99 against experiments/zero-rtt-dpdk/reports/ for 0-RTT benefit"
} > "$REPORT_FILE"

log "Report saved to $REPORT_FILE"

exit "$FAILURES"
