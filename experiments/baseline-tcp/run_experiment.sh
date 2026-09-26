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

# shellcheck source=../lib/transport/ssm.sh
source "$(dirname "$0")/../lib/transport/ssm.sh"
# shellcheck source=../lib/measure.sh
source "$(dirname "$0")/../lib/measure.sh"
# shellcheck source=../lib/endpoint.sh
source "$(dirname "$0")/../lib/endpoint.sh"

REPO_PATH="/home/ec2-user/zero-rtt-tcp"
SERVER_PORT=8080

# Transport shims — endpoint.sh is written against the generic remote_* names so
# the same code drives this stack and the 0-RTT stack (run_core.sh).
remote_run()    { ssm_run    "$@"; }
remote_bg()     { ssm_bg     "$@"; }
remote_stdout() { ssm_stdout "$@"; }
REMOTE_OUTPUT_CAP=24000
# Number of measurement ROUNDS (each round opens LOAD_PARALLEL connections across
# LOAD_PORTS ports — see measure.sh). Default 1 round of 100000 parallel conns.
# Override rounds via env: CONNECTIONS=5 ./run_experiment.sh
BASELINE_CONNECTIONS="${CONNECTIONS:-1}"

# shellcheck source=../lib/output.sh
source "$(dirname "$0")/../lib/output.sh"
# shellcheck source=../lib/report.sh
source "$(dirname "$0")/../lib/report.sh"

FAILURES=0


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
# REPO_REF defaults to main; must match whatever the 0-RTT run used, or the two
# stacks are running different harness code and the comparison is meaningless.
# Hard reset rather than pull: a merge conflict from VM-local drift would leave
# the node on unknown code with only a swallowed error to show for it.
REPO_REF="${REPO_REF:-main}"
log "Syncing all VMs to origin/${REPO_REF}..."
[[ "$REPO_REF" != "main" ]] && warn "REPO_REF=${REPO_REF} — VMs are running a NON-MAIN ref"
# Clone-on-demand, mirroring run_core.sh. The baseline CDK user-data clone uses
# a token that has expired — cloud-init logged "Invalid username or token" and
# left every baseline VM with no repo at all, which no amount of `git fetch`
# recovers from. Re-clone here with the PAT from Secrets Manager so the run is
# self-healing on an already-deployed stack.
for iid in "$SERVER_ID" "$SERVERNIC_ID" "$CLIENTNIC_ID" "$CLIENT_ID"; do
    ssm_bg "$iid" \
        "git config --global --add safe.directory $REPO_PATH 2>/dev/null || true; \
         if [ -d $REPO_PATH/.git ]; then \
             sudo -u ec2-user git -C $REPO_PATH fetch origin $REPO_REF 2>&1 && \
             sudo -u ec2-user git -C $REPO_PATH checkout -B $REPO_REF origin/$REPO_REF 2>&1 && \
             sudo -u ec2-user git -C $REPO_PATH reset --hard origin/$REPO_REF 2>&1 || true; \
         else \
             GITHUB_TOKEN=\$(aws secretsmanager get-secret-value --secret-id zero-rtt/github-token --query SecretString --output text --region eu-central-1 | tr -d '\"[:space:]'); \
             sudo -u ec2-user git clone \"https://x-access-token:\${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-tcp.git\" $REPO_PATH 2>&1 || true; \
             sudo -u ec2-user git -C $REPO_PATH checkout $REPO_REF 2>&1 || true; \
             chown -R ec2-user:ec2-user $REPO_PATH 2>/dev/null || true; \
         fi"
done
sleep 30

# `git rev-parse` as root refuses an ec2-user-owned repo ("dubious ownership"),
# so pass safe.directory inline — otherwise a perfectly good checkout reports
# NOREPO and the run looks broken when it is not.
for iid in "$SERVER_ID" "$SERVERNIC_ID" "$CLIENTNIC_ID" "$CLIENT_ID"; do
    log "  $iid HEAD: $(ssm_stdout "$iid" "git -c safe.directory=$REPO_PATH -C $REPO_PATH rev-parse --short HEAD 2>/dev/null || echo NOREPO" 30 | tr -d '[:space:]')"
done


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
ssm_bg "$SERVER_ID" "pkill -f loadgen.py 2>/dev/null; rm -f /tmp/server.log"
sleep 2


# ─── Step 2b: Endpoint tuning — identical to the 0-RTT stack ─────────────────
# The whole point of this run is to be compared against experiments/dpdk. Any
# endpoint parameter that differs between the two — emulated RTT, offloads, MTU,
# TCP options, kernel limits — becomes a confound indistinguishable from 0-RTT
# benefit or cost. endpoint_tune() is the same function run_core.sh calls.
endpoint_tune "$CLIENT_ID" "$SERVER_ID"


# ─── Step 2c: Emulated WAN on the middle leg ─────────────────────────────────
# roadmap.md F2 / measurement-methodology-review.md §E. This stack's NIC VMs are
# plain kernel routers, so `tc` reaches the middle leg directly; the DPDK stack
# gets the identical delay from --wan-delay-us inside both forwarders. The
# interfaces match the static routes asserted in Step 1: ClientNIC reaches the
# Middle subnet over eth1, ServerNIC over eth0.
wan_tune_middle_leg "$CLIENTNIC_ID" eth1 "$SERVERNIC_ID" eth0


# ─── Step 3: Start Server ─────────────────────────────────────────────────────
# SSM commands don't inherit this orchestrator's env, so pass LOAD_PORTS through
# explicitly — otherwise the remote server.sh falls back to its own default and may
# listen on a different port set than the client (measure.sh) dials into.
log "Step 3: Starting Server ($LOAD_PORTS load-generator port(s))..."
ssm_bg "$SERVER_ID" \
    "LOAD_PORTS=$LOAD_PORTS REPO_REF=$REPO_REF setsid bash $REPO_PATH/experiments/nodes/server.sh < /dev/null >> /tmp/server.log 2>&1 &"
sleep 3

LISTEN_CHECK=$(ssm_stdout "$SERVER_ID" "ss -tlnp | grep -q :$SERVER_PORT && echo LISTEN_OK || echo LISTEN_NONE" 30)
if echo "$LISTEN_CHECK" | grep -q "LISTEN_OK"; then
    pass "Server listening on :$SERVER_PORT"
else
    fail "Server not listening on :$SERVER_PORT"
    echo "  ss output: $LISTEN_CHECK"
fi


# ─── Step 3b: Start endpoint captures ────────────────────────────────────────
# Without these the baseline produces no send_unlock/FCT at all, and the 0-RTT
# claim — a *difference* between two stacks — has only one side measured.
PORT_HI=$(( SERVER_PORT + LOAD_PORTS - 1 ))
endpoint_capture_start "$CLIENT_ID" "$SERVER_ID" "portrange ${SERVER_PORT}-${PORT_HI}"


# ─── Step 4: Run baseline measurements ───────────────────────────────────────
log "Step 4: Running baseline load ($BASELINE_CONNECTIONS round(s))..."
run_ttfb_measurement "$CLIENT_ID" "$SERVER_IP" "$SERVER_PORT" "$BASELINE_CONNECTIONS" "$REPO_PATH" "${LOAD_TIMEOUT:-1800}" "Baseline"

sleep 3


# ─── Step 5: Stop captures + Server, analyze, collect logs ───────────────────
log "Step 5: Stopping captures and Server..."
endpoint_capture_stop "$CLIENT_ID" "$SERVER_ID"
ssm_bg "$SERVER_ID" "pkill -f loadgen.py 2>/dev/null || true"
sleep 2

log "Packet analysis: analyzing each endpoint capture on its own host..."
endpoint_analyze "$CLIENT_ID" "$SERVER_ID" "$REPO_PATH"

# Same metric set, same ordering, same helper as the 0-RTT run — so the two
# reports can be read side by side without re-deriving what each row means.
# There is no NIC in-app TTFB block here: the baseline has no data plane.
METRICS_SUMMARY=$(endpoint_latency_summary "${ENDPOINT_METRICS:-}")
echo "--- Latency summary ---"
echo "$METRICS_SUMMARY"
echo "-----------------------"

SERVER_LOG=$(ssm_stdout "$SERVER_ID" "cat /tmp/server.log" 30)
echo "--- Server log ---"
echo "$SERVER_LOG"
echo "------------------"

if echo "$SERVER_LOG" | grep -qiE "Received|bytes|connection"; then
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

IMPL_INFO=$(
    echo "**Mode**: Plain TCP (no 0-RTT middleware)"
    echo "**Infra**: \`infra/baseline\` CDK stack (BaselineStack) — 4× t3.micro, kernel forwarding"
)

EXTRA_BODY=$(
    echo "## Load Parameters"
    echo ""
    echo "These must match the 0-RTT run being compared against, or the comparison"
    echo "is confounded. Both stacks read them from \`experiments/lib/measure.sh\`"
    echo "and configure endpoints via \`experiments/lib/endpoint.sh\`."
    echo ""
    echo "| Parameter | Value |"
    echo "|---|---|"
    echo "| Rounds | $BASELINE_CONNECTIONS |"
    echo "| \`LOAD_PARALLEL\` | $LOAD_PARALLEL |"
    echo "| \`LOAD_PORTS\` | $LOAD_PORTS |"
    echo "| \`LOAD_BYTES\` | $LOAD_BYTES |"
    echo "| \`LOAD_RATE\` | $LOAD_RATE conn/s |"
    echo "| \`LOAD_CONCURRENCY\` | $LOAD_CONCURRENCY |"
    echo "| \`NETEM_RTT_MS\` | $NETEM_RTT_MS (Server egress only) |"
)

{
    report_header "Baseline TCP Report" "$IMPL_INFO" "$OVERALL_RESULT" "%Y-%m-%d-%H%M%S"
    printf '%s\n' "$EXTRA_BODY"
    echo ""
    report_section "Latency Summary" "$METRICS_SUMMARY"
    report_section "Client Output" "$CLIENT_STDOUT"
    report_section "Endpoint Packet Analysis" "${ENDPOINT_METRICS:-}"
    report_section "Server Log" "$SERVER_LOG" 20
    echo "## Notes"
    echo ""
    echo "- Traffic path: Client → ClientNIC (kernel forward) → ServerNIC (kernel forward) → Server"
    echo "- ClientNIC: ip_forward=1, static route 10.1.2.0/24 via 10.1.1.1 dev eth1"
    echo "- ServerNIC: ip_forward=1, static route 10.1.0.0/24 via 10.1.1.1 dev eth0"
    echo "- Emulated RTT is applied entirely on the Server VM's egress, so the leg"
    echo "  0-RTT short-circuits carries the full \`NETEM_RTT_MS\`. See endpoint.sh."
    echo "- **Compare \`Send unlock\` against \`experiments/dpdk/reports/\`** — that is"
    echo "  the metric the 0-RTT mechanism acts on. FCT and server gap are"
    echo "  throughput-bound and move with payload size and loss."
} > "$REPORT_FILE"

log "Report saved to $REPORT_FILE"

exit "$FAILURES"
