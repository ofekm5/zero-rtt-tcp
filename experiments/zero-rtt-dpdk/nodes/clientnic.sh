#!/usr/bin/env bash
# Run on the ClientNIC VM (DPDK stack).
# Optionally builds the binary, sets up iptables, starts tcpdump on eth0,
# then runs clientnic-dpdk in the foreground so you can watch 0-RTT activity live.
#
# Startup order: server.sh → servernic.sh → clientnic.sh → client.sh
# Run this after servernic.sh is ready. On exit, prints the validator command.
#
# Usage: [SKIP_BUILD=1] ./clientnic.sh [gw-mac]
#   SKIP_BUILD=1  skip meson+ninja (use existing binary)
#   gw-mac        ServerNIC eth0 MAC; auto-discovered from EC2 API if omitted

set -uo pipefail

REPO_PATH="/home/ec2-user/zero-rtt-demo"
DPDK_BUILD="$REPO_PATH/clientnic/dpdk/builddir"
BINARY="$DPDK_BUILD/clientnic-dpdk"
SERVER_PORT=8080
REGION="eu-central-1"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}"; }

# ─── Cleanup ──────────────────────────────────────────────────────────────────
log "Killing any leftover clientnic-dpdk/tcpdump processes..."
pkill -x clientnic-dpdk 2>/dev/null || true
pkill tcpdump 2>/dev/null || true
sudo iptables -F FORWARD 2>/dev/null || true
sudo iptables -F OUTPUT 2>/dev/null || true
rm -f /tmp/client_side.pcap /tmp/server_side.pcap
sleep 1

# ─── Pull latest code ─────────────────────────────────────────────────────────
log "Pulling latest code..."
sudo -u ec2-user git -C "$REPO_PATH" pull origin main 2>&1 || true

# ─── Build (optional) ─────────────────────────────────────────────────────────
if [ "${SKIP_BUILD:-0}" = "1" ]; then
    log "SKIP_BUILD=1 — skipping meson+ninja build."
    if [ ! -x "$BINARY" ]; then
        echo -e "${RED}ERROR: Binary not found at $BINARY${NC}"
        exit 1
    fi
    log "Using existing binary: $BINARY"
else
    log "Building clientnic-dpdk (set SKIP_BUILD=1 to skip)..."
    export PATH=/usr/local/bin:$PATH
    export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig
    cd "$REPO_PATH/clientnic/dpdk"
    rm -rf builddir
    /usr/local/bin/meson setup builddir 2>&1 \
        && cd builddir && /usr/local/bin/ninja 2>&1 \
        && log "Build succeeded." \
        || { echo -e "${RED}ERROR: Build failed.${NC}"; exit 1; }
    cd "$REPO_PATH"
fi

# ─── Discover gateway MAC ─────────────────────────────────────────────────────
# ServerNIC's eth0 MAC is the next hop on the middle subnet for eth1 (DPDK-bound).
# eth1 is DPDK-controlled so the kernel can't ARP for it — we read the MAC from
# the EC2 API instead (primary ENI, DeviceIndex=0, of the ServerNIC instance).
GW_MAC="${1:-}"
if [ -z "$GW_MAC" ]; then
    log "Discovering ServerNIC eth0 MAC via EC2 API..."
    GW_MAC=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=smartnics-servernic" "Name=instance-state-name,Values=running" \
        --query "Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==\`0\`].MacAddress" \
        --output text --region "$REGION" 2>/dev/null | tr -d '[:space:]')
fi
if [ -z "$GW_MAC" ] || [ "$GW_MAC" = "None" ]; then
    echo -e "${RED}ERROR: Could not determine gateway MAC.${NC}"
    echo "On the ServerNIC VM run: cat /sys/class/net/eth0/address"
    echo "Then pass it as: $0 <gw-mac>"
    exit 1
fi
log "Gateway MAC (ServerNIC eth0): $GW_MAC"

# ─── IP forwarding check ──────────────────────────────────────────────────────
FWRD=$(cat /proc/sys/net/ipv4/ip_forward)
if [ "$FWRD" != "1" ]; then
    log "WARNING: IP forwarding not enabled — enabling now..."
    sudo sysctl -w net.ipv4.ip_forward=1
fi
log "IP forwarding: enabled"

# ─── Start packet capture on eth0 (background) ───────────────────────────────
# eth1 is DPDK-controlled; the binary captures it directly via --server-pcap.
log "Starting tcpdump on eth0 → /tmp/client_side.pcap ..."
sudo tcpdump -i eth0 -nn -tttt "tcp port $SERVER_PORT" -w /tmp/client_side.pcap \
    </dev/null >/tmp/tcpdump_eth0.log 2>&1 &
TCPDUMP_PID=$!
sleep 1

# ─── Cleanup on exit ──────────────────────────────────────────────────────────
cleanup() {
    echo ""
    log "Stopping tcpdump and DPDK binary..."
    kill "$TCPDUMP_PID" 2>/dev/null || true
    wait "$TCPDUMP_PID" 2>/dev/null || true
    sudo iptables -F FORWARD 2>/dev/null || true
    sudo iptables -F OUTPUT 2>/dev/null || true
    sleep 1

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

# ─── Start DPDK binary (foreground) ──────────────────────────────────────────
log "Starting clientnic-dpdk — watching for flows. Press Ctrl+C to stop."
log "  --port=$SERVER_PORT --gw-mac=$GW_MAC --server-pcap=/tmp/server_side.pcap"
echo ""
exec "$BINARY" -l 0 -- \
    --port="$SERVER_PORT" \
    --gw-mac="$GW_MAC" \
    --server-pcap=/tmp/server_side.pcap
