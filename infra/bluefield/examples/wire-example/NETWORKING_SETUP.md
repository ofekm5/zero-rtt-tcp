# Networking Setup for Wire-Example

## Overview

The `wire-example` application operates in **Classic DPDK Mode**, directly forwarding packets on ARM cores. It can work **with or without** OVS/smartnic mode.

## Port Architecture

When you run `sudo ./wire`, you'll see DPDK ports like:

```
Port 0: p0 (Physical uplink - external network)
Port 1: p1 (Physical uplink - secondary port)
Port 2: pf0hpf (Host PF representor)
Port 3: en3f0pf0sf10 (Subfunction representor)
...
```

## Setup Options

### Option 1: Minimal Setup (Legacy Mode)

**No subfunctions, no OVS needed**

```bash
# Wire between physical port and existing host PF
sudo ./wire -l 0-2 -- 0 2
#                      ↑   ↑
#                      p0  pf0hpf
```

**Use case:** Simple testing, maximum simplicity

---

### Option 2: With Subfunctions (Recommended)

**Modern approach with scalable subfunctions**

```bash
# 1. Enable switchdev mode
devlink dev eswitch set pci/0000:03:00.0 mode switchdev

# 2. Create subfunction for host
mlnx-sf --action create \
  --device 0000:03:00.0 \
  --sfnum 10 \
  --hwaddr 02:25:f2:00:00:10

# 3. Check created SF
mlnx-sf --action show

# 4. Run wire between physical port and SF representor
sudo ./wire -l 0-2 -- 0 3
#                      ↑   ↑
#                      p0  SF representor
```

**Use case:** Production deployments, scalability

**Benefits:**
- Can create many SFs (1000+) vs few VFs (128 max)
- Lower overhead than VFs
- Flexible resource allocation
- Modern best practice

---

### Option 3: Hybrid with OVS (Advanced)

**Classic DPDK app + OVS hardware offload**

```bash
# 1. Enable switchdev and create SFs (as in Option 2)
devlink dev eswitch set pci/0000:03:00.0 mode switchdev
mlnx-sf --action create --device 0000:03:00.0 --sfnum 10 --hwaddr 02:25:f2:00:00:10

# 2. Setup OVS bridge for OTHER traffic
ovs-vsctl add-br ovsbr0
ovs-vsctl add-port ovsbr0 p1              # Use p1 for OVS
ovs-vsctl add-port ovsbr0 en3f0pf0sf11   # Different SF

# 3. Enable hardware offload
ovs-vsctl set Open_vSwitch . other_config:hw-offload=true

# 4. Run wire app on p0 + SF10 (independent of OVS)
sudo ./wire -l 0-2 -- 0 3
```

**Use case:**
- Need custom processing on some traffic (wire app)
- Need hardware-offloaded switching on other traffic (OVS)

**Architecture:**
```
┌─────────────────────────────────────────────┐
│ Physical Port p0 ←→ Wire App ←→ SF10 (Host) │ ← Custom processing
├─────────────────────────────────────────────┤
│ Physical Port p1 ←→ OVS ←→ SF11 (Host)      │ ← Hardware offload
└─────────────────────────────────────────────┘
```

---

## Why Subfunctions Instead of VFs?

| Feature | VFs | Subfunctions (SFs) |
|---------|-----|-------------------|
| **Max Count** | ~128 | 1000+ |
| **Creation Speed** | Slow | Fast |
| **Resource Usage** | Higher | Lower |
| **Flexibility** | Limited | High |
| **NVIDIA Recommendation** | Legacy | ✅ Preferred |

---

## Answering Your Questions

### Q1: Why would I need VFs?

**You DON'T!** Use Subfunctions (SFs) instead. VFs are the older SR-IOV approach. SFs are the modern, Bluefield-3-optimized replacement.

### Q2: Could classic mode work while DPU is in smartnic mode?

**YES!** This is actually very powerful:

- **Switchdev mode** is required to create SFs
- Your **DPDK wire app** can still run and access representor ports
- You can even have **OVS running alongside** your wire app on different ports
- The wire app processes packets on ARM cores (classic DPDK)
- OVS/eSwitch handles other traffic with hardware offload

**Example Hybrid Flow:**

```
HTTP traffic (port 80):
  Network → NIC Flow Engine → Hardware offload → Host
  (Handled by OVS, <1μs latency, zero ARM CPU)

SSH traffic (port 22):
  Network → p0 → Wire App (ARM cores) → SF10 → Host
  (Custom processing, ~50-100μs latency, uses ARM)
```

---

## Typical Wire Example Setup

**For host-to-network bidirectional forwarding:**

```bash
# 1. Enable switchdev
devlink dev eswitch set pci/0000:03:00.0 mode switchdev

# 2. Create SF for host
mlnx-sf --action create \
  --device 0000:03:00.0 \
  --sfnum 10 \
  --hwaddr 02:25:f2:00:00:10

# 3. Verify ports
sudo ./wire  # Lists available ports

# Expected output:
# Port 0: p0 (Physical)
# Port 1: p1 (Physical)
# Port 2: en3f0pf0sf10 (SF representor)

# 4. Wire between network and host
sudo ./wire -l 0-2 -- 0 2

# Now all traffic between p0 ↔ host flows through wire app
# ARM cores forward packets bidirectionally
```

---

## Debugging

### Check Port Mapping

```bash
# Show all DPDK-visible ports
sudo ./wire

# Show SF details
mlnx-sf --action show

# Show OVS ports (if using OVS)
ovs-vsctl show
```

### Check Traffic Flow

```bash
# Monitor wire app output
# It prints "Total forwarded packets: N" when forwarding

# Check interface counters
ethtool -S p0 | grep packets
ethtool -S en3f0pf0sf10 | grep packets

# Check if packets are being dropped
ethtool -S p0 | grep drop
```

### Common Issues

**Issue:** Wire app sees no ports
- **Fix:** Make sure DPDK has permission: `sudo ./wire`

**Issue:** SF representor not visible
- **Fix:** Check switchdev mode: `devlink dev eswitch show pci/0000:03:00.0`

**Issue:** No traffic forwarded
- **Fix:** Check that you're using the correct port IDs from `./wire` output

---

## Performance Characteristics

| Metric | Value |
|--------|-------|
| **Throughput** | ~10-20 Gbps per ARM core |
| **Latency** | ~50-100 μs |
| **CPU Usage** | 100% (dedicated cores) |
| **Max Cores** | 2 (wire uses 2 threads) |

For **higher performance**, consider migrating to hardware-offloaded OVS (400 Gbps, <1μs).

---

## Next Steps

1. **Basic testing:** Use Option 1 (no SFs)
2. **Production:** Use Option 2 (with SFs)
3. **Advanced:** Use Option 3 (hybrid with OVS)

Refer to `sf_setup.sh` for automated SF creation.
