#!/usr/bin/env bash
# Run on the ServerNIC VM (Scapy stack).
# Sets up iptables + route, then runs the stateless forwarder in the foreground.
#
# Startup order: server.sh → servernic.sh → clientnic.sh → client.sh
# Run this after server.sh is ready.

set -uo pipefail

REPO_PATH="/home/ec2-user/zero-rtt-tcp"
SERVER_PORT=8080

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}"; }

# ─── Cleanup ──────────────────────────────────────────────────────────────────
log "Killing any leftover servernic processes..."
pkill -f 'servernic/scapy' 2>/dev/null || true
sudo iptables -F FORWARD 2>/dev/null || true
sleep 1

# ─── Pull latest code ─────────────────────────────────────────────────────────
log "Pulling latest code..."
sudo -u ec2-user git -C "$REPO_PATH" pull origin main 2>&1 || true

# ─── Network setup ────────────────────────────────────────────────────────────
# Route: Scapy's send() uses the kernel routing table. Without this route,
# return packets from the server subnet are routed incorrectly.
log "Adding route 10.1.0.0/24 via 10.1.1.1 dev eth0..."
sudo ip route replace 10.1.0.0/24 via 10.1.1.1 dev eth0 2>/dev/null || true

# iptables: block kernel forwarding so Scapy is the sole handler for port-8080
# traffic (otherwise each packet is forwarded twice).
log "Setting iptables FORWARD DROP for port $SERVER_PORT..."
sudo iptables -F FORWARD 2>/dev/null || true
sudo iptables -A FORWARD -p tcp --dport "$SERVER_PORT" -j DROP
sudo iptables -A FORWARD -p tcp --sport "$SERVER_PORT" -j DROP

# ─── IP forwarding check ──────────────────────────────────────────────────────
FWRD=$(cat /proc/sys/net/ipv4/ip_forward)
if [ "$FWRD" != "1" ]; then
    log "WARNING: IP forwarding not enabled — enabling now..."
    sudo sysctl -w net.ipv4.ip_forward=1
fi
log "IP forwarding: enabled"

# ─── Cleanup on exit ──────────────────────────────────────────────────────────
cleanup() {
    echo ""
    log "Cleaning up iptables..."
    sudo iptables -F FORWARD 2>/dev/null || true
    log "ServerNIC stopped."
}
trap cleanup EXIT

# ─── Start servernic (foreground) ─────────────────────────────────────────────
log "Starting servernic/scapy/main.py — press Ctrl+C to stop."
echo ""
exec python3 -u "$REPO_PATH/src/servernic/scapy/main.py" --client-iface eth0 --server-iface eth1
