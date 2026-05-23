#!/bin/bash
#
# SYN Punt Application - Verification Test
#
# This script verifies that the SYN punt application is working correctly:
# 1. Checks if application is running
# 2. Sends test packets
# 3. Verifies that SYN packets appear in application output
# 4. Verifies that non-SYN packets are not printed (fast-forwarded)
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="syn_punt"
TEST_INTERFACE="${1:-eth0}"
LOG_FILE="/tmp/syn_punt_test.log"
APP_OUTPUT="/tmp/syn_punt_output.log"

echo "======================================"
echo "SYN Punt Application - Verification"
echo "======================================"
echo ""

# Function to print colored messages
print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[*]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

# Check if interface exists
if ! ip link show "$TEST_INTERFACE" &> /dev/null; then
    print_error "Interface '$TEST_INTERFACE' not found"
    echo "Available interfaces:"
    ip link show | grep '^[0-9]' | cut -d: -f2 | tr -d ' '
    exit 1
fi

print_success "Interface $TEST_INTERFACE found"

# Check if test_sender.py exists
if [ ! -f "tests/test_sender.py" ]; then
    print_error "test_sender.py not found in tests/ directory"
    exit 1
fi

print_success "Test sender script found"

# Check if Python and scapy are available
if ! python3 -c "import scapy" 2>/dev/null; then
    print_error "Python scapy module not installed"
    echo "Install with: pip3 install scapy"
    exit 1
fi

print_success "Python and scapy available"

# Check if application binary exists
if [ ! -f "build/$APP_NAME" ]; then
    print_error "Application binary not found at build/$APP_NAME"
    echo "Build the application first with:"
    echo "  meson setup build"
    echo "  ninja -C build"
    exit 1
fi

print_success "Application binary found"

echo ""
print_info "Starting test sequence..."
echo ""

# Clean up old log files
rm -f "$LOG_FILE" "$APP_OUTPUT"

# Start the application in background (if not already running)
if pgrep -x "$APP_NAME" > /dev/null; then
    print_info "Application already running (PID: $(pgrep -x $APP_NAME))"
    APP_PID=$(pgrep -x "$APP_NAME")
else
    print_info "Starting application..."
    # Note: Adjust EAL arguments as needed for your setup
    sudo ./build/$APP_NAME -l 0-1 -a 03:00.0 -- -p 0 > "$APP_OUTPUT" 2>&1 &
    APP_PID=$!

    # Wait for application to initialize
    sleep 5

    if ! kill -0 $APP_PID 2>/dev/null; then
        print_error "Application failed to start"
        cat "$APP_OUTPUT"
        exit 1
    fi

    print_success "Application started (PID: $APP_PID)"
fi

# Send test packets
print_info "Sending test packets..."
python3 tests/test_sender.py "$TEST_INTERFACE" \
    --syn-count 5 \
    --syn-ack-count 5 \
    --data-count 20 \
    --udp-count 10 \
    > "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    print_error "Failed to send test packets"
    cat "$LOG_FILE"
    exit 1
fi

print_success "Test packets sent"

# Wait for packets to be processed
sleep 2

# Analyze results
echo ""
print_info "Analyzing results..."
echo ""

# Count SYN packets in application output
SYN_COUNT=$(grep -c "=== SYN Packet Detected ===" "$APP_OUTPUT" || echo "0")

echo "Results:"
echo "  - SYN packets detected by app: $SYN_COUNT"
echo "  - Expected SYN packets: 5"

# Verify results
SUCCESS=true

if [ "$SYN_COUNT" -ge 5 ]; then
    print_success "SYN packets were correctly punted to application"
else
    print_error "Expected at least 5 SYN packets, but found $SYN_COUNT"
    SUCCESS=false
fi

# Check that non-SYN packets were NOT printed (fast-forwarded)
# We sent 35 non-SYN packets (5 SYN-ACK + 20 data + 10 UDP)
# They should NOT appear in the output as "SYN Packet Detected"
TOTAL_LINES=$(wc -l < "$APP_OUTPUT")
if [ "$TOTAL_LINES" -lt 100 ]; then
    print_success "Non-SYN packets appear to be fast-forwarded (output is concise)"
else
    print_error "Too many lines in output, non-SYN packets may not be fast-forwarded"
    SUCCESS=false
fi

echo ""
echo "======================================"
if [ "$SUCCESS" = true ]; then
    print_success "All tests passed!"
    echo "======================================"
    echo ""
    echo "Application is working correctly:"
    echo "  ✓ SYN packets are punted to application"
    echo "  ✓ Non-SYN packets are fast-forwarded"
    exit 0
else
    print_error "Some tests failed!"
    echo "======================================"
    echo ""
    echo "Check the application output:"
    echo "  cat $APP_OUTPUT"
    exit 1
fi
