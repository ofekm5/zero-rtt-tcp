#!/usr/bin/env bash
# Run on the ClientNIC VM (Scapy stack).
# Sets up iptables + route, starts tcpdump captures, then runs the 0-RTT
# interceptor in the foreground so you can watch flow table activity live.
#
# Startup order: server.sh → servernic.sh → clientnic.sh → client.sh
# Run this after servernic.sh is ready. On exit, prints the validator command.

set -uo pipefail

REPO_PATH="/home/ec2-user/zero-rtt-demo"
SERVER_PORT=8080

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}"; }

# ─── Cleanup ──────────────────────────────────────────────────────────────────
log "Killing any leftover clientnic/tcpdump processes..."
pkill -f 'clientnic/scapy' 2>/dev/null || true
pkill tcpdump 2>/dev/null || true
sudo iptables -F FORWARD 2>/dev/null || true
rm -f /tmp/client_side.pcap /tmp/server_side.pcap
sleep 1

# ─── Pull latest code ─────────────────────────────────────────────────────────
log "Pulling latest code..."
sudo -u ec2-user git -C "$REPO_PATH" pull origin main 2>&1 || true

# ─── Network setup ────────────────────────────────────────────────────────────
log "Adding route 10.1.2.0/24 via 10.1.1.1 dev eth1..."
sudo ip route replace 10.1.2.0/24 via 10.1.1.1 dev eth1 2>/dev/null || true

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

# ─── Start packet captures (background) ──────────────────────────────────────
# Start tcpdump BEFORE the interceptor so the spoofed SYN-ACK is captured.
log "Starting tcpdump on eth0 → /tmp/client_side.pcap ..."
sudo tcpdump -i eth0 -nn -tttt "tcp port $SERVER_PORT" -w /tmp/client_side.pcap \
    </dev/null >/tmp/tcpdump_eth0.log 2>&1 &
TCPDUMP_ETH0_PID=$!

log "Starting tcpdump on eth1 → /tmp/server_side.pcap ..."
sudo tcpdump -i eth1 -nn -tttt "tcp port $SERVER_PORT" -w /tmp/server_side.pcap \
    </dev/null >/tmp/tcpdump_eth1.log 2>&1 &
TCPDUMP_ETH1_PID=$!

sleep 1  # give tcpdump time to open the interfaces

# ─── Cleanup on exit ──────────────────────────────────────────────────────────
cleanup() {
    echo ""
    log "Stopping tcpdump (flushing pcap buffers)..."
    kill "$TCPDUMP_ETH0_PID" 2>/dev/null || true
    kill "$TCPDUMP_ETH1_PID" 2>/dev/null || true
    wait "$TCPDUMP_ETH0_PID" "$TCPDUMP_ETH1_PID" 2>/dev/null || true
    sleep 1

    sudo iptables -F FORWARD 2>/dev/null || true

    echo ""
    echo "─── Captures saved ──────────────────────────────────────────"
    ls -lh /tmp/client_side.pcap /tmp/server_side.pcap 2>/dev/null || true
    echo ""
    echo "─── Run validator ───────────────────────────────────────────"
    echo "  cp $REPO_PATH/clientnic/validate_0rtt_capture.py /tmp/"
    echo "  python3 /tmp/validate_0rtt_capture.py \\"
    echo "    --client-pcap /tmp/client_side.pcap \\"
    echo "    --server-pcap /tmp/server_side.pcap"
    echo "─────────────────────────────────────────────────────────────"
}
trap cleanup EXIT

# ─── Start ClientNIC interceptor (foreground) ─────────────────────────────────
log "Starting clientnic/scapy/main.py — watching for flows. Press Ctrl+C to stop."
echo ""
exec python3 -u "$REPO_PATH/clientnic/scapy/main.py"
