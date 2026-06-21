#!/usr/bin/env bash
# Run on the Client VM — interactive 0-RTT iperf client (iperf2).
# Press Enter to run a new iperf flow; each invocation opens a fresh TCP connection.
#
# Startup order: server.sh → servernic.sh → clientnic.sh → client.sh
# Run this last, after clientnic.sh is ready.
#
# Usage (on the Client VM via SSH):
#   ./client.sh <server-private-ip>
#   ./client.sh               # auto-discovers server IP via EC2 API
#
# IMPORTANT: Use the Server's PRIVATE IP (e.g. 10.1.2.x), NOT the public IP.
#   The Client VM connects over the internal VPC network — the public IP is
#   not reachable from inside the VPC and will cause every connection to time out.
#
# server-ip is optional; auto-discovered from EC2 API if omitted (requires IAM permissions).

set -uo pipefail

REPO_PATH="/home/ec2-user/zero-rtt-demo"
SERVER_PORT=8080
REGION="eu-central-1"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}"; }

# ─── Pre-flight (iperf2 ONLY) ─────────────────────────────────────────────────
command -v iperf >/dev/null || { echo -e "${RED}ERROR: iperf not installed. Run: sudo yum install -y iperf${NC}"; exit 1; }
if iperf --version 2>&1 | grep -qiE 'iperf[ ]?3'; then
    echo -e "${RED}ERROR: iperf3 detected — this experiment requires iperf2.${NC}"; exit 1
fi

# Total parallel connections per flow (iperf2 -P), spread across IPERF_PORTS
# contiguous server ports so one source IP can clear the per-port ephemeral ceiling.
# Override: IPERF_PARALLEL=N IPERF_PORTS=M ./client.sh
IPERF_PARALLEL="${IPERF_PARALLEL:-100000}"
IPERF_PORTS="${IPERF_PORTS:-4}"
[ "$IPERF_PORTS" -lt 1 ] && IPERF_PORTS=1
PORT_HI=$(( SERVER_PORT + IPERF_PORTS - 1 ))
PERPORT=$(( (IPERF_PARALLEL + IPERF_PORTS - 1) / IPERF_PORTS ))   # ceil
# Give each iperf process enough fds for its share of parallel streams.
ulimit -n $((PERPORT + 1024)) 2>/dev/null || true

# ─── Discover server IP ───────────────────────────────────────────────────────
SERVER_IP="${1:-}"
if [ -z "$SERVER_IP" ]; then
    log "Discovering Server VM IP via EC2 API..."
    SERVER_IP=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=smartnics-server" "Name=instance-state-name,Values=running" \
        --query "Reservations[0].Instances[0].PrivateIpAddress" \
        --output text --region "$REGION" 2>/dev/null | tr -d '[:space:]')
fi
if [ -z "$SERVER_IP" ] || [ "$SERVER_IP" = "None" ]; then
    echo -e "${RED}ERROR: Could not determine server IP.${NC}"
    echo "Usage: $0 <server-ip>"
    exit 1
fi

# ─── Pull latest code ─────────────────────────────────────────────────────────
log "Pulling latest code..."
sudo -u ec2-user git -C "$REPO_PATH" pull origin main 2>&1 || true

# ─── Interactive loop ─────────────────────────────────────────────────────────
CONN=0

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  0-RTT Interactive iperf Client                  ║${NC}"
echo -e "${CYAN}║  Server: ${SERVER_IP}:${SERVER_PORT}                        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "Each flow opens $IPERF_PARALLEL connections across ports ${SERVER_PORT}-${PORT_HI}"
echo "($IPERF_PORTS port(s) x $PERPORT parallel). Press Enter for a new flow, Ctrl+C to quit."
echo ""

while IFS= read -r _input; do
    CONN=$((CONN + 1))
    echo -e "${GREEN}─── Flow #${CONN} (${IPERF_PORTS} ports x ${PERPORT} parallel) ──────────${NC}"
    pids=""
    for (( p=SERVER_PORT; p<=PORT_HI; p++ )); do
        iperf -c "$SERVER_IP" -p "$p" -P "$PERPORT" -n 1M -f m &
        pids="$pids $!"
    done
    # shellcheck disable=SC2086
    wait $pids
    echo ""
    echo "Press Enter for flow #$((CONN + 1)), or Ctrl+C to quit."
    echo ""
done
