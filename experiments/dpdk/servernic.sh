#!/usr/bin/env bash
# Run on the ServerNIC VM (T8 mode: servernic-dpdk binary).
#
# ENI roles (T8 design, D6):
#   eth0: kernel/SSM management
#   eth1: ClientNIC-facing DPDK port (vfio-pci, bound at boot by CDK user data)
#   eth2: Server-facing AF_PACKET
#
# The binary handles its own iptables RST suppression and FORWARD drops.
#
# Startup order: server.sh → servernic.sh → clientnic.sh → client.sh
#
# Usage (on the ServerNIC VM via SSM or SSH):
#   ./servernic.sh <clientnic-gw-mac> <server-gw-mac>
#
#   clientnic-gw-mac: MAC of ClientNIC's eth1 secondary ENI (Middle subnet).
#                     Get it: aws ec2 describe-instances ... | jq ...
#                             or: on ClientNIC VM: cat /sys/class/net/eth1/address
#                             (requires eth1 to be briefly in kernel mode)
#   server-gw-mac:   MAC of the Server's eth0 (or Server subnet gateway).
#                     Get it: on Server VM: cat /sys/class/net/eth0/address
#
#   Alternatively, set CLIENTNIC_GW_MAC and SERVER_GW_MAC env vars.
#
# SKIP_BUILD=1 to skip meson+ninja.

set -uo pipefail

REPO_PATH="/home/ec2-user/zero-rtt-demo"
DPDK_BUILD="$REPO_PATH/servernic/dpdk/builddir"
BINARY="$DPDK_BUILD/servernic-dpdk"
SERVER_PORT=8080
REGION="eu-central-1"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}"; }

# ─── Cleanup ──────────────────────────────────────────────────────────────────
log "Killing any leftover servernic processes..."
pkill -x servernic-dpdk 2>/dev/null || true
pkill -f 'servernic/scapy' 2>/dev/null || true
sudo iptables -F FORWARD 2>/dev/null || true
sudo iptables -F OUTPUT 2>/dev/null || true
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
    log "Building servernic-dpdk (set SKIP_BUILD=1 to skip)..."
    export PATH=/usr/local/bin:$PATH
    export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig
    cd "$REPO_PATH/servernic/dpdk"
    rm -rf builddir
    /usr/local/bin/meson setup builddir 2>&1 \
        && cd builddir && /usr/local/bin/ninja 2>&1 \
        && log "Build succeeded." \
        || { echo -e "${RED}ERROR: Build failed.${NC}"; exit 1; }
    cd "$REPO_PATH"
fi

# ─── Discover gateway MACs ────────────────────────────────────────────────────
# --gw-mac: ClientNIC-side gateway MAC (ClientNIC eth1 secondary ENI, Middle subnet)
# --server-gw-mac: Server-side gateway MAC (Server eth0 MAC or subnet gateway)
CLIENTNIC_GW_MAC="${1:-${CLIENTNIC_GW_MAC:-}}"
SERVER_GW_MAC="${2:-${SERVER_GW_MAC:-}}"

if [ -z "$CLIENTNIC_GW_MAC" ]; then
    log "Discovering ClientNIC eth1 MAC via EC2 API..."
    CLIENTNIC_GW_MAC=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=smartnics-clientnic" "Name=instance-state-name,Values=running" \
        --query "Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==\`1\`].MacAddress" \
        --output text --region "$REGION" 2>/dev/null | tr -d '[:space:]')
fi
if [ -z "$CLIENTNIC_GW_MAC" ] || [ "$CLIENTNIC_GW_MAC" = "None" ]; then
    echo -e "${RED}ERROR: Could not determine ClientNIC gateway MAC.${NC}"
    exit 1
fi

if [ -z "$SERVER_GW_MAC" ]; then
    log "Discovering Server eth0 MAC via EC2 API..."
    SERVER_GW_MAC=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=smartnics-server" "Name=instance-state-name,Values=running" \
        --query "Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==\`0\`].MacAddress" \
        --output text --region "$REGION" 2>/dev/null | tr -d '[:space:]')
fi
if [ -z "$SERVER_GW_MAC" ] || [ "$SERVER_GW_MAC" = "None" ]; then
    echo -e "${RED}ERROR: Could not determine Server gateway MAC.${NC}"
    exit 1
fi

log "ClientNIC-side gateway MAC (eth1): $CLIENTNIC_GW_MAC"
log "Server-side gateway MAC (eth2):    $SERVER_GW_MAC"

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
    sudo iptables -F OUTPUT 2>/dev/null || true
    log "ServerNIC DPDK stopped."
}
trap cleanup EXIT

# ─── Start servernic-dpdk (foreground) ───────────────────────────────────────
log "Starting servernic-dpdk — watching for flows. Press Ctrl+C to stop."
log "  --port=$SERVER_PORT --gw-mac=$CLIENTNIC_GW_MAC --server-gw-mac=$SERVER_GW_MAC"
echo ""
exec "$BINARY" -l 0 -- \
    --port="$SERVER_PORT" \
    --gw-mac="$CLIENTNIC_GW_MAC" \
    --server-gw-mac="$SERVER_GW_MAC" \
    --client-iface=eth1 \
    --server-iface=eth2
