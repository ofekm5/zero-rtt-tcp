#!/usr/bin/env bash
# Run on the Server VM.
# Cleans up, pulls latest code, starts server.py in the foreground.
#
# Startup order: server.sh → servernic.sh → clientnic.sh → client.sh
# Run this first and wait until "Server listening on 0.0.0.0:8080" appears.
#
# Usage (on the Server VM via SSM or SSH):
#   cd /home/ec2-user/zero-rtt-demo/experiments/zero-rtt-dpdk/nodes
#   ./server.sh
#
# The script blocks in the foreground. Press Ctrl+C to stop.

set -uo pipefail

REPO_PATH="/home/ec2-user/zero-rtt-demo"
SERVER_PORT=8080

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}"; }

# ─── Cleanup ──────────────────────────────────────────────────────────────────
log "Killing any leftover server.py..."
pkill -f 'python3.*server.py' 2>/dev/null || true
sleep 1

# ─── Pull latest code ─────────────────────────────────────────────────────────
log "Pulling latest code..."
sudo -u ec2-user git -C "$REPO_PATH" pull origin main 2>&1 || true

# ─── Pre-flight ───────────────────────────────────────────────────────────────
MY_IP=$(hostname -I | awk '{print $1}')
log "Server VM IP: $MY_IP"
log "Will listen on 0.0.0.0:$SERVER_PORT"
echo ""

# ─── Start server (foreground) ────────────────────────────────────────────────
log "Starting server.py — press Ctrl+C to stop."
echo ""
cd "$REPO_PATH"
exec python3 -u server-app/server.py --host 0.0.0.0 --port "$SERVER_PORT" --verbose
