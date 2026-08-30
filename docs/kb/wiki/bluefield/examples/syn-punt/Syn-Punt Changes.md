---
type: Wiki Entry
title: "Changes Made to SYN Punt Application"
description: "Files named docaflow.c and docaflow.h conflicted with official DOCA library headers, causing compilation failures."
tags: [bluefield, examples, syn-punt]
timestamp: 2026-05-23T16:09:41+03:00
---

Source: `infra/bluefield/examples/syn-punt/CHANGES.md`

# Changes Made to SYN Punt Application

## Issue 1: Filename Conflict with DOCA Libraries ✅ FIXED

### Problem
Files named `doca_flow.c` and `doca_flow.h` conflicted with official DOCA library headers, causing compilation failures.

### Solution
Renamed files to avoid conflicts:
- `src/doca_flow.c` → `src/doca_flow_handler.c`
- `src/doca_flow.h` → `src/doca_flow_handler.h`

### Files Updated
1. **src/doca_flow_handler.h**: Updated header guards
   ```c
   #ifndef SYN_PUNT_DOCA_FLOW_HANDLER_H
   #define SYN_PUNT_DOCA_FLOW_HANDLER_H
   ```

2. **src/doca_flow_handler.c**: Updated include
   ```c
   #include "doca_flow_handler.h"
   ```

3. **src/main.c**: Updated include
   ```c
   #include "doca_flow_handler.h"
   ```

4. **meson.build**: Updated source file list
   ```python
   sources = [
       'src/main.c',
       'src/utils.c',
       'src/dpdk_init.c',
       'src/doca_flow_handler.c',  # ← Changed
       'src/packet_parser.c',
       'src/packet_processor.c',
   ]
   ```

---

## Issue 2: Incorrect Network Topology ✅ FIXED

### Problem
Original documentation assumed SF-to-SF topology, but actual lab setup is:
```
Host VM → pf0hpf → BF3 DPU → p0 → Tofino
```

Where:
- **SF0** is already used for SSH management (cannot use for application)
- **pf0hpf** is the PF representor (receives from Host VM)
- **p0** is physical port (sends to Tofino switch)
- **OVS bridge is REQUIRED** to connect pf0hpf ↔ p0

### Solution
Created topology-specific documentation and setup scripts.

### New Files Created

1. **ovs_setup.sh** (New)
   - Automated OVS bridge creation
   - Connects pf0hpf and p0 interfaces
   - Configures OpenFlow rules for normal forwarding
   - Usage: `sudo ./ovs_setup.sh`

2. **TOPOLOGY.md** (New)
   - Detailed network topology diagrams
   - Interface descriptions (pf0hpf, p0, SF0)
   - Packet flow diagrams (fast path vs exception path)
   - Troubleshooting guide for network issues
   - DPDK port mapping reference

3. **QUICKSTART.md** (New)
   - Step-by-step guide for your specific lab setup
   - OVS setup as mandatory first step
   - Testing procedures from Host VM
   - Expected output examples
   - Common troubleshooting

### Files Updated

4. **docker_setup.sh**
   - Removed SF creation section (SF0 already in use)
   - Added network interface detection
   - Added topology information display
   - Shows pf0hpf and p0 availability

---

## Complete File List

### Core Application (C source)
```
src/
├── main.c                  (286 lines) - Entry point
├── utils.{c,h}             (92 lines)  - Common utilities
├── dpdk_init.{c,h}         (180 lines) - DPDK initialization
├── doca_flow_handler.{c,h} (187 lines) - DOCA Flow (RENAMED)
├── packet_parser.{c,h}     (124 lines) - Packet parsing
└── packet_processor.{c,h}  (106 lines) - Packet processing
```

### Build & Scripts
```
├── meson.build            (43 lines)  - Build config (UPDATED)
├── run.sh                 (85 lines)  - Quick launch
├── ovs_setup.sh           (135 lines) - OVS bridge setup (NEW)
└── docker_setup.sh        (158 lines) - Docker setup (UPDATED)
```

### Documentation
```
├── README.md              (523 lines) - Main documentation
├── TOPOLOGY.md            (287 lines) - Network topology (NEW)
├── QUICKSTART.md          (186 lines) - Quick start guide (NEW)
└── CHANGES.md             (This file) - Change log (NEW)
```

### Tests
```
tests/
├── test_sender.py         (218 lines) - Packet generator
└── test_verify.sh         (168 lines) - Automated tests
```

**Total**: 20 files, ~2,400 lines of code + documentation

---

## How to Use (Your Specific Setup)

### 1. Setup OVS Bridge (REQUIRED!)
```bash
cd examples/syn-punt
sudo ./ovs_setup.sh
```

This creates the bridge connecting pf0hpf ↔ p0.

### 2. Build Application
```bash
meson setup build
ninja -C build
```

### 3. Run Application
```bash
sudo ./run.sh
```

### 4. Test from Host VM
```bash
# Generate SYN packets
hping3 -S -p 80 <tofino_ip> -c 10
```

### 5. Expected Output
```
=== SYN Packet Detected ===
  ETH: aa:bb:cc:dd:ee:ff -> 00:11:22:33:44:55
  IP:  192.168.1.100 -> 10.0.0.2
  TCP: 54321 -> 80
  Seq: 1000, Ack: 0
  Flags: SYN
===========================
```

---

## Key Points for Your Setup

✅ **No SFs needed** - Uses pf0hpf and p0 directly
✅ **SF0 untouched** - Remains available for SSH
✅ **OVS bridge required** - Connects pf0hpf ↔ p0
✅ **Container network** - Use `--network host` for Docker
✅ **Traffic path** - Host VM → pf0hpf → app → p0 → Tofino

---

## Testing Reference

### From Host VM
```bash
# SYN packets (should be printed)
hping3 -S -p 80 <tofino_ip> -c 10

# Non-SYN packets (should be silent/fast-forwarded)
hping3 -A -p 80 <tofino_ip> -c 100
```

### On DPU
```bash
# Monitor pf0hpf (from Host VM)
sudo tcpdump -i pf0hpf -n 'tcp[tcpflags] & tcp-syn != 0'

# Monitor p0 (to Tofino)
sudo tcpdump -i p0 -n 'tcp[tcpflags] & tcp-syn != 0'
```

---

## References

| Document | Purpose |
|----------|---------|
| **QUICKSTART.md** | Start here for your lab setup |
| **TOPOLOGY.md** | Understand network architecture |
| **README.md** | Full documentation |
| **ovs_setup.sh** | Setup OVS bridge (run first!) |

---

## Summary of Fixes

| Issue | Status | Files Changed |
|-------|--------|---------------|
| Filename conflict | ✅ Fixed | 4 files renamed/updated |
| Wrong topology docs | ✅ Fixed | 3 new docs, 1 script updated |
| Missing OVS setup | ✅ Fixed | ovs_setup.sh created |
| SF0 assumption | ✅ Fixed | docker_setup.sh updated |

**All issues resolved!** Application is now ready for your specific lab topology.
