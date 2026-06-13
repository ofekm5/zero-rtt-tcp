#!/usr/bin/env bash
# Run on the Server VM.
# Cleans up, pulls latest code, starts iperf server in the foreground.
#
# Startup order: server.sh → servernic.sh → clientnic.sh → client.sh
# Run this first and wait until "Server listening on port 8080" appears.
#
# Usage (on the Server VM via SSM or SSH):
#   cd /home/ec2-user/zero-rtt-demo/experiments/nodes
#   ./server.sh
#
# The script blocks in the foreground. Press Ctrl+C to stop.

set -uo pipefail

REPO_PATH="/home/ec2-user/zero-rtt-demo"
SERVER_PORT=8080

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}"; }

# ─── Cleanup ──────────────────────────────────────────────────────────────────
log "Killing any leftover iperf processes..."
pkill -f 'iperf -s' 2>/dev/null || true
sleep 1

# ─── Check iperf available ────────────────────────────────────────────────────
command -v iperf >/dev/null || { echo -e "${RED}ERROR: iperf not installed. Run: sudo amazon-linux-extras install -y epel && sudo yum install -y iperf${NC}"; exit 1; }

# ─── Pull latest code ─────────────────────────────────────────────────────────
log "Pulling latest code..."
sudo -u ec2-user git -C "$REPO_PATH" pull origin main 2>&1 || true

# ─── Pre-flight ───────────────────────────────────────────────────────────────
MY_IP=$(hostname -I | awk '{print $1}')
log "Server VM IP: $MY_IP"
log "Will listen on 0.0.0.0:$SERVER_PORT"
echo ""

# ─── Start iperf server (foreground) ─────────────────────────────────────────
log "Starting iperf server — press Ctrl+C to stop."
echo ""
exec iperf -s -p "$SERVER_PORT"
