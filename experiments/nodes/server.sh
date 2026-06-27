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
# Number of contiguous ports to listen on (SERVER_PORT .. SERVER_PORT+IPERF_PORTS-1).
# The client spreads its parallel connections across these to clear the per-port
# ephemeral-port ceiling. Must match the data plane's --port-count.
IPERF_PORTS="${IPERF_PORTS:-4}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}"; }

# ─── Cleanup ──────────────────────────────────────────────────────────────────
log "Killing any leftover iperf processes..."
pkill -f 'iperf -s' 2>/dev/null || true
sleep 1

# ─── Check iperf available (iperf2 ONLY) ──────────────────────────────────────
command -v iperf >/dev/null || { echo -e "${RED}ERROR: iperf not installed. Run: sudo amazon-linux-extras install -y epel && sudo yum install -y iperf${NC}"; exit 1; }
if iperf --version 2>&1 | grep -qiE 'iperf[ ]?3'; then
    echo -e "${RED}ERROR: iperf3 detected — this experiment requires iperf2. Install iperf2 and ensure it is first in PATH.${NC}"; exit 1
fi

# Raise the open-file limit so the server can accept the client's parallel
# connections (iperf2 -P on the client opens up to 100000 streams).
ulimit -n 1048576 2>/dev/null || ulimit -n "$(ulimit -Hn)" 2>/dev/null || true
log "Open-file limit (ulimit -n): $(ulimit -n)"

# ─── Pull latest code ─────────────────────────────────────────────────────────
log "Syncing code to origin/main (hard reset — discards VM-local drift)..."
sudo -u ec2-user git -C "$REPO_PATH" fetch origin main 2>&1 \
    && sudo -u ec2-user git -C "$REPO_PATH" reset --hard origin/main 2>&1 \
    || log "WARNING: git sync failed — using current checkout"

# ─── Pre-flight ───────────────────────────────────────────────────────────────
MY_IP=$(hostname -I | awk '{print $1}')
SERVER_PORT_HI=$(( SERVER_PORT + IPERF_PORTS - 1 ))
log "Server VM IP: $MY_IP"
log "Will listen on 0.0.0.0:${SERVER_PORT}-${SERVER_PORT_HI} ($IPERF_PORTS port(s))"
echo ""

# ─── Start iperf servers (one per port, background) ──────────────────────────
log "Starting $IPERF_PORTS iperf2 server(s) on ports ${SERVER_PORT}-${SERVER_PORT_HI} — press Ctrl+C to stop."
echo ""
SRV_PIDS=()
cleanup() { kill "${SRV_PIDS[@]}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
for (( p=SERVER_PORT; p<=SERVER_PORT_HI; p++ )); do
    iperf -s -p "$p" &
    SRV_PIDS+=("$!")
done
log "iperf servers running (pids: ${SRV_PIDS[*]})"
# Block in the foreground keeping all servers alive until signalled.
wait
