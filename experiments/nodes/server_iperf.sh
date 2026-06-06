#!/usr/bin/env bash
# Run on the Server VM — iperf server variant.
# Replaces server.py with iperf listening on port 5001.
#
# Startup order: server_iperf.sh → servernic.sh → clientnic.sh → client_iperf.sh
# Run this first and wait until "Server listening on port 5001" appears.

set -uo pipefail

IPERF_PORT=5001

RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}"; }

# ─── Cleanup ──────────────────────────────────────────────────────────────────
log "Killing any leftover iperf / server.py processes..."
pkill -f 'iperf' 2>/dev/null || true
pkill -f 'python3.*server.py' 2>/dev/null || true
sleep 1

# ─── Pull latest code ─────────────────────────────────────────────────────────
log "Pulling latest code..."
sudo -u ec2-user git -C /home/ec2-user/zero-rtt-demo pull origin main 2>&1 || true

# ─── Pre-flight ───────────────────────────────────────────────────────────────
command -v iperf >/dev/null || { echo -e "${RED}ERROR: iperf not installed. Run: sudo yum install -y iperf${NC}"; exit 1; }
MY_IP=$(hostname -I | awk '{print $1}')
log "Server VM IP: $MY_IP"
log "Will listen on 0.0.0.0:$IPERF_PORT"
echo ""

# ─── Start iperf server (foreground, persistent) ─────────────────────────────
log "Starting iperf server — press Ctrl+C to stop."
echo ""
bash /home/ec2-user/zero-rtt-demo/server-app/iperf_server.sh "$IPERF_PORT"
