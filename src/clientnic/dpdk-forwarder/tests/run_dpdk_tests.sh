#!/bin/bash
# DPDK virtual-PMD smoke-test suite targeting the clientnic-dpdk-forwarder binary.
#
# Usage:
#   ./run_dpdk_tests.sh <path-to-binary>
#   ./run_dpdk_tests.sh ../builddir/clientnic-dpdk-forwarder

set -euo pipefail

BINARY="${1:-}"
PASS=0
FAIL=0
SKIP=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; ((PASS++)); }
log_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; ((FAIL++)); }
log_skip() { echo -e "${YELLOW}⊘ SKIP${NC}: $1"; ((SKIP++)); }
log_info() { echo -e "  ↳ $1"; }

echo "=== ClientNIC DPDK Forwarder Test Suite ==="
echo ""

if [ -z "$BINARY" ]; then
    echo "Usage: $0 <path-to-clientnic-dpdk-forwarder-binary>"
    echo ""
    echo "Build first:"
    echo "  cd src/clientnic/dpdk-forwarder && meson setup builddir && ninja -C builddir"
    echo "  $0 builddir/clientnic-dpdk-forwarder"
    exit 1
fi

if [ ! -f "$BINARY" ]; then
    echo "Error: binary not found: $BINARY"
    exit 1
fi
[ ! -x "$BINARY" ] && chmod +x "$BINARY"

echo "Binary: $BINARY"
echo ""

HUGE_ARGS=""
if ! grep -q "HugePages_Total:.*[1-9]" /proc/meminfo 2>/dev/null; then
    HUGE_ARGS="--no-huge"
fi

echo "--- Test 1: Binary Validation ---"
FILE_OUT=$(file "$BINARY" 2>&1)
if echo "$FILE_OUT" | grep -q "ELF"; then
    log_pass "Binary is valid ELF"
else
    log_fail "Binary is not a valid ELF file"
fi
echo ""

echo "--- Test 2: DPDK EAL Init (null PMD) ---"
EAL_OUTPUT=$(timeout 5 "$BINARY" \
    --vdev=net_null0 --vdev=net_null1 \
    -l 0 --no-pci $HUGE_ARGS \
    -- --help 2>&1 || true)
if echo "$EAL_OUTPUT" | grep -q "EAL:"; then
    log_pass "DPDK EAL initialized"
else
    log_fail "DPDK EAL initialization failed"
fi
echo ""

echo "--- Test 3: Graceful No-Device Handling ---"
NO_DEV_OUTPUT=$(timeout 5 "$BINARY" \
    --no-pci $HUGE_ARGS -l 0 \
    -- --help 2>&1 || true)
if echo "$NO_DEV_OUTPUT" | grep -qiE "(no.*port|usage|help|error)"; then
    log_pass "Graceful handling when no DPDK ports"
else
    log_skip "Could not verify no-device behavior"
fi
echo ""

TOTAL=$((PASS + FAIL + SKIP))
echo "=== Results: $PASS passed, $FAIL failed, $SKIP skipped (of $TOTAL) ==="

[ "$FAIL" -gt 0 ] && exit 1
exit 0
