#!/usr/bin/env bash
# Run on the ServerNIC VM (servernic-dpdk binary).
#
# ENI roles (design D6):
#   eth0: kernel/SSM management
#   eth1: ClientNIC-facing DPDK port (vfio-pci, bound at boot by CDK user data)
#   eth2: Server-facing DPDK port (vfio-pci, bound at boot by CDK user data)
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

REPO_PATH="/home/ec2-user/zero-rtt-tcp"
DPDK_BUILD="$REPO_PATH/src/servernic/dpdk/builddir"
BINARY="$DPDK_BUILD/servernic-dpdk"
SERVER_PORT=8080
# Number of contiguous app ports to translate (SERVER_PORT .. +PORT_COUNT-1).
# Must match the load spread (LOAD_PORTS) and the ClientNIC --port-count.
PORT_COUNT="${PORT_COUNT:-1}"
REGION="eu-central-1"
# Emulated one-way WAN latency held on the ClientNIC-facing (middle-leg) TX path.
# roadmap.md F2 / measurement-methodology-review.md §E: `tc` cannot reach a
# vfio-pci port, so the delay lives inside the forwarder. Must equal half of the
# baseline stack's NETEM_RTT_MS, and must match the ClientNIC's value — the two
# together make one modelled round trip. 0 = no emulated WAN.
WAN_DELAY_US="${WAN_DELAY_US:-50000}"

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
# REPO_REF defaults to main; override to run a branch (e.g. to validate a
# harness change on real infra before merging it).
REPO_REF="${REPO_REF:-main}"
log "Syncing code to origin/${REPO_REF} (hard reset — discards VM-local drift)..."
sudo -u ec2-user git -C "$REPO_PATH" fetch origin "$REPO_REF" 2>&1 \
    && sudo -u ec2-user git -C "$REPO_PATH" reset --hard "origin/$REPO_REF" 2>&1 \
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
    cd "$REPO_PATH/src/servernic/dpdk"
    rm -rf builddir
    /usr/local/bin/meson setup builddir 2>&1 \
        && cd builddir && /usr/local/bin/ninja 2>&1 \
        && log "Build succeeded." \
        || { echo -e "${RED}ERROR: Build failed.${NC}"; exit 1; }
    cd "$REPO_PATH"
fi

# ─── Discover gateway MACs ────────────────────────────────────────────────────
# Passed to the binary as --gw-mac: ClientNIC-side gateway MAC (ClientNIC eth1 secondary ENI, Middle subnet)
# Passed to the binary as --server-mac: Server-side peer MAC (Server eth0 MAC or subnet gateway)
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

log "ClientNIC-side gateway MAC (peer):  $CLIENTNIC_GW_MAC"
log "Server-side peer MAC (peer):        $SERVER_GW_MAC"

# ─── Discover our own DPDK port MACs ──────────────────────────────────────────
# The binary maps roles to DPDK ports by matching each port's MAC against these,
# because port IDs follow PCI enumeration order rather than ENI device_index.
#   device_index=1 (Middle subnet) → ClientNIC-facing port
#   device_index=2 (Server subnet) → Server-facing port
#
# This replaces the old "detect the Middle ENI landed on the wrong kernel name and
# rebind it" hack: role assignment no longer depends on kernel naming at all, and
# under dual-DPDK that hack would unbind whichever vfio device it found first.
own_eni_mac() {
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=smartnics-servernic" "Name=instance-state-name,Values=running" \
        --query "Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==\`$1\`].MacAddress" \
        --output text --region "$REGION" 2>/dev/null | tr -d '[:space:]'
}

CLIENT_PORT_MAC="${CLIENT_PORT_MAC:-}"
SERVER_PORT_MAC="${SERVER_PORT_MAC:-}"
[ -z "$CLIENT_PORT_MAC" ] && { log "Discovering our ClientNIC-facing ENI MAC (DeviceIndex=1)..."; CLIENT_PORT_MAC=$(own_eni_mac 1); }
[ -z "$SERVER_PORT_MAC" ] && { log "Discovering our Server-facing ENI MAC (DeviceIndex=2)..."; SERVER_PORT_MAC=$(own_eni_mac 2); }

for _v in CLIENT_PORT_MAC SERVER_PORT_MAC; do
    if [ -z "${!_v}" ] || [ "${!_v}" = "None" ]; then
        echo -e "${RED}ERROR: Could not determine $_v (ServerNIC's own ENI MAC).${NC}"
        echo "Get it from the EC2 API (DeviceIndex 1 / 2 of smartnics-servernic) or pass via the $_v env var."
        exit 1
    fi
done
log "Our ClientNIC-facing port MAC (eth1): $CLIENT_PORT_MAC"
log "Our Server-facing port MAC (eth2):    $SERVER_PORT_MAC"

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
log "  --port=$SERVER_PORT --port-count=$PORT_COUNT --gw-mac=$CLIENTNIC_GW_MAC --server-mac=$SERVER_GW_MAC"
log "  --client-port-mac=$CLIENT_PORT_MAC --server-port-mac=$SERVER_PORT_MAC"
log "  --wan-delay-us=$WAN_DELAY_US (emulated WAN, middle leg — must match ClientNIC)"
echo ""
exec "$BINARY" -l 0 -- \
    --port="$SERVER_PORT" \
    --port-count="$PORT_COUNT" \
    --gw-mac="$CLIENTNIC_GW_MAC" \
    --server-mac="$SERVER_GW_MAC" \
    --client-port-mac="$CLIENT_PORT_MAC" \
    --server-port-mac="$SERVER_PORT_MAC" \
    --wan-delay-us="$WAN_DELAY_US"
