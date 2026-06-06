#!/usr/bin/env bash
# Run on the Client VM — iperf stress-test variant.
# Replaces client.py with the full iperf_client.sh suite
# (multi-flow, parallel streams, bursts, UDP flood, stress).
#
# Startup order: server_iperf.sh → servernic.sh → clientnic.sh → client_iperf.sh
# Run this last, after clientnic.sh reports "Entering busy-poll loop...".
#
# Usage:
#   ./client_iperf.sh <server-private-ip>
#   ./client_iperf.sh               # auto-discovers server IP via EC2 API

set -uo pipefail

IPERF_PORT=5001
REGION="eu-central-1"
REPO_PATH="/home/ec2-user/zero-rtt-demo"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}"; }

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
    echo "Usage: $0 <server-private-ip>"
    exit 1
fi

# ─── Pre-flight ───────────────────────────────────────────────────────────────
command -v iperf >/dev/null || { echo -e "${RED}ERROR: iperf not installed. Run: sudo yum install -y iperf${NC}"; exit 1; }

# ─── Pull latest code ─────────────────────────────────────────────────────────
log "Pulling latest code..."
sudo -u ec2-user git -C "$REPO_PATH" pull origin main 2>&1 || true

# ─── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  0-RTT iperf Stress Suite                        ║${NC}"
echo -e "${CYAN}║  Server: ${SERVER_IP}:${IPERF_PORT}                         ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
log "Watch Terminal 3 (ClientNIC) for per-flow SYN/delta logs."
echo ""

# ─── Run full iperf suite ─────────────────────────────────────────────────────
bash "$REPO_PATH/client-app/iperf_client.sh" "$SERVER_IP" "$IPERF_PORT"
