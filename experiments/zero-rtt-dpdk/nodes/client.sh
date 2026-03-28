#!/usr/bin/env bash
# Run on the Client VM (Scapy stack) — interactive 0-RTT client.
# Press Enter to send a new TCP connection; each press uses a different
# OS-assigned ephemeral source port, creating a fresh 4-tuple flow.
#
# Startup order: server.sh → servernic.sh → clientnic.sh → client.sh
# Run this last, after clientnic.sh is ready.
#
# Usage: ./client.sh [server-ip]
#   server-ip: optional; auto-discovered from EC2 API if omitted.

set -uo pipefail

REPO_PATH="/home/ec2-user/zero-rtt-demo"
SERVER_PORT=8080
REGION="eu-central-1"

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
echo -e "${CYAN}║  0-RTT Interactive Client                        ║${NC}"
echo -e "${CYAN}║  Server: ${SERVER_IP}:${SERVER_PORT}                        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "Press Enter to send a new TCP connection (new flow each time)."
echo "Press Ctrl+C to quit."
echo ""

while IFS= read -r _input; do
    CONN=$((CONN + 1))
    echo -e "${GREEN}─── Connection #${CONN} ───────────────────────────────────────${NC}"
    python3 "$REPO_PATH/client-app/client.py" \
        --host "$SERVER_IP" --port "$SERVER_PORT" \
        --mode single --verbose
    echo ""
    echo "Press Enter for connection #$((CONN + 1)), or Ctrl+C to quit."
    echo ""
done
