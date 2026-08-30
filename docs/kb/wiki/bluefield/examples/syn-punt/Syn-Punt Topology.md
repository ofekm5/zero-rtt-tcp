---
type: Wiki Entry
title: "Network Topology for SYN Punt Application"
description: "Network topology diagram for the SYN-punt DOCA application's lab wiring."
tags: [bluefield, examples, syn-punt]
timestamp: 2026-05-23T16:09:41+03:00
---

Source: `infra/bluefield/examples/syn-punt/TOPOLOGY.md`

# Network Topology for SYN Punt Application

## Physical Setup

```
┌─────────────────┐         ┌──────────────────────────────────────┐         ┌─────────────┐
│   Host VM       │         │      BlueField-3 DPU                 │         │   Tofino    │
│                 │         │                                      │         │   Switch    │
│                 │         │  ┌────────────────────────────┐      │         │             │
│                 │  PCIe   │  │     ARM Cores              │      │  25G    │             │
│  Application    ├─────────┼──┤                            │      ├─────────┤  Network    │
│                 │         │  │  - SF0 (SSH management)    │      │  Cable  │  Fabric     │
│                 │         │  │  - syn_punt app running    │      │         │             │
│                 │         │  │    in Docker container     │      │         │             │
│  eth0 (VM NIC)  │         │  └────────────┬───────────────┘      │         │             │
└─────────────────┘         │               │                      │         └─────────────┘
                            │               │                      │
                            │    ┌──────────▼──────────┐           │
                            │    │     eSwitch         │           │
                            │    │  (Embedded Switch)  │           │
                            │    │                     │           │
                            │    │  ┌──────────────┐   │           │
                            │    │  │ DOCA Flow    │   │           │
                            │    │  │ Rules Engine │   │           │
                            │    │  │              │   │           │
                            │    │  │ SYN → Queue 0│   │           │
                            │    │  │ Other → RSS  │   │           │
                            │    │  └──────────────┘   │           │
                            │    │                     │           │
                            │    │   pf0hpf ←→ p0      │           │
                            │    └─────┬────────┬──────┘           │
                            │          │        │                  │
                            │     ┌────▼───┐ ┌──▼────┐             │
                            │     │pf0hpf  │ │  p0   │             │
                            │     │(Repr)  │ │(Phys) │             │
                            │     └────────┘ └───────┘             │
                            └──────────────────────────────────────┘
                                     ▲           │
                                     │           │
                                PCIe to Host  25G to Tofino
```

## Interface Details

### pf0hpf (PF0 Host Physical Function Representor)
- **Type**: Representor port
- **Direction**: Host VM ↔ DPU
- **Connection**: PCIe to Host VM
- **Purpose**: Receives packets from Host VM
- **Linux Interface**: `pf0hpf`
- **DPDK Port**: Usually port 0 or 1 (check with `dpdk-testpmd`)

### p0 (Physical Port 0)
- **Type**: Physical Ethernet port
- **Direction**: DPU ↔ Tofino
- **Connection**: 25G cable to Tofino switch
- **Purpose**: Forwards packets to external network
- **Linux Interface**: `p0`
- **DPDK Port**: Usually port 2 (check with `dpdk-testpmd`)

### SF0 (Scalable Function 0)
- **Type**: Scalable Function (virtual function)
- **Purpose**: **Management / SSH access**
- **Status**: Already in use by users for remote access
- **Note**: **DO NOT use SF0 for the syn_punt application**

## Packet Flow

### Normal Traffic (No OVS Bridge)
```
Host VM → pf0hpf → (drops or routes incorrectly) → p0 → Tofino
```
**Problem**: Without OVS bridge, packets don't know how to route between pf0hpf and p0.

### With OVS Bridge (Correct Setup)
```
Host VM → pf0hpf → [OVS Bridge: br-syn-punt] → p0 → Tofino
                          ↓
                    syn_punt app
                    (intercepts via DOCA Flow)
```

### With SYN Punt Application + DOCA Flow
```
1. Non-SYN Packet Flow (Fast Path):
   Host VM → pf0hpf → eSwitch → p0 → Tofino
   (Hardware forwarding, ~1 µs latency)

2. SYN Packet Flow (Exception Path):
   Host VM → pf0hpf → eSwitch → Queue 0 → ARM cores
                                            ↓
                                      syn_punt app
                                      (parse, print)
                                            ↓
                                      TX burst → p0 → Tofino
   (Software processing, ~10-50 µs latency)
```

## OVS Bridge Configuration

The OVS bridge `br-syn-punt` connects pf0hpf and p0:

```bash
# Create bridge
ovs-vsctl add-br br-syn-punt

# Add ports
ovs-vsctl add-port br-syn-punt pf0hpf
ovs-vsctl add-port br-syn-punt p0

# Configure flows (normal forwarding by default)
ovs-ofctl add-flow br-syn-punt "priority=0,actions=normal"
```

This allows:
- Packets from Host VM (pf0hpf) to reach Tofino (p0)
- Packets from Tofino (p0) to reach Host VM (pf0hpf)
- syn_punt application to intercept packets via DPDK

## DPDK Port Binding

### Finding Your Ports

```bash
# Method 1: Use dpdk-testpmd
dpdk-testpmd -l 0-1 -a 03:00.0 -- --list

# Method 2: Use our application's list mode
sudo ./build/syn_punt -l 0-1 -a 03:00.0 -- --list

# Method 3: Check Linux interface to DPDK mapping
ip link show | grep -E "pf0hpf|p0"
```

### Typical Port Mapping
```
DPDK Port 0 or 1 → pf0hpf (representor)
DPDK Port 2      → p0 (physical)
```

**Important**: Verify your port IDs before running the application!

## Container Network Access

Since SF0 is used for SSH, the Docker container must:
1. Run with `--network host` to access pf0hpf and p0
2. Have access to `/sys/class/net` for interface management
3. Have hugepage access: `-v /dev/hugepages:/dev/hugepages`

```bash
docker run -it --rm \
    --privileged \
    --network host \
    -v $(pwd):/workspace \
    -v /sys/class/net:/sys/class/net \
    -v /dev/hugepages:/dev/hugepages \
    nvcr.io/nvidia/doca/doca:2.5.0-devel \
    bash
```

## Traffic Testing

### From Host VM
```bash
# Generate SYN packets
hping3 -S -p 80 <tofino_ip> -c 10

# Or use curl (generates SYN as first packet)
curl http://<tofino_ip>
```

### Capture on DPU
```bash
# Terminal 1: Run syn_punt app
sudo ./build/syn_punt -l 0-1 -a 03:00.0 -- -p 0

# Terminal 2: Monitor pf0hpf (from Host VM)
sudo tcpdump -i pf0hpf -n 'tcp[tcpflags] & tcp-syn != 0'

# Terminal 3: Monitor p0 (to Tofino)
sudo tcpdump -i p0 -n 'tcp[tcpflags] & tcp-syn != 0'
```

### Expected Behavior
- SYN packets appear in syn_punt app output
- SYN packets visible on both pf0hpf and p0
- Non-SYN packets NOT printed (fast-forwarded)
- Application statistics show correct counts

## Troubleshooting

### Packets Not Reaching Application
```bash
# 1. Verify OVS bridge is configured
ovs-vsctl show

# 2. Verify ports are in bridge
ovs-vsctl list-ports br-syn-punt

# 3. Check flow rules
ovs-ofctl dump-flows br-syn-punt

# 4. Verify interfaces are UP
ip link show pf0hpf
ip link show p0
```

### No SYN Packets Detected
```bash
# 1. Verify DOCA Flow rules installed
# (Check application startup logs)

# 2. Generate test SYN from Host VM
hping3 -S -p 80 10.0.0.1 -c 5

# 3. Capture raw packets
tcpdump -i pf0hpf -nn -vv 'tcp[tcpflags] & tcp-syn != 0'
```

### Performance Issues
```bash
# 1. Check if eSwitch offload is enabled
ethtool -k p0 | grep hw-tc-offload

# 2. Verify hugepages
cat /proc/meminfo | grep Huge

# 3. Monitor CPU usage
top -H -p $(pgrep syn_punt)
```

## References

- [DOCA Flow Programming Guide](https://docs.nvidia.com/doca/sdk/doca+flow+programming+guide/)
- [BlueField OVS Guide](https://docs.nvidia.com/networking/display/bluefielddpuosdocumentation/ovs)
- [DPDK Representors](https://doc.dpdk.org/guides/prog_guide/switch_representation.html)
