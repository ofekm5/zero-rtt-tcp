# Quick Start Guide - SYN Punt Application

For your specific lab topology: **Host VM → pf0hpf → BF3 DPU → p0 → Tofino**

## Prerequisites

✅ BlueField-3 DPU with DOCA SDK installed
✅ SF0 is used for SSH (don't touch it!)
✅ `pf0hpf` and `p0` interfaces available
✅ Host VM can send traffic to Tofino via DPU

## Step 1: Setup OVS Bridge (Required!)

```bash
cd examples/syn-punt

# This creates br-syn-punt bridge connecting pf0hpf ↔ p0
sudo ./ovs_setup.sh
```

**Expected output:**
```
=== OVS Bridge Setup for SYN Punt Application ===
[OK] Open vSwitch is installed
[OK] Both pf0hpf and p0 interfaces found
[OK] Bridge created
...
Traffic Flow:
  Host VM → pf0hpf → [br-syn-punt] → p0 → Tofino
```

## Step 2: Build the Application

### Option A: Native Build (on DPU ARM)
```bash
meson setup build
ninja -C build
```

### Option B: Docker Build (recommended)
```bash
# Pull and run DOCA container
docker run -it --rm \
    --privileged \
    --network host \
    -v $(pwd):/workspace \
    -v /sys/class/net:/sys/class/net \
    -v /dev/hugepages:/dev/hugepages \
    -w /workspace \
    nvcr.io/nvidia/doca/doca:2.5.0-devel \
    bash

# Inside container
cd /workspace/examples/syn-punt
meson setup build
ninja -C build
```

## Step 3: Run the Application

```bash
# Quick launch (auto-detects PCI device)
sudo ./run.sh

# Or manually specify port
sudo ./build/syn_punt -l 0-1 -a 03:00.0 -- -p 0
```

**Expected startup:**
```
=== SYN Punt Application ===
[INFO] DPDK EAL initialized successfully
[INFO] Port 0 initialized with 1 queues
[INFO] DOCA Flow initialized (mode: vnf,hws, queues: 1)
[INFO] SYN punt pipe created successfully
  - SYN packets -> RX queue 0 (exception path)
  - Other packets -> RSS (fast path)

=== Initialization Complete ===
Starting packet processor on port 0 (queue 0)
```

## Step 4: Test It

### From Host VM (Terminal 1)
```bash
# Generate TCP traffic to Tofino
ping <tofino_ip>

# Generate SYN packets specifically
hping3 -S -p 80 <tofino_ip> -c 10

# Or use curl (creates SYN on connect)
curl http://<tofino_ip>
```

### On DPU - syn_punt Output (Terminal 2)
```
=== SYN Packet Detected ===
  ETH: aa:bb:cc:dd:ee:ff -> 00:11:22:33:44:55
  IP:  192.168.1.100 -> 10.0.0.2
  TCP: 54321 -> 80
  Seq: 1000, Ack: 0
  Flags: SYN
===========================

Statistics: Total=10, SYN=10
```

### Verify with tcpdump (Terminal 3)
```bash
# Monitor pf0hpf (from Host VM)
sudo tcpdump -i pf0hpf -n 'tcp[tcpflags] & tcp-syn != 0'

# Monitor p0 (to Tofino)
sudo tcpdump -i p0 -n 'tcp[tcpflags] & tcp-syn != 0'
```

## Verify Fast Path

```bash
# Send 1000 non-SYN packets from Host VM
hping3 -A -p 80 <tofino_ip> -c 1000

# Expected: Application shows NO output (packets fast-forwarded in hardware)
# Statistics should show: Total=1000, SYN=0
```

## Troubleshooting

### Problem: "No DPDK ports found"
```bash
# Check PCI device
lspci | grep Mellanox

# Find correct PCI address
dpdk-testpmd -l 0-1 -- --list
```

### Problem: "Packets not reaching application"
```bash
# 1. Verify OVS bridge
sudo ovs-vsctl show

# 2. Verify ports are in bridge
sudo ovs-vsctl list-ports br-syn-punt

# 3. Verify interfaces are UP
ip link show pf0hpf
ip link show p0
```

### Problem: "No SYN packets detected"
```bash
# 1. Verify traffic is entering pf0hpf
sudo tcpdump -i pf0hpf -n

# 2. Test locally on DPU
hping3 -S -p 80 127.0.0.1 -c 5
```

## Understanding the Output

### SYN Packets (Punted to Software)
- ✅ Printed with full 5-tuple information
- ✅ Processed by ARM cores (~10-50 µs)
- ✅ Counted in statistics

### Non-SYN Packets (Hardware Fast-Path)
- ❌ NOT printed (silent)
- ✅ Forwarded by eSwitch (~1 µs)
- ✅ Counted in statistics under "Total"

### Performance
```
SYN packet processing:     ~10-50 µs per packet
Non-SYN fast-path:         ~1 µs per packet (hardware)
Throughput (SYN packets):  ~1M packets/sec per core
Throughput (non-SYN):      Line rate (25 Gbps)
```

## Cleanup

```bash
# Stop application: Ctrl+C

# Remove OVS bridge
sudo ovs-vsctl del-br br-syn-punt

# Stop Docker container
exit
```

## Next Steps

1. **Read full documentation**: `README.md`
2. **Understand topology**: `TOPOLOGY.md`
3. **Customize for your use case**: Modify `src/doca_flow_handler.c`

## Quick Reference

| File | Purpose |
|------|---------|
| `ovs_setup.sh` | Setup OVS bridge (pf0hpf ↔ p0) |
| `run.sh` | Quick launch script |
| `docker_setup.sh` | Docker container setup |
| `tests/test_sender.py` | Generate test packets |
| `TOPOLOGY.md` | Network topology details |
| `README.md` | Full documentation |

---

**Your Lab Setup:**
```
Host VM (eth0)
    ↓ PCIe
pf0hpf (DPU representor)
    ↓ OVS bridge: br-syn-punt
    ↓ syn_punt app intercepts here
p0 (DPU physical port)
    ↓ 25G cable
Tofino Switch
```

**Need help?** Check `TOPOLOGY.md` for detailed diagrams and troubleshooting.
