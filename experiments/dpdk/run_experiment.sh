#!/usr/bin/env bash
# End-to-end integration test for the 0-RTT TCP demo — ISN ack-num translation shift.
#
# Topology (all in AWS, eu-central-1):
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

REPO_PATH="/home/ec2-user/zero-rtt-tcp"
SERVER_PORT=8080

# shellcheck source=../lib/output.sh
source "$(dirname "$0")/../lib/output.sh"
# shellcheck source=../lib/report.sh
source "$(dirname "$0")/../lib/report.sh"

# Number of measurement ROUNDS (each round opens LOAD_PARALLEL connections across
# LOAD_PORTS ports — see experiments/utils/measure.sh). Default 1 round of 100000.
# Override via env: CONNECTIONS=3 ./run_experiment.sh
CONNECTIONS="${CONNECTIONS:-1}"

FAILURES=0

# ─── Transport shims: map run_core.sh primitives to SSM helpers ───────────────
remote_run()    { ssm_run    "$@"; }
remote_bg()     { ssm_bg     "$@"; }
remote_stdout() { ssm_stdout "$@"; }

# SSM silently truncates StandardOutputContent at 24 KB — no error, no marker,
# the last line is simply cut mid-character. Anything this transport fetches by
# `cat`-ing a whole file is therefore a prefix once the file passes ~24 KB, which
# is routine for the NIC logs at 100k connections. run_core.sh uses this to warn
# when a fetched blob lands at the cap. Unset for uncapped transports (SSH).
REMOTE_OUTPUT_CAP=24000

# ─── Node discovery (AWS EC2) ─────────────────────────────────────────────────
# Populates SERVER_ID, SERVERNIC_ID, CLIENTNIC_ID, CLIENT_ID, SERVER_IP.
discover_nodes() {
    SERVER_ID=$(get_iid "smartnics-server")
    SERVERNIC_ID=$(get_iid "smartnics-servernic")
    CLIENTNIC_ID=$(get_iid "smartnics-clientnic")
    CLIENT_ID=$(get_iid "smartnics-client")
    SERVER_IP=$(get_ip "smartnics-server")
}

# shellcheck source=../utils/run_core.sh
source "$(dirname "$0")/../utils/run_core.sh"


# ─── Step 0: Discover instances ───────────────────────────────────────────────
log "Step 0: Discovering EC2 instances..."

discover_nodes

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


# ─── Resolve MACs (AWS EC2 API) ───────────────────────────────────────────────
# Gateway MAC for ClientNIC: ServerNIC eth1 MAC (DeviceIndex=1, Middle subnet, DPDK port).
# eth1 is DPDK-controlled so the kernel can't ARP for it — read from EC2 API.
log "Resolving Ethernet MACs from EC2 API..."

GW_MAC=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=smartnics-servernic" "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==\`1\`].MacAddress" \
    --output text --region eu-central-1 2>/dev/null | tr -d '[:space:]')

# ClientNIC eth1 MAC (DeviceIndex=1) → ServerNIC needs this as --gw-mac
CLIENTNIC_ETH1_MAC=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=smartnics-clientnic" "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==\`1\`].MacAddress" \
    --output text --region eu-central-1 2>/dev/null | tr -d '[:space:]')

# Server eth0 MAC (DeviceIndex=0) → ServerNIC needs this as --server-mac
SERVER_ETH0_MAC=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=smartnics-server" "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==\`0\`].MacAddress" \
    --output text --region eu-central-1 2>/dev/null | tr -d '[:space:]')

# Each SmartNIC's OWN endpoint-facing ENI (DeviceIndex=2). The binaries match these
# against each DPDK port's MAC to decide which port is which — port IDs follow PCI
# enumeration order, which does not reliably track ENI device_index.
CLIENTNIC_ETH2_MAC=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=smartnics-clientnic" "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==\`2\`].MacAddress" \
    --output text --region eu-central-1 2>/dev/null | tr -d '[:space:]')

SERVERNIC_ETH2_MAC=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=smartnics-servernic" "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==\`2\`].MacAddress" \
    --output text --region eu-central-1 2>/dev/null | tr -d '[:space:]')

log "  ClientNIC eth1 MAC (ServerNIC --gw-mac):          ${CLIENTNIC_ETH1_MAC:-UNKNOWN}"
log "  Server eth0 MAC (ServerNIC --server-mac):         ${SERVER_ETH0_MAC:-UNKNOWN}"
log "  ClientNIC eth2 MAC (its own client-facing port):  ${CLIENTNIC_ETH2_MAC:-UNKNOWN}"
log "  ServerNIC eth2 MAC (its own server-facing port):  ${SERVERNIC_ETH2_MAC:-UNKNOWN}"

for _v in CLIENTNIC_ETH1_MAC SERVER_ETH0_MAC CLIENTNIC_ETH2_MAC SERVERNIC_ETH2_MAC; do
    if [[ -z "${!_v}" || "${!_v}" == "None" ]]; then
        fail "Could not resolve $_v from the EC2 API"
    fi
done

if [[ -z "$GW_MAC" || "$GW_MAC" == "None" ]]; then
    fail "Smoke test: could not discover ServerNIC eth1 MAC (DeviceIndex=1)"
else
    log "  Gateway MAC (ServerNIC eth1, DPDK port): $GW_MAC"

    # Smoke-test clientnic-dpdk-forwarder: run 3 s, check for busy-poll
    DPDK_BUILD="$REPO_PATH/src/clientnic/dpdk-forwarder/builddir"
    BINARY="$DPDK_BUILD/clientnic-dpdk-forwarder"

    ssm_run "$CLIENTNIC_ID" \
        "rm -f /tmp/clientnic_smoke.log; \
         setsid $BINARY -l 0 -- --port=$SERVER_PORT --gw-mac=$GW_MAC \
             --client-port-mac=$CLIENTNIC_ETH2_MAC --server-port-mac=$CLIENTNIC_ETH1_MAC \
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


# ─── Run shared experiment core ───────────────────────────────────────────────
run_experiment "$GW_MAC" "$CLIENTNIC_ETH1_MAC" "$SERVER_ETH0_MAC" \
               "$CLIENTNIC_ETH2_MAC" "$SERVERNIC_ETH2_MAC"


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
    OVERALL_RESULT="ALL PASSED"
else
    OVERALL_RESULT="$FAILURES FAILURE(S)"
fi

IMPL_INFO=$(
    echo "**Implementation**: DPDK (ISN ack-num translation shift)"
    echo "**ClientNIC binary**: \`src/clientnic/dpdk-forwarder/\` (transparent forwarder + V-stamp)"
    echo "**ServerNIC binary**: \`src/servernic/dpdk/\` (full translator)"
    echo "**Experiment script**: \`experiments/dpdk/run_experiment.sh\`"
    echo "**Node scripts**: \`experiments/dpdk/\` (clientnic/servernic), \`experiments/nodes/\` (client/server)"
)

EXTRA_BODY=$(
    if [[ "${LOAD_RATE:-2000}" == "0" ]]; then
        echo "> **CAPACITY RUN — \`LOAD_RATE=0\`.** Connections arrived as a single"
        echo "> burst, so every flow's latency includes queueing behind the rest of"
        echo "> the batch. Valid readings: establishment success rate and data-plane"
        echo "> throughput. **Not** valid: any 0-RTT latency claim. For a latency"
        echo "> run use \`run_experiment.sh\` with the default paced arrival."
        echo ""
    fi
    echo "## Load Parameters"
    echo ""
    echo "Must match the baseline run being compared against — see"
    echo "\`experiments/baseline-tcp/reports/\`."
    echo ""
    echo "| Parameter | Value |"
    echo "|---|---|"
    echo "| Rounds | $CONNECTIONS |"
    echo "| \`LOAD_PARALLEL\` | $LOAD_PARALLEL |"
    echo "| \`LOAD_PORTS\` | $LOAD_PORTS |"
    echo "| \`LOAD_BYTES\` | $LOAD_BYTES |"
    echo "| \`LOAD_RATE\` | $LOAD_RATE conn/s |"
    echo "| \`LOAD_CONCURRENCY\` | $LOAD_CONCURRENCY |"
    echo "| \`NETEM_RTT_MS\` | $NETEM_RTT_MS (Server egress only) |"
    echo ""
    echo "## Latency Summary"
    echo ""
    echo "\`Send unlock\` is the primary result: first SYN out → first payload out,"
    echo "which is exactly what the spoofed SYN-ACK unblocks. Compare it against the"
    echo "baseline's \`Send unlock\`; the expected saving is one \`NETEM_RTT_MS\`."
    echo ""
    echo '```'
    echo "${CORE_METRICS_SUMMARY:-}"
    echo '```'
)

{
    report_header "" "$IMPL_INFO" "$OVERALL_RESULT"
    printf '%s\n' "$EXTRA_BODY"
    echo ""
    report_section "Client Output" "${CLIENT_STDOUT:-}"
    report_section "ClientNIC Log (0-RTT activity)" "${CORE_CLIENTNIC_LOG:-}" 50
    report_section "ServerNIC Log" "${CORE_SERVERNIC_LOG:-}" 30
    report_section "Server Log" "${CORE_SERVER_LOG:-}" 20
    report_section "Packet Analysis" "${CORE_ENDPOINT_METRICS:-}" "" 1
} > "$REPORT_FILE"

log "Report saved to $REPORT_FILE"

exit "$FAILURES"
