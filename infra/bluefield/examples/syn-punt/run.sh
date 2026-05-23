#!/bin/bash
#
# Quick launch script for SYN Punt Application
#
# Usage: sudo ./run.sh [port_id] [timeout]
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

# Default values
PORT_ID="${1:-0}"
TIMEOUT="${2:-0}"
BINARY="./build/syn_punt"

# Check if binary exists
if [ ! -f "$BINARY" ]; then
    print_error "Binary not found: $BINARY"
    echo ""
    echo "Build the application first:"
    echo "  meson setup build"
    echo "  ninja -C build"
    exit 1
fi

print_success "Found binary: $BINARY"

# Check hugepages
HUGEPAGES=$(cat /proc/meminfo | grep HugePages_Total | awk '{print $2}')
if [ "$HUGEPAGES" -lt 512 ]; then
    print_info "Configuring hugepages..."
    sysctl -w vm.nr_hugepages=2048
    print_success "Hugepages configured"
fi

# Detect PCI device
print_info "Detecting Mellanox devices..."

# Try to find Mellanox PCI device
PCI_DEVICE=$(lspci -Dd 15b3: | head -n1 | awk '{print $1}')

if [ -z "$PCI_DEVICE" ]; then
    print_error "No Mellanox device found"
    echo ""
    echo "Available PCI devices:"
    lspci | grep -i network
    exit 1
fi

print_success "Found Mellanox device: $PCI_DEVICE"

# EAL arguments
EAL_ARGS="-l 0-1 -a $PCI_DEVICE"

# Application arguments
APP_ARGS="-p $PORT_ID"
if [ "$TIMEOUT" -ne 0 ]; then
    APP_ARGS="$APP_ARGS -t $TIMEOUT"
fi

echo ""
echo "======================================"
echo "SYN Punt Application"
echo "======================================"
echo "  PCI Device: $PCI_DEVICE"
echo "  Port ID:    $PORT_ID"
echo "  Timeout:    ${TIMEOUT}s (0 = infinite)"
echo "  CPU Cores:  0-1"
echo "======================================"
echo ""

# Launch application
print_info "Starting application..."
echo ""

exec "$BINARY" $EAL_ARGS -- $APP_ARGS
