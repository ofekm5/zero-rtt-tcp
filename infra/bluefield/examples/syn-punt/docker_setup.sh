#!/bin/bash
#
# Docker Setup for SYN Punt Application
#
# This script helps set up the DOCA Docker environment with SF access
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

print_header "DOCA Docker Setup for SYN Punt Application"
echo ""

# Step 1: Check Docker installation
print_info "Checking Docker installation..."
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed"
    echo ""
    echo "Install Docker with:"
    echo "  curl -fsSL https://get.docker.com | sh"
    exit 1
fi
print_success "Docker is installed"

# Step 2: Check DOCA image
print_info "Checking for DOCA Docker image..."
DOCA_IMAGE="nvcr.io/nvidia/doca/doca:2.5.0-devel"

if ! docker images | grep -q "nvidia/doca"; then
    print_info "DOCA image not found locally, pulling..."
    docker pull "$DOCA_IMAGE"
    print_success "DOCA image pulled"
else
    print_success "DOCA image found"
fi

# Step 3: Network Interfaces
print_header "Network Interface Configuration"
echo ""
print_info "NOTE: SF0 is already in use for SSH management"
print_info "The syn_punt application will use pf0hpf and p0 directly"
print_info "No additional SFs needed for this setup"
echo ""

# Show current network interfaces
print_info "Available network interfaces:"
ip link show | grep -E "pf0hpf|p0|sf" | awk '{print "  "$2}' | tr -d ':'

echo ""
print_info "Topology:"
echo "  Host VM → pf0hpf → [BF3 DPU + syn_punt app] → p0 → Tofino"
echo ""

# Step 4: Configure hugepages
print_header "Hugepage Configuration"
echo ""
HUGEPAGES=$(cat /proc/meminfo | grep HugePages_Total | awk '{print $2}')
print_info "Current hugepages: $HUGEPAGES"

if [ "$HUGEPAGES" -lt 1024 ]; then
    print_info "Configuring 2048 hugepages..."
    sysctl -w vm.nr_hugepages=2048
    print_success "Hugepages configured"
fi

# Step 5: Generate docker run command
print_header "Docker Run Command"
echo ""

cat << 'EOF' > /tmp/doca_run.sh
#!/bin/bash
docker run -it --rm \
    --name doca-syn-punt \
    --privileged \
    --network host \
    -v $(pwd):/workspace \
    -v /sys/class/net:/sys/class/net \
    -v /dev/hugepages:/dev/hugepages \
    -v /dev/infiniband:/dev/infiniband \
    -w /workspace \
    nvcr.io/nvidia/doca/doca:2.5.0-devel \
    bash
EOF

chmod +x /tmp/doca_run.sh

print_success "Created Docker launch script: /tmp/doca_run.sh"
echo ""
echo "To start the DOCA container, run:"
echo -e "  ${GREEN}/tmp/doca_run.sh${NC}"
echo ""
echo "Inside the container:"
echo "  cd /workspace/examples/syn-punt"
echo "  meson setup build"
echo "  ninja -C build"
echo "  ./run.sh"
echo ""

# Step 6: Optional - Start container now
read -p "Start Docker container now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    /tmp/doca_run.sh
fi
