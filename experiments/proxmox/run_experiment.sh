#!/usr/bin/env bash
# End-to-end 0-RTT TCP experiment for the RUNS Proxmox lab.
#
# Uses the SSH-gateway transport to reach lab VMs on the 10.13.37.0/24
# dev subnet via the RUNS gateway at 132.75.121.140.
#
# 4-VM chain topology (Proxmox VMs):
#
#   Client ──eth0──► ClientNIC (dpdk-forwarder) ──eth1──► ServerNIC (servernic-dpdk) ──eth2──► Server
#
# Prerequisites:
#   - F5 VPN (HAIFA) active
#   - ~/.ssh/config entry for "runs-gateway" (HostName 132.75.121.140, User runs)
#   - SSH key-based auth to gateway + lab VMs (no interactive prompts)
#   - python3 in PATH (local)
#   - Lab VMs running with DPDK 23.11 built and vfio-pci bound on ClientNIC/ServerNIC eth1
#
# VM IP configuration (override via env vars; see experiments/utils/ssh_lab.sh):
#   LAB_CLIENT_IP    (default: 10.13.37.10)
#   LAB_CLIENTNIC_IP (default: 10.13.37.11)
#   LAB_SERVERNIC_IP (default: 10.13.37.12)
#   LAB_SERVER_IP_INTERNAL (default: 10.13.37.13)
#
# Usage:
#   ./experiments/proxmox/run_experiment.sh
#   CONNECTIONS=10 ./experiments/proxmox/run_experiment.sh
#
# Exit code: 0 = all checks passed, non-zero = number of failures

set -uo pipefail

export PYTHONUTF8=1
export PYTHONIOENCODING=utf-8

# shellcheck source=../utils/ssh_lab.sh
source "$(dirname "$0")/../utils/ssh_lab.sh"
# shellcheck source=../utils/measure.sh
source "$(dirname "$0")/../utils/measure.sh"
# shellcheck source=../utils/run_core.sh
source "$(dirname "$0")/../utils/run_core.sh"

REPO_PATH="/home/user/zero-rtt-tcp"
SERVER_PORT=8080
# Measurement ROUNDS (each round opens LOAD_PARALLEL conns across LOAD_PORTS
# ports — see experiments/utils/measure.sh). Default 1 round of 100000.
CONNECTIONS="${CONNECTIONS:-1}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
FAILURES=0

log()  { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}" >&2; }
pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; FAILURES=$((FAILURES + 1)); }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }


# ─── Step 0: Discover lab nodes ───────────────────────────────────────────────
log "Step 0: Discovering Proxmox lab VMs..."

if ! discover_nodes; then
    echo -e "${RED}ERROR: one or more lab VMs are unreachable via gateway${NC}" >&2
    echo "  Check F5 VPN and ~/.ssh/config (runs-gateway → 132.75.121.140)" >&2
    exit 1
fi

log "  Client:    $CLIENT_ID"
log "  ClientNIC: $CLIENTNIC_ID"
log "  ServerNIC: $SERVERNIC_ID"
log "  Server:    $SERVER_ID  ($SERVER_IP)"


# ─── Resolve MACs ─────────────────────────────────────────────────────────────
# In the Proxmox lab, MACs are read from the VMs directly (no EC2 API).
log "Resolving Ethernet MACs from lab VMs..."

# GW_MAC: ServerNIC eth1 MAC — ClientNIC DPDK port next hop
GW_MAC=$(get_lab_mac "$SERVERNIC_ID" "eth1")
# CLIENTNIC_ETH1_MAC: ClientNIC eth1 MAC — ServerNIC needs this as --gw-mac
CLIENTNIC_ETH1_MAC=$(get_lab_mac "$CLIENTNIC_ID" "eth1")
# SERVER_ETH0_MAC: Server eth0 MAC — ServerNIC needs this as --server-mac
SERVER_ETH0_MAC=$(get_lab_mac "$SERVER_ID" "eth0")
# Each SmartNIC's OWN endpoint-facing port MAC. The binaries map DPDK port roles by
# MAC, since port IDs follow PCI enumeration order rather than interface numbering.
CLIENTNIC_ETH2_MAC=$(get_lab_mac "$CLIENTNIC_ID" "eth2")
SERVERNIC_ETH2_MAC=$(get_lab_mac "$SERVERNIC_ID" "eth2")

log "  GW_MAC (ServerNIC eth1):      ${GW_MAC:-UNKNOWN}"
log "  CLIENTNIC_ETH1_MAC:           ${CLIENTNIC_ETH1_MAC:-UNKNOWN}"
log "  SERVER_ETH0_MAC:              ${SERVER_ETH0_MAC:-UNKNOWN}"
log "  CLIENTNIC_ETH2_MAC:           ${CLIENTNIC_ETH2_MAC:-UNKNOWN}"
log "  SERVERNIC_ETH2_MAC:           ${SERVERNIC_ETH2_MAC:-UNKNOWN}"

for var_name in GW_MAC CLIENTNIC_ETH1_MAC SERVER_ETH0_MAC CLIENTNIC_ETH2_MAC SERVERNIC_ETH2_MAC; do
    val="${!var_name}"
    if [[ -z "$val" || "$val" == "UNKNOWN" ]]; then
        echo -e "${RED}ERROR: could not resolve $var_name${NC}" >&2
        exit 1
    fi
done


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
REPORT_FILE="$REPORT_DIR/proxmox-test-report-$(date +%Y-%m-%d).md"

if [[ $FAILURES -eq 0 ]]; then
    OVERALL_RESULT="ALL PASSED"
else
    OVERALL_RESULT="$FAILURES FAILURE(S)"
fi

{
    echo "# Proxmox 0-RTT Test Report — $(date +%Y-%m-%d)"
    echo ""
    echo "**Implementation**: DPDK (T8 ISN ack-num translation shift)"
    echo "**Infra**: RUNS Proxmox lab — 4 VMs via SSH gateway (${LAB_GATEWAY})"
    echo "**ClientNIC binary**: \`src/clientnic/dpdk-forwarder/\` (transparent forwarder + V-stamp)"
    echo "**ServerNIC binary**: \`src/servernic/dpdk/\` (full translator)"
    echo "**Experiment script**: \`experiments/proxmox/run_experiment.sh\`"
    echo "**Transport**: SSH jump host via \`experiments/utils/ssh_lab.sh\`"
    echo "**Overall result**: $OVERALL_RESULT"
    echo ""
    echo "## Latency Summary (TTFB @ 3 points + FCT)"
    echo ""
    echo '```'
    echo "${CORE_METRICS_SUMMARY:-}"
    echo '```'
    echo ""
    echo "## Client Output"
    echo ""
    echo '```'
    echo "${CLIENT_STDOUT:-}"
    echo '```'
    echo ""
    echo "## ClientNIC Log (0-RTT activity)"
    echo ""
    echo '```'
    echo "${CORE_CLIENTNIC_LOG:-}" | tail -50
    echo '```'
    echo ""
    echo "## ServerNIC Log"
    echo ""
    echo '```'
    echo "${CORE_SERVERNIC_LOG:-}" | tail -30
    echo '```'
    echo ""
    echo "## Server Log"
    echo ""
    echo '```'
    echo "${CORE_SERVER_LOG:-}" | tail -20
    echo '```'
    echo ""
    echo "## Packet Analysis"
    echo ""
    echo '```'
    echo "${CORE_ENDPOINT_METRICS:-}"
    echo '```'
} > "$REPORT_FILE"

log "Report saved to $REPORT_FILE"

exit "$FAILURES"
