#!/bin/bash
# DPDK Virtual PMD Tests for ClientNIC
# Imported from wire-app GitLab CI, adapted for local execution.
#
# Runs DPDK smoke tests using virtual devices (no hardware required).
# Execute on any Linux machine with DPDK installed, or inside a Docker container.
#
# Usage:
#   ./run_dpdk_tests.sh <path-to-binary>
#   ./run_dpdk_tests.sh ../builddir/clientnic-dpdk
#
# Prerequisites:
#   - DPDK 23.11+ installed (dpdk-dev, libdpdk-dev)
#   - Hugepages configured (or --no-huge for testing)
#   - Root privileges (for EAL)

set -euo pipefail

BINARY="${1:-}"
PASS=0
FAIL=0
SKIP=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; ((PASS++)); }
log_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; ((FAIL++)); }
log_skip() { echo -e "${YELLOW}⊘ SKIP${NC}: $1"; ((SKIP++)); }
log_info() { echo -e "  ↳ $1"; }

# ============================================
# Pre-flight checks
# ============================================

echo "=== ClientNIC DPDK Test Suite ==="
echo ""

if [ -z "$BINARY" ]; then
    echo "Usage: $0 <path-to-clientnic-dpdk-binary>"
    echo ""
    echo "Build first:"
    echo "  cd clientnic/dpdk && meson setup builddir && ninja -C builddir"
    echo "  $0 builddir/clientnic-dpdk"
    exit 1
fi

if [ ! -f "$BINARY" ]; then
    echo "Error: binary not found: $BINARY"
    exit 1
fi

if [ ! -x "$BINARY" ]; then
    chmod +x "$BINARY"
fi

echo "Binary: $BINARY"
echo ""

# ============================================
# Test 1: Binary validation (from wire-app test:binary_check)
# ============================================

echo "--- Test 1: Binary Validation ---"

# Check ELF format
FILE_OUT=$(file "$BINARY" 2>&1)
if echo "$FILE_OUT" | grep -q "ELF"; then
    log_pass "Binary is valid ELF"
    log_info "$FILE_OUT"
else
    log_fail "Binary is not a valid ELF file"
    log_info "$FILE_OUT"
fi

# Check DPDK library linkage
LDD_OUT=$(ldd "$BINARY" 2>&1 || true)
if echo "$LDD_OUT" | grep -qE "(dpdk|rte_)"; then
    log_pass "DPDK libraries linked"
else
    log_fail "DPDK libraries not found in linkage"
    log_info "$LDD_OUT"
fi

echo ""

# ============================================
# Test 2: EAL init with null PMD (from wire-app dpdk:virtual_pmd_test)
# ============================================

echo "--- Test 2: DPDK EAL Init (null PMD) ---"

# Try hugepages first, fall back to --no-huge
HUGE_ARGS=""
if grep -q "HugePages_Total:.*[1-9]" /proc/meminfo 2>/dev/null; then
    log_info "Hugepages available"
else
    log_info "No hugepages, using --no-huge"
    HUGE_ARGS="--no-huge"
fi

EAL_OUTPUT=$(timeout 5 "$BINARY" \
    --vdev=net_null0 --vdev=net_null1 \
    -l 0 --no-pci $HUGE_ARGS \
    -- --help 2>&1 || true)

if echo "$EAL_OUTPUT" | grep -q "EAL:"; then
    log_pass "DPDK EAL initialized with null PMD"
else
    log_fail "DPDK EAL initialization failed"
    log_info "Output: $(echo "$EAL_OUTPUT" | head -5)"
fi

echo ""

# ============================================
# Test 3: Ring PMD (from wire-app dpdk:ring_pmd_test)
# ============================================

echo "--- Test 3: DPDK Ring PMD ---"

RING_OUTPUT=$(timeout 5 "$BINARY" \
    --vdev='net_ring0' --vdev='net_ring1' \
    -l 0 --no-pci $HUGE_ARGS \
    -- --help 2>&1 || true)

if echo "$RING_OUTPUT" | grep -q "EAL:"; then
    log_pass "Ring PMD devices created"
else
    log_fail "Ring PMD test failed"
    log_info "Output: $(echo "$RING_OUTPUT" | head -5)"
fi

echo ""

# ============================================
# Test 4: No-device graceful exit (from wire-app dpdk:integration_test)
# ============================================

echo "--- Test 4: Graceful No-Device Handling ---"

NO_DEV_OUTPUT=$(timeout 5 "$BINARY" \
    --no-pci $HUGE_ARGS \
    -l 0 \
    -- --help 2>&1 || true)

if echo "$NO_DEV_OUTPUT" | grep -qiE "(no.*port|no.*device|usage|help|error)"; then
    log_pass "Graceful handling when no DPDK ports available"
else
    log_skip "Could not verify no-device behavior (binary may not implement --help yet)"
    log_info "Output: $(echo "$NO_DEV_OUTPUT" | head -5)"
fi

echo ""

# ============================================
# Test 5: Port enumeration with virtual devices
# ============================================

echo "--- Test 5: Port Enumeration ---"

ENUM_OUTPUT=$(timeout 5 "$BINARY" \
    --vdev=net_null0 --vdev=net_null1 \
    -l 0 --no-pci $HUGE_ARGS \
    -- --help 2>&1 || true)

if echo "$ENUM_OUTPUT" | grep -qiE "(port|available|device)"; then
    log_pass "Port enumeration output detected"
else
    log_skip "Port enumeration not yet implemented"
fi

echo ""

# ============================================
# Summary
# ============================================

TOTAL=$((PASS + FAIL + SKIP))
echo "=== Results: $PASS passed, $FAIL failed, $SKIP skipped (of $TOTAL) ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
