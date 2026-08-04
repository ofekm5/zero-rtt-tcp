#!/usr/bin/env bash
# Run on the ClientNIC VM (T8 mode: clientnic-dpdk-forwarder binary).
#
# T8 design: ClientNIC is a transparent forwarder — it spoofs the SYN-ACK,
# stamps V (spoofed server ISN) in the forwarded SYN's ack-num field, and does
# no seq/ack translation.  All translation happens at the ServerNIC.
#
# Startup order: server.sh → servernic.sh → clientnic.sh → client.sh
# Run this after servernic.sh is ready.
#
# Usage (on the ClientNIC VM via SSM or SSH):
#   cd /home/ec2-user/zero-rtt-tcp/experiments/dpdk
#
#   Full build + run (first time or after source changes):
#     ./clientnic.sh <gw-mac>
#
#   Skip build, use existing binary (faster — binary already built by CDK or prior run):
#     SKIP_BUILD=1 ./clientnic.sh <gw-mac>       ← NOTE: env var prefix, NOT 'SKIP_BUILD=1 &&'
#
#   gw-mac is the ServerNIC eth1 MAC (secondary ENI, Middle subnet, DPDK port).
#   Get it: aws ec2 describe-instances ... DeviceIndex=1 | jq .MacAddress
#           or from the CDK deploy output: SmartNicsStack.ServerNicEth1Mac
#
#   The binary also needs the MACs of ClientNIC's OWN two DPDK ports, so it can
#   tell which DPDK port is which: port IDs follow PCI enumeration order, which
#   does not reliably track ENI device_index. Both are auto-discovered via the
#   EC2 API, or passed via env:
#     CLIENT_PORT_MAC=<our eth2 ENI>  SERVER_PORT_MAC=<our eth1 ENI> ./clientnic.sh <gw-mac>
#
# Log output explained:
#   "SYN: flow created, spoofed SYN-ACK sent, SYN forwarded (V=<N>)"
#     → ClientNIC intercepted the client's SYN, immediately sent a spoofed SYN-ACK
#       back to the client (0-RTT), and forwarded the real SYN toward ServerNIC
#       with V (the spoofed ISN) stamped in the ack-num field for the ServerNIC
#       to pick up and use as the translation anchor.
#   Subsequent data/ACK/FIN packets are transparently forwarded with only Ethernet
#   header rewrites — no seq/ack changes at the ClientNIC.
#
# The script blocks in the foreground. Press Ctrl+C to stop.

set -uo pipefail

REPO_PATH="/home/ec2-user/zero-rtt-tcp"
DPDK_BUILD="$REPO_PATH/src/clientnic/dpdk-forwarder/builddir"
BINARY="$DPDK_BUILD/clientnic-dpdk-forwarder"
SERVER_PORT=8080
# Number of contiguous app ports to 0-RTT-process (SERVER_PORT .. +PORT_COUNT-1).
# Must match the load spread (LOAD_PORTS) and the ServerNIC --port-count.
PORT_COUNT="${PORT_COUNT:-1}"
PORT_HI=$(( SERVER_PORT + PORT_COUNT - 1 ))
REGION="eu-central-1"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}"; }

# ─── Cleanup ──────────────────────────────────────────────────────────────────
log "Killing any leftover clientnic-dpdk-forwarder/tcpdump processes..."
pkill -x clientnic-dpdk-forwarder 2>/dev/null || true
pkill tcpdump 2>/dev/null || true
sudo iptables -F FORWARD 2>/dev/null || true
sudo iptables -F OUTPUT 2>/dev/null || true
rm -f /tmp/client_side.pcap /tmp/server_side.pcap
sleep 1

# ─── Pull latest code ─────────────────────────────────────────────────────────
log "Syncing code to origin/main (hard reset — discards VM-local drift)..."
sudo -u ec2-user git -C "$REPO_PATH" fetch origin main 2>&1 \
    && sudo -u ec2-user git -C "$REPO_PATH" reset --hard origin/main 2>&1 \
    || log "WARNING: git sync failed — building from current checkout"

# ─── Build (optional) ─────────────────────────────────────────────────────────
if [ "${SKIP_BUILD:-0}" = "1" ]; then
    log "SKIP_BUILD=1 — skipping meson+ninja build."
    if [ ! -x "$BINARY" ]; then
        echo -e "${RED}ERROR: Binary not found at $BINARY${NC}"
        exit 1
    fi
    log "Using existing binary: $BINARY"
else
    log "Building clientnic-dpdk-forwarder (set SKIP_BUILD=1 to skip)..."
    export PATH=/usr/local/bin:$PATH
    export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig
    cd "$REPO_PATH/src/clientnic/dpdk-forwarder"
    rm -rf builddir
    /usr/local/bin/meson setup builddir 2>&1 \
        && cd builddir && /usr/local/bin/ninja 2>&1 \
        && log "Build succeeded." \
        || { echo -e "${RED}ERROR: Build failed.${NC}"; exit 1; }
    cd "$REPO_PATH"
fi

# ─── Discover gateway MAC ─────────────────────────────────────────────────────
# ServerNIC's eth1 MAC (secondary ENI, Middle subnet, DPDK port) is the next hop
# for ClientNIC eth1 (DPDK-bound, Middle subnet).
# eth1 is DPDK-controlled so the kernel can't ARP for it — we read the MAC from
# the EC2 API instead (DeviceIndex=1 of the ServerNIC instance).
GW_MAC="${1:-}"
if [ -z "$GW_MAC" ]; then
    log "Discovering ServerNIC eth1 MAC via EC2 API..."
    GW_MAC=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=smartnics-servernic" "Name=instance-state-name,Values=running" \
        --query "Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==\`1\`].MacAddress" \
        --output text --region "$REGION" 2>/dev/null | tr -d '[:space:]')
fi
if [ -z "$GW_MAC" ] || [ "$GW_MAC" = "None" ]; then
    echo -e "${RED}ERROR: Could not determine gateway MAC.${NC}"
    echo "Get from EC2 API (DeviceIndex=1 of smartnics-servernic) or pass as: $0 <gw-mac>"
    exit 1
fi
log "Gateway MAC (ServerNIC eth1, Middle subnet DPDK port): $GW_MAC"

# ─── Discover our own DPDK port MACs ──────────────────────────────────────────
# The binary maps roles to DPDK ports by matching each port's MAC against these,
# because port IDs follow PCI enumeration order rather than ENI device_index.
#   device_index=2 (Client subnet) → client-facing port
#   device_index=1 (Middle subnet) → ServerNIC-facing port
own_eni_mac() {
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=smartnics-clientnic" "Name=instance-state-name,Values=running" \
        --query "Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==\`$1\`].MacAddress" \
        --output text --region "$REGION" 2>/dev/null | tr -d '[:space:]'
}

CLIENT_PORT_MAC="${CLIENT_PORT_MAC:-}"
SERVER_PORT_MAC="${SERVER_PORT_MAC:-}"
[ -z "$CLIENT_PORT_MAC" ] && { log "Discovering our client-facing ENI MAC (DeviceIndex=2)..."; CLIENT_PORT_MAC=$(own_eni_mac 2); }
[ -z "$SERVER_PORT_MAC" ] && { log "Discovering our ServerNIC-facing ENI MAC (DeviceIndex=1)..."; SERVER_PORT_MAC=$(own_eni_mac 1); }

for _v in CLIENT_PORT_MAC SERVER_PORT_MAC; do
    if [ -z "${!_v}" ] || [ "${!_v}" = "None" ]; then
        echo -e "${RED}ERROR: Could not determine $_v (ClientNIC's own ENI MAC).${NC}"
        echo "Get it from the EC2 API (DeviceIndex 2 / 1 of smartnics-clientnic) or pass via the $_v env var."
        exit 1
    fi
done
log "Our client-facing port MAC (eth2):     $CLIENT_PORT_MAC"
log "Our ServerNIC-facing port MAC (eth1):  $SERVER_PORT_MAC"

# ─── IP forwarding check ──────────────────────────────────────────────────────
FWRD=$(cat /proc/sys/net/ipv4/ip_forward)
if [ "$FWRD" != "1" ]; then
    log "WARNING: IP forwarding not enabled — enabling now..."
    sudo sysctl -w net.ipv4.ip_forward=1
fi
log "IP forwarding: enabled"

# No kernel-side NIC tuning here: both data-plane ports are DPDK-owned (vfio-pci)
# and invisible to ethtool/ip, and eth0 is now the kernel/SSM management ENI that
# carries no data-plane traffic. GRO/LRO coalescing and qdisc depth were AF_PACKET
# concerns; DPDK bypasses both. No tcpdump either — the client-side capture is
# taken on the Client VM's own eth0 (see run_core.sh).

# ─── Cleanup on exit ──────────────────────────────────────────────────────────
cleanup() {
    echo ""
    log "Stopping DPDK forwarder binary..."
    sudo iptables -F FORWARD 2>/dev/null || true
    sudo iptables -F OUTPUT 2>/dev/null || true
    sleep 1

    echo ""
    echo "─── Run validator (on the CLIENT VM, not here) ──────────────"
    echo "  The client-side pcap is captured on the Client VM's eth0."
    echo "  cp $REPO_PATH/src/clientnic/validate_0rtt_capture.py /tmp/"
    echo "  python3 /tmp/validate_0rtt_capture.py \\"
    echo "    --client-pcap /tmp/client_side.pcap"
    echo "─────────────────────────────────────────────────────────────"
}
trap cleanup EXIT

# ─── Start DPDK forwarder binary (foreground) ────────────────────────────────
log "Starting clientnic-dpdk-forwarder — transparent forwarding with V-stamp. Press Ctrl+C to stop."
log "  --port=$SERVER_PORT --port-count=$PORT_COUNT --gw-mac=$GW_MAC"
log "  --client-port-mac=$CLIENT_PORT_MAC --server-port-mac=$SERVER_PORT_MAC"
echo ""
exec "$BINARY" -l 0 -- \
    --port="$SERVER_PORT" \
    --port-count="$PORT_COUNT" \
    --gw-mac="$GW_MAC" \
    --client-port-mac="$CLIENT_PORT_MAC" \
    --server-port-mac="$SERVER_PORT_MAC"
