---
type: Wiki Entry
title: "Packet Processing Pipeline"
description: "This document describes the complete packet flow through BlueField-3 from ingress to egress."
tags: [bluefield, architecture]
timestamp: 2026-05-23T16:09:41+03:00
---

Source: `infra/bluefield/docs/01-architecture/packet-pipeline.md`

# Packet Processing Pipeline

## Overview
This document describes the complete packet flow through BlueField-3 from ingress to egress.

## High-Level Flow

```
Physical Port → Parser → Flow Engine → Action → Egress Port
                           ↓
                    (Optional: DPA/ARM)
```

## Detailed Packet Processing Stages

### Stage 1: Packet Arrival

```
Packet arrives at Physical Port (e.g., 200G Ethernet)
    ↓
NIC PHY layer
    ↓
MAC layer processing
    ↓
DMA to packet buffer (DRAM)
    ↓
Packet descriptor created
```

**What happens**:
- Physical layer receives bits
- MAC validates frame (CRC check)
- Packet copied to memory via DMA
- Descriptor contains pointer to packet + metadata

### Stage 2: Hardware Parser

```
Packet Buffer
    ↓
Hardware Parser (fixed-function ASIC)
    ↓
Extracted Metadata:
  • Ethernet: src/dst MAC, ethertype, VLAN tags
  • IP: src/dst IP, protocol, ToS, TTL
  • TCP/UDP: src/dst ports, flags
  • Tunnel: VXLAN VNI, GRE key, etc.
```

**Parser Capabilities**:
- Layer 2-4 protocol parsing
- Tunnel decapsulation detection
- Multiple VLAN tags
- IPv4/IPv6
- Pre-programmed protocol support

**Cannot Parse** (without DPL):
- Custom protocols
- Non-standard encapsulations
- Proprietary headers

### Stage 3: Flow Engine Lookup

```
Parsed Metadata
    ↓
Flow Steering Engine
    ↓
Multi-stage table lookup:

┌─────────────────────────────────────┐
│ Stage 1: Root Table (Table 0)      │
│   Match: Ingress Port               │
│   Action: Jump to Group Table       │
└──────────────┬──────────────────────┘
               ↓
┌─────────────────────────────────────┐
│ Stage 2: Group Tables               │
│   Match: MAC/IP/Ports               │
│   Action: Forward/Modify/Drop       │
└──────────────┬──────────────────────┘
               ↓
┌─────────────────────────────────────┐
│ Stage 3: Final Actions              │
│   Execute all accumulated actions   │
└─────────────────────────────────────┘
```

**Lookup Process**:
1. Hash packet headers to index
2. Check TCAM for priority rules
3. Check hash table for exact match
4. Fall through to default rule if no match

**Lookup Time**: <1 μs for on-chip tables

### Stage 4: Action Execution

```
Matched Flow Rule
    ↓
Action Engine executes:

┌─────────────────────────────────────┐
│ Supported Actions:                  │
│                                     │
│ • Set destination port              │
│ • Modify IP addresses (NAT)         │
│ • Modify TCP/UDP ports (PAT)        │
│ • Push/pop VLAN tags                │
│ • Encapsulate (VXLAN/GRE/GENEVE)   │
│ • Decapsulate tunnels               │
│ • Decrement TTL                     │
│ • Recalculate checksums             │
│ • Update counters                   │
│ • Mark/flag for software            │
└─────────────────────────────────────┘
```

**Action Limitations**:
- Can only modify predefined header fields
- Cannot add arbitrary data
- Cannot generate new packets
- No complex computations

### Stage 5: Egress Processing

```
Modified Packet
    ↓
Egress Port Selection
    ↓
┌──────────────┬─────────────┬──────────────┐
│              │             │              │
Physical Port  Host VF      ARM Uplink    DPA Queue
(external)     (VM)         (software)    (processing)
```

**Egress Options**:
- **Physical Port**: Send to network
- **Host VF**: Send to VM via PCIe
- **ARM Uplink**: Send to ARM cores for software processing
- **DPA Queue**: Send to DPA for custom processing

## Special Processing Paths

### Path 1: Pure Hardware Fast Path (Line-Rate)

```
Ingress Port → Parser → Flow Match → Actions → Egress Port
                         (all in hardware)
                         
Performance: 400 Gbps, <1 μs latency
Use Case: Simple forwarding, NAT, VXLAN
```

**Example**: VM-to-VM through eSwitch
```
VM1 (VF0) → Flow Engine (MAC match) → VM2 (VF1)
```

### Path 2: Hardware + DPA Hybrid

```
Ingress Port → Parser → Flow Match → Send to DPA
                                         ↓
                                    DPA Processing
                                    (custom logic)
                                         ↓
                                    Send to Flow Engine
                                         ↓
                                    Egress Port

Performance: 10-100 Gbps, 5-20 μs latency
Use Case: Custom packet modifications, stateful processing
```

**Example**: TCP sequence number modification
```
Port 0 → Filter (specific IP) → DPA (modify seq/ack) → Port 1
```

### Path 3: Software Processing on ARM

```
Ingress Port → Parser → Flow Match → ARM Uplink
                                         ↓
                                    ARM Cores
                                    (DPDK app)
                                         ↓
                                    Process packet
                                         ↓
                                    Send back to NIC
                                         ↓
                                    Egress Port

Performance: 10-20 Gbps/core, 50-200 μs latency
Use Case: Control plane, first packet of flow, complex policy
```

**Example**: OVS slow path
```
Unknown flow → ARM (OVS learns) → Install flow rule → Fast path
```

### Path 4: Hairpin Queues (NIC-to-NIC)

```
Port 0 RX Queue → Hairpin → Port 1 TX Queue
         (all in hardware, bypass ARM)

Performance: Line-rate, <1 μs
Use Case: Fast port-to-port forwarding
```

**Setup**:
```c
// Bind RX queue on Port 0 to TX queue on Port 1
struct rte_eth_hairpin_conf conf = {
    .peer_count = 1,
    .peers[0] = { .port = 1, .queue = 0 }
};
rte_eth_rx_hairpin_bind(0, rx_queue, &conf);
```

## Complete Example Flows

### Example 1: Simple L2 Forwarding

```
1. Packet arrives at Physical Port 0
   MAC: aa:bb:cc:dd:ee:01 → aa:bb:cc:dd:ee:02

2. Parser extracts:
   - dst_mac = aa:bb:cc:dd:ee:02
   - src_mac = aa:bb:cc:dd:ee:01

3. Flow Engine lookup:
   Match: {ingress=port0, dst_mac=aa:bb:cc:dd:ee:02}
   Action: Forward to VF0

4. Packet sent to Host VF0 via PCIe

Total time: <1 μs
```

### Example 2: VXLAN Encapsulation

```
1. Packet arrives at ARM Uplink (from software)
   Inner: IP 10.0.0.1 → 10.0.0.2

2. Parser identifies inner packet

3. Flow Engine lookup:
   Match: {ingress=arm_uplink, dst_ip=10.0.0.2}
   Action: 
     - Encap VXLAN (VNI=100)
     - Set outer IP: 192.168.1.1 → 192.168.1.2
     - Set outer UDP: port 4789
     - Forward to Physical Port 0

4. Packet sent with VXLAN header

Headers: [Eth][IP:192.168.1.1→192.168.1.2][UDP:4789][VXLAN:VNI=100][Inner Packet]

Total time: <2 μs (encap adds slight overhead)
```

### Example 3: TCP SYN Proxy with DPA

```
1. SYN packet arrives at Physical Port 0
   TCP flags: SYN

2. Parser extracts TCP metadata

3. Flow Engine lookup:
   Match: {tcp_flags=SYN, dst_port=80}
   Action: Send to DPA Queue 0

4. DPA receives packet:
   - Extracts connection info (IPs, ports, seq)
   - Generates SYN-ACK packet
   - Tracks connection state
   - Sends SYN-ACK to DPA TX queue

5. Flow Engine receives from DPA:
   Action: Forward to Physical Port 0

6. SYN-ACK sent back to client

Total time: ~10-20 μs (DPA processing)
```

### Example 4: OVS with Hardware Offload

```
First Packet:
1. VM1 sends to VM2 (unknown flow)
2. Flow Engine: No match
3. Default action: Send to ARM (OVS slow path)
4. OVS on ARM:
   - Learns MAC addresses
   - Makes forwarding decision
   - Installs flow rule in hardware
5. Packet forwarded to VM2

Subsequent Packets:
1. Same flow arrives
2. Flow Engine: Match found (hardware rule installed)
3. Action: Forward to VM2 directly
4. Bypass ARM entirely

First packet: ~100 μs (software)
Subsequent: <1 μs (hardware)
```

## Flow Rule Priority and Hierarchy

**Flow rules define the routing decision: which packets go where.** They connect:
- **Match criteria** (what packets to catch)
- **Actions** (what to do: send to queue, modify, drop, hairpin)

```
Priority 0 (Highest)
    ↓
┌─────────────────────────────────────┐
│ Specific rules (TCAM)               │
│ Example: TCP port 80 to server A    │
└──────────────┬──────────────────────┘
               ↓
Priority 100 (Medium)
    ↓
┌─────────────────────────────────────┐
│ Group rules (Hash tables)           │
│ Example: All HTTP traffic           │
└──────────────┬──────────────────────┘
               ↓
Priority 1000 (Low)
    ↓
┌─────────────────────────────────────┐
│ Default rules                       │
│ Example: Forward to ARM / Drop      │
└─────────────────────────────────────┘
```

**Lookup Process**:
1. Check highest priority first (TCAM)
2. If match → execute actions
3. If no match → check next priority
4. Continue until match or default

## Packet Metadata Through Pipeline

```
Stage              Available Metadata
─────────────────────────────────────────────────────────
Arrival            • Ingress port
                   • Timestamp
                   • Packet length

After Parser       • All L2-L4 headers
                   • Tunnel information
                   • VLAN tags
                   • Hash value

Flow Lookup        • Matched rule ID
                   • Table ID
                   • Priority
                   • Hit/miss status

Action Execution   • Modified headers
                   • Counter values
                   • Flags/marks

Egress            • Egress port
                   • Queue ID
                   • TX timestamp
```

## Performance Characteristics by Path

| Path | Throughput | Latency | Packet Rate | Use Case |
|------|------------|---------|-------------|----------|
| **Hardware Only** | 400 Gbps | <1 μs | 500 Mpps | Forwarding, NAT |
| **Hardware + DPA** | 50-100 Gbps | 10-20 μs | 50-100 Mpps | Custom processing |
| **Hardware + ARM** | 10-20 Gbps | 100-200 μs | 10-20 Mpps | Control plane |
| **Hairpin** | 400 Gbps | <1 μs | 500 Mpps | Port mirroring |

## Troubleshooting Packet Drops

### Where Packets Can Be Dropped

```
1. Physical Layer
   - CRC errors
   - Physical link issues
   
2. MAC Layer
   - Buffer overflow
   - Flow control

3. Parser
   - Malformed packets
   - Unknown protocols (without DPL)

4. Flow Engine
   - No matching rule (if default = drop)
   - Table full / overflow
   - Rate limiting / policing

5. DPA
   - Processing error
   - Queue full
   - Application logic

6. ARM
   - Application not polling
   - Queue full
   - Software bugs

7. Egress
   - Output port congestion
   - PCIe bandwidth limit
   - Buffer exhaustion
```

### Debugging Tools

```bash
# Check hardware counters
ethtool -S <interface>

# Check flow rules
ovs-appctl dpctl/dump-flows type=offloaded

# Check hardware flow table usage
mlxdump -d <device> fsdump --type FT --gvmi=0

# DPA debugging
doca_dpa_debug --dump-state

# Check packet drops
cat /sys/class/net/<interface>/statistics/rx_dropped
```

## Key Takeaways

1. **Hardware path is fastest**: <1 μs, 400 Gbps
2. **DPA adds flexibility**: Custom processing at ~50-100 Gbps
3. **ARM for control plane**: Slow but flexible
4. **Multi-stage lookup**: TCAM → Hash → Default
5. **Actions are limited**: Only predefined operations in hardware
6. **eSwitch is flow rules**: Not separate hardware logic
7. **Hybrid approach optimal**: Hardware filter + DPA/ARM process

## Next Steps
- See [[Eswitch Flow Engine|eSwitch and Flow Engine]] for programming
- Read [[DPA Programming]] for custom processing
- Check [[Performance Tuning|Performance Optimization]] for tuning
