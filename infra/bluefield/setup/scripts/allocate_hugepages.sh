#!/usr/bin/env bash
set -euo pipefail

PAGES_2M="${1:-1024}"

log()   { echo "[INFO] $*"; }
error() { echo "[ERROR] $*" >&2; }

# Step 1: check hugepages mount
if ! mountpoint -q /dev/hugepages; then
  log "/dev/hugepages not mounted — creating and mounting hugetlbfs..."
  if sudo mkdir -p /dev/hugepages && sudo mount -t hugetlbfs nodev /dev/hugepages; then
    log "Mounted hugetlbfs on /dev/hugepages"
  else
    error "Failed to mount /dev/hugepages"
    exit 1
  fi
else
  log "/dev/hugepages already mounted"
fi

# Step 2: allocate 2MB hugepages
log "Allocating ${PAGES_2M} hugepages (2MB each)..."
if echo "$PAGES_2M" | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages >/dev/null; then
  log "Hugepage allocation request applied"
else
  error "Failed to allocate hugepages"
  exit 1
fi

# Step 3: report status
TOTAL=$(cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages 2>/dev/null || echo "N/A")
FREE=$(grep HugePages_Free /proc/meminfo | awk '{print $2}' || echo "N/A")

log "=== Hugepages (2MB) ==="
log "Total configured: $TOTAL"
log "Currently free : $FREE"
mount | grep -E "on /dev/hugepages type hugetlbfs" || error "hugetlbfs mount missing?"
