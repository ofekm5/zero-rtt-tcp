#!/usr/bin/env bash
# Run on the Client VM — interactive 0-RTT client.
# Press Enter to send a new TCP connection; each press uses a different
# OS-assigned ephemeral source port, creating a fresh 4-tuple flow.
#
# Startup order: server.sh → servernic.sh → clientnic.sh → client.sh
# Run this last, after clientnic.sh is ready.
#
# Usage (on the Client VM via SSM or SSH):
#   cd /home/ec2-user/zero-rtt-demo/experiments/zero-rtt-dpdk/nodes
#   ./client.sh <server-private-ip>
#
# IMPORTANT: Use the Server's PRIVATE IP (e.g. 10.1.2.x), NOT the public IP.
#   The Client VM connects over the internal VPC network — the public IP is
#   not reachable from inside the VPC and will cause every connection to time out.
#
#   Get the private IP from the CDK deploy output (ServerPublicIp is the public one;
#   use the private IP shown in `aws ec2 describe-instances` or `ip route` on the Server VM),
#   or from the server.sh startup log: "[HH:MM:SS] Server VM IP: 10.1.2.x"
#
#   Example:
#     ./client.sh 10.1.2.59     ✓ correct (private IP)
#     ./client.sh 18.199.80.62  ✗ wrong   (public IP — will time out)
#
# server-ip is optional; auto-discovered from EC2 API if omitted (requires IAM permissions).

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
