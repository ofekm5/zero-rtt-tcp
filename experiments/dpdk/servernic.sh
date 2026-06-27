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
# Number of contiguous app ports to translate (SERVER_PORT .. +PORT_COUNT-1).
# Must match the iperf load spread (IPERF_PORTS) and the ClientNIC --port-count.
PORT_COUNT="${PORT_COUNT:-1}"
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

# ─── Ensure correct DPDK binding ─────────────────────────────────────────────
# CDK user data binds eth1 (by OS name) to vfio-pci. On some instances the OS
# assigns the Server-subnet ENI as eth1 and the Middle-subnet ENI as eth2,
# putting the DPDK on the wrong interface. Detect and fix at startup.
#
# Correct: DeviceIndex=1 (Middle subnet, ClientNIC-facing) → vfio-pci
# Correct: DeviceIndex=2 (Server subnet) → kernel AF_PACKET
log "Checking DPDK binding (Middle subnet ENI should be vfio-pci)..."
# Accept MIDDLE_ENI_MAC from caller (run_experiment.sh has IAM access); fall back
# to EC2 API only if not provided (requires ec2:DescribeInstances on the VM).
MIDDLE_ENI_MAC="${MIDDLE_ENI_MAC:-}"
if [ -z "$MIDDLE_ENI_MAC" ] || [ "$MIDDLE_ENI_MAC" = "none" ]; then
    MIDDLE_ENI_MAC=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=smartnics-servernic" "Name=instance-state-name,Values=running" \
        --query "Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==\`1\`].MacAddress" \
        --output text --region "$REGION" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
fi

if [ -z "$MIDDLE_ENI_MAC" ] || [ "$MIDDLE_ENI_MAC" = "none" ]; then
    log "WARNING: Could not determine Middle subnet ENI MAC — skipping binding check"
else
    MIDDLE_KERNEL_IFACE=""
    for _iface in eth1 eth2 eth3; do
        [ -d /sys/class/net/$_iface ] || continue
        _mac=$(cat /sys/class/net/$_iface/address 2>/dev/null | tr '[:upper:]' '[:lower:]')
        if [ "$_mac" = "$MIDDLE_ENI_MAC" ]; then MIDDLE_KERNEL_IFACE="$_iface"; break; fi
    done

    if [ -n "$MIDDLE_KERNEL_IFACE" ]; then
        log "Middle subnet ENI ($MIDDLE_ENI_MAC) is kernel $MIDDLE_KERNEL_IFACE — rebinding..."
        CURRENT_DPDK_PCI=$(dpdk-devbind.py --status 2>/dev/null | grep "drv=vfio-pci" | awk '{print $1}' | head -1)
        if [ -n "$CURRENT_DPDK_PCI" ]; then
            dpdk-devbind.py --bind=ena "$CURRENT_DPDK_PCI" 2>/dev/null || true
            sleep 3
            log "Unbound old DPDK device $CURRENT_DPDK_PCI"
        fi
        MIDDLE_PCI=$(basename "$(readlink /sys/class/net/$MIDDLE_KERNEL_IFACE/device)")
        ip link set "$MIDDLE_KERNEL_IFACE" down
        dpdk-devbind.py --bind=vfio-pci "$MIDDLE_PCI"
        sleep 3
        log "Rebound Middle subnet ENI ($MIDDLE_PCI / $MIDDLE_KERNEL_IFACE) to vfio-pci"
    else
        log "Middle subnet ENI ($MIDDLE_ENI_MAC) not in kernel — already DPDK-bound, OK"
    fi
fi

# Detect server-facing kernel interface: first non-eth0 interface in /sys/class/net
SERVER_IFACE="eth2"
for _iface in eth1 eth2 eth3; do
    [ -d /sys/class/net/$_iface ] && SERVER_IFACE="$_iface" && break
done
log "Server-facing interface (AF_PACKET): $SERVER_IFACE"

# Raise the egress qdisc depth so the synchronized 100-flow flush/bulk burst is
# queued rather than tail-dropped (default txqueuelen 1000 -> ENOBUFS under load).
sudo ip link set "$SERVER_IFACE" txqueuelen 100000 2>/dev/null || true

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
log "  --port=$SERVER_PORT --port-count=$PORT_COUNT --gw-mac=$CLIENTNIC_GW_MAC --server-gw-mac=$SERVER_GW_MAC"
echo ""
exec "$BINARY" -l 0 -- \
    --port="$SERVER_PORT" \
    --port-count="$PORT_COUNT" \
    --gw-mac="$CLIENTNIC_GW_MAC" \
    --server-gw-mac="$SERVER_GW_MAC" \
    --client-iface=eth1 \
    --server-iface="$SERVER_IFACE"
