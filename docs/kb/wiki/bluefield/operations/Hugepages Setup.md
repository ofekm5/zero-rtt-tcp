---
type: Wiki Entry
title: "Hugepages Setup"
description: "Hugepages are required for DPDK applications on BlueField-3. This document describes how to configure and verify hugepage allocation."
tags: [bluefield, operations]
timestamp: 2026-05-23T16:09:41+03:00
---

Source: `infra/bluefield/docs/03-operations/hugepages-setup.md`

# Hugepages Setup

## Overview

Hugepages are required for DPDK applications on BlueField-3. This document describes how to configure and verify hugepage allocation.

## Quick Setup

```bash
# Check if /dev/hugepages is mounted
mountpoint -q /dev/hugepages

# If not mounted, mount it
sudo mkdir -p /dev/hugepages
sudo mount -t hugetlbfs nodev /dev/hugepages

# Allocate 1024 hugepages (2MB each = 2GB total)
echo 1024 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

# Verify allocation
cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
grep HugePages /proc/meminfo
```

## Persistent Configuration

### Method 1: sysctl

Add to `/etc/sysctl.conf`:

```
vm.nr_hugepages = 1024
```

Apply changes:

```bash
sudo sysctl -p
```

### Method 2: systemd Service

Create `/etc/systemd/system/hugepages.service`:

```ini
[Unit]
Description=Configure Hugepages
DefaultDependencies=no
Before=sysinit.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo 1024 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages'

[Install]
WantedBy=sysinit.target
```

Enable the service:

```bash
sudo systemctl enable hugepages.service
sudo systemctl start hugepages.service
```

## Automated Setup Script

The script from `mcp/architecture/allocate_hugepages.sh` performs these operations:

```bash
#!/usr/bin/env bash
set -euo pipefail

PAGES_2M="${1:-1024}"

# Step 1: Mount hugepages filesystem
if ! mountpoint -q /dev/hugepages; then
  sudo mkdir -p /dev/hugepages
  sudo mount -t hugetlbfs nodev /dev/hugepages
fi

# Step 2: Allocate hugepages
echo "$PAGES_2M" | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

# Step 3: Verify
echo "=== Hugepages (2MB) ==="
echo "Total configured: $(cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages)"
echo "Currently free: $(grep HugePages_Free /proc/meminfo | awk '{print $2}')"
```

## Verification Commands

### Check Mount Status

```bash
mount | grep hugepages
# Expected: hugetlbfs on /dev/hugepages type hugetlbfs (rw,relatime,pagesize=2M)
```

### Check Allocation

```bash
# Total configured
cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

# Currently free
cat /sys/kernel/mm/hugepages/hugepages-2048kB/free_hugepages

# Summary from meminfo
grep Huge /proc/meminfo
```

Expected output:

```
HugePages_Total:    1024
HugePages_Free:     1024
HugePages_Rsvd:        0
HugePages_Surp:        0
Hugepagesize:       2048 kB
```

## Sizing Guidelines

| Application Type | Recommended Size | Pages (2MB) |
|-----------------|------------------|-------------|
| **Small test** | 512 MB | 256 |
| **Development** | 2 GB | 1024 |
| **Production** | 4-8 GB | 2048-4096 |

Calculate required pages:

```bash
# Formula: (desired_size_in_MB) / 2
# Example: 4 GB = 4096 MB / 2 = 2048 pages
```

## Troubleshooting

### Allocation Fails

```bash
# Check available memory
free -h

# Check kernel messages
dmesg | grep -i hugepage
```

**Common causes**:
- Insufficient free memory
- Memory fragmentation
- Kernel configuration doesn't support hugepages

### DPDK Application Fails to Start

```bash
# Check DPDK can access hugepages
ls -la /dev/hugepages

# Verify permissions
sudo chmod 755 /dev/hugepages
```

### Insufficient Hugepages

If DPDK reports insufficient hugepages:

```bash
# Increase allocation
echo 2048 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

# Or restart with smaller memory pool in application
```

## DPDK Configuration

In your DPDK application, specify hugepage requirements:

```c
// Create mempool with hugepages
struct rte_mempool *pool = rte_pktmbuf_pool_create(
    "mbuf_pool",
    NUM_MBUFS,        // Number of buffers
    MBUF_CACHE_SIZE,
    0,
    RTE_MBUF_DEFAULT_BUF_SIZE,
    socket_id         // NUMA socket
);
```

DPDK EAL will automatically use hugepages from `/dev/hugepages`.

## Key Takeaways

1. **Hugepages required** for DPDK applications
2. **Mount `/dev/hugepages`** before allocation
3. **Allocate via sysfs**: `/sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages`
4. **Verify with `/proc/meminfo`**
5. **Size based on application**: 2-8 GB typical
6. **Make persistent** via sysctl or systemd service

## Next Steps
- See [[Performance Tuning]] for optimization
- Read [[DPDK Integration]] for DPDK setup
- Check [[Debugging Guide]] for troubleshooting
