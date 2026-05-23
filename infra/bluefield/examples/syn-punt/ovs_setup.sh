#!/bin/bash
#
# OVS Bridge Configuration for SYN Punt Application
#
# Topology:
#   Host VM → pf0hpf → [BF3 DPU + syn_punt app] → p0 → Tofino
#
# This script creates an OVS bridge to connect pf0hpf and p0, allowing the
# syn_punt application to intercept traffic between the host and Tofino switch.
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

print_header "OVS Bridge Setup for SYN Punt Application"
echo ""

# Configuration
BRIDGE_NAME="br-syn-punt"
PF_REPR="pf0hpf"    # Representor to Host VM
PHYS_PORT="p0"      # Physical port to Tofino

# Check if OVS is installed
if ! command -v ovs-vsctl &> /dev/null; then
    print_error "Open vSwitch is not installed"
    echo ""
    echo "Install with:"
    echo "  apt-get update"
    echo "  apt-get install openvswitch-switch"
    exit 1
fi

print_success "Open vSwitch is installed"

# Check if OVS is running
if ! systemctl is-active --quiet openvswitch-switch; then
    print_info "Starting Open vSwitch..."
    systemctl start openvswitch-switch
fi

print_success "Open vSwitch is running"

# Check if ports exist
print_info "Checking network interfaces..."

if ! ip link show "$PF_REPR" &> /dev/null; then
    print_error "Interface $PF_REPR not found"
    echo ""
    echo "Available interfaces:"
    ip link show | grep '^[0-9]' | awk '{print $2}' | tr -d ':'
    exit 1
fi

if ! ip link show "$PHYS_PORT" &> /dev/null; then
    print_error "Interface $PHYS_PORT not found"
    echo ""
    echo "Available interfaces:"
    ip link show | grep '^[0-9]' | awk '{print $2}' | tr -d ':'
    exit 1
fi

print_success "Both $PF_REPR and $PHYS_PORT interfaces found"

# Remove existing bridge if it exists
if ovs-vsctl br-exists "$BRIDGE_NAME" 2>/dev/null; then
    print_info "Removing existing bridge $BRIDGE_NAME..."
    ovs-vsctl del-br "$BRIDGE_NAME"
fi

# Create OVS bridge
print_info "Creating OVS bridge: $BRIDGE_NAME"
ovs-vsctl add-br "$BRIDGE_NAME"
print_success "Bridge created"

# Add ports to bridge
print_info "Adding $PF_REPR to bridge..."
ovs-vsctl add-port "$BRIDGE_NAME" "$PF_REPR"
print_success "$PF_REPR added"

print_info "Adding $PHYS_PORT to bridge..."
ovs-vsctl add-port "$BRIDGE_NAME" "$PHYS_PORT"
print_success "$PHYS_PORT added"

# Bring up all interfaces
print_info "Bringing up interfaces..."
ip link set dev "$BRIDGE_NAME" up
ip link set dev "$PF_REPR" up
ip link set dev "$PHYS_PORT" up
print_success "All interfaces are up"

# Configure OpenFlow rules
print_header "Configuring OpenFlow Rules"
echo ""

# Delete existing flows
ovs-ofctl del-flows "$BRIDGE_NAME"

# Normal forwarding as baseline (lowest priority)
print_info "Adding baseline forwarding rule..."
ovs-ofctl add-flow "$BRIDGE_NAME" "priority=0,actions=normal"

print_success "OpenFlow rules configured"

# Display bridge configuration
print_header "Bridge Configuration"
echo ""
ovs-vsctl show | grep -A 10 "$BRIDGE_NAME"

echo ""
print_header "Port Configuration"
ovs-ofctl show "$BRIDGE_NAME"

echo ""
print_header "Flow Rules"
ovs-ofctl dump-flows "$BRIDGE_NAME"

echo ""
print_success "OVS bridge setup complete!"
echo ""
echo "=========================================="
echo "Traffic Flow:"
echo "  Host VM → $PF_REPR → [$BRIDGE_NAME] → $PHYS_PORT → Tofino"
echo "  Tofino  → $PHYS_PORT → [$BRIDGE_NAME] → $PF_REPR → Host VM"
echo "=========================================="
echo ""
echo "All traffic between Host VM and Tofino now flows through the bridge."
echo "The syn_punt application will intercept packets on this path."
echo ""
echo "Next steps:"
echo "  1. Run the syn_punt application:"
echo "     sudo ./run.sh"
echo ""
echo "  2. Verify traffic flow:"
echo "     sudo tcpdump -i $PF_REPR -n"
echo "     sudo tcpdump -i $PHYS_PORT -n"
echo ""
echo "To remove this configuration:"
echo "  sudo ovs-vsctl del-br $BRIDGE_NAME"
