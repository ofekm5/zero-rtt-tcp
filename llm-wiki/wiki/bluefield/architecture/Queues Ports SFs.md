---
type: Wiki Entry
title: "Queues, Ports, and Scalable Functions"
description: "Understanding queues, ports, and Scalable Functions (SFs) is fundamental to BlueField-3 development. This document explains what these concepts are, how they..."
tags: [bluefield, architecture]
timestamp: 2026-05-23T16:09:41+03:00
---

Source: `infra/bluefield/docs/01-architecture/queues-ports-sfs.md`

# Queues, Ports, and Scalable Functions

## Overview
Understanding queues, ports, and Scalable Functions (SFs) is fundamental to BlueField-3 development. This document explains what these concepts are, how they relate to each other, and their role in the packet processing architecture.

## DPDK Queues

### Definition

```
Queue = Circular ring buffer containing packet descriptors

NOT: Communication endpoints like sockets
ARE: Memory structures for efficient packet transfer
```

**Structure**:
```c
struct rte_ring {
    uint32_t prod_head;    // Producer write position
    uint32_t prod_tail;    // Producer commit position
    uint32_t cons_head;    // Consumer read position
    uint32_t cons_tail;    // Consumer commit position

    void *ring[];          // Array of packet descriptors
};
```

### RX Queue (Receive)

```
NIC Hardware
    ↓
DMA writes packet to memory
    ↓
Packet descriptor added to RX Queue
    ↓
Application polls queue
```

**Key Points**:
- No interrupts (poll mode)
- Lock-free (single producer, single consumer)
- Zero-copy (descriptors point to packet buffers)
- CPU core typically dedicated to one queue

### TX Queue (Transmit)

```
Application prepares packets
    ↓
Add descriptors to TX Queue
    ↓
NIC Hardware reads descriptors
    ↓
DMA reads packet data
    ↓
Transmit on wire
```

## DPDK Ports

### What is a Port?

```
Port = Representation of a network interface (physical or virtual)

Physical Port: Actual NIC port (eth0, eth1)
Virtual Port: Representor for VF, PF, or other endpoint
```

### Port Types on BlueField-3

#### 1. Physical Ports (Uplink Ports)
```c
// Physical port 0 (external network)
Port ID: 0
Type: Physical NIC port
Speed: 200G or 400G
Use: Connect to external network
```

#### 2. Host PF (Physical Function)
```c
// PCIe function seen by x86 host
Port ID: X (assigned at init)
Type: Host Physical Function representor
Use: Host OS network interface
```

#### 3. Host VFs (Virtual Functions)
```c
// SR-IOV virtual functions for VMs
Port ID: Y, Y+1, Y+2, ...
Type: Host VF representors
Use: Pass-through to VMs
```

#### 4. ARM Uplink
```c
// Connection to ARM cores
Port ID: Z
Type: ARM uplink representor
Use: Software processing on ARM
```

#### 5. DPA Queues (Virtual Ports)
```c
// DPA processing queues
Port ID: W
Type: DPA queue representor
Use: Send packets to DPA for processing
```

### Port Representors

**Key Concept**: Representors are **virtual ports** that represent endpoints in the system.

```
┌─────────────────────────────────────────┐
│         BlueField-3 Internal View       │
│                                         │
│  Port 0:  Physical Port 0 (external)    │
│  Port 1:  Physical Port 1 (external)    │
│  Port 2:  Host PF (pf0hpf)              │
│  Port 3:  Host VF0 (pf0vf0)             │
│  Port 4:  Host VF1 (pf0vf1)             │
│  Port 5:  ARM Uplink                    │
│  Port 6:  DPA Queue 0                   │
│  ...                                    │
└─────────────────────────────────────────┘
```

**From x86 Host Perspective**:
```bash
# Host sees VFs as normal network interfaces
lspci | grep Mellanox
# 03:00.0 Ethernet controller: Mellanox Technologies MT42822
# 03:00.1 Ethernet controller: Mellanox Technologies MT42822 VF
# 03:00.2 Ethernet controller: Mellanox Technologies MT42822 VF
```

**From ARM Perspective** (on BlueField):
```bash
# ARM sees representors
ip link show
# pf0hpf: Host PF representor
# pf0vf0: Host VF0 representor
# pf0vf1: Host VF1 representor
# p0: Physical port 0
# p1: Physical port 1
```

## Scalable Functions (SFs)

### What is a Scalable Function?

A Scalable Function (SF) is a lightweight virtualization technology that provides isolated network endpoints with their own resources.

**Key characteristics**:
- Lighter weight than SR-IOV VFs
- Dynamic creation/deletion
- Dedicated MAC address
- Own queue resources
- Isolated from other SFs

### The Two "Faces" of a Subfunction

Every SF has two network interfaces:

| Component | Name Example | Purpose | Used By |
|-----------|--------------|---------|---------|
| **SF Netdev** | `enp3s0f0s0` | Direct hardware access | DOCA/DPDK applications |
| **SF Representor** | `en3f0pf0sf0` | Switch fabric control | OVS, kernel networking |

**Important distinction**:
- **SF Netdev**: Bind to your DPDK/DOCA application for direct packet processing
- **SF Representor**: Add to OVS bridge to represent the SF in the switching fabric

You typically use one OR the other for a given traffic path, not both simultaneously.

### SF vs VF Comparison

| Feature | Scalable Function (SF) | Virtual Function (VF) |
|---------|------------------------|----------------------|
| **Creation** | Dynamic (runtime) | Static (requires reboot) |
| **Weight** | Lightweight | Heavier |
| **Number** | Thousands | Hundreds |
| **Performance** | Same as VF | Line-rate |
| **Use Case** | Containers, microservices | VMs |

### SF Lifecycle

```
1. Create SF
   mlnx-sf --action create --device 0000:03:00.0 --sfnum 9 --hwaddr 02:25:f2:8d:a2:4c

2. SF appears as two interfaces:
   - SF netdev: enp3s0f0s9 (for DPDK binding)
   - SF representor: en3f0pf0sf9 (for OVS)

3. Use SF:
   Option A: Bind netdev to DPDK application
   Option B: Add representor to OVS bridge

4. Delete SF:
   mlnx-sf --action delete --sfindex pci/0000:03:00.0/229409
```

## Interface Types Summary

### Where Traffic Goes - Handler Types

| Handler Type | What It Does | When to Use |
|--------------|--------------|-------------|
| **DOCA/DPDK App** | Your code processes all traffic directly via eSwitch | Your PoCs - full control over packets |
| **OVS Bridge** | L2 switching, MAC learning, optional flow rules | VMs, containers needing network connectivity |
| **Linux Kernel Stack** | Regular networking (ip addr, routes, iptables) | Management interfaces, simple use cases |

### Physical Ports vs Virtual Endpoints

```
┌─────────────────────────────────────────────────────────────────┐
│                        BlueField-3                               │
│                                                                  │
│  Physical Ports          Subfunctions                           │
│  ┌──────┐ ┌──────┐      ┌──────────┐  ┌──────────┐             │
│  │  p0  │ │  p1  │      │   SF0    │  │   SF1    │             │
│  │uplink│ │uplink│      │          │  │          │             │
│  └──┬───┘ └──┬───┘      └────┬─────┘  └────┬─────┘             │
│     │        │               │             │                    │
│     │        │          ┌────┴────┐   ┌────┴────┐              │
│     │        │          │ Netdev  │   │ Netdev  │              │
│     │        │          │(for app)│   │(for app)│              │
│     │        │          └────┬────┘   └────┬────┘              │
│     │        │               │             │                    │
│     │        │          ┌────┴────┐   ┌────┴────┐              │
│     │        │          │ Repre-  │   │ Repre-  │              │
│     │        │          │ sentor  │   │ sentor  │              │
│     │        │          └─────────┘   └─────────┘              │
│     │        │                                                  │
└─────┼────────┼──────────────────────────────────────────────────┘
      │        │
      ▼        ▼
  Add to OVS if needed
```

### Port Naming Conventions

Understanding interface names is crucial:

| Name Pattern | Type | Example | Purpose |
|-------------|------|---------|---------|
| `p0`, `p1` | Physical uplink | `p0` | External network connection |
| `pf0hpf` | Host PF representor | `pf0hpf` | Represents host PCI function |
| `pf0vf0` | Host VF representor | `pf0vf0` | Represents host VF #0 |
| `en3f0pf0sf2` | SF representor | `en3f0pf0sf2` | Represents SF #2 in switching |
| `enp3s0f0s2` | SF netdev | `enp3s0f0s2` | Direct hardware access for SF #2 |

## Multi-Queue Architecture

### Why Multiple Queues?

```
Single Queue (Bad):
    All packets → One RX Queue → One CPU core
    Bottleneck at ~10-20 Gbps per core

Multiple Queues (Good):
    Packets → Queue 0 → CPU Core 0
    Packets → Queue 1 → CPU Core 1
    Packets → Queue 2 → CPU Core 2
    ...
    Total: ~40-60 Gbps (parallelism)
```

### RSS (Receive Side Scaling)

**Purpose**: Distribute packets across queues based on hash

**How RSS Works**:
```
Packet arrives
    ↓
Hardware hashes: src_ip ^ dst_ip ^ src_port ^ dst_port
    ↓
Queue = hash % num_queues
    ↓
Packet placed in selected queue
```

**Benefits**:
- Load balancing across CPU cores
- Maintains flow affinity (same flow → same queue)
- Scales performance linearly with cores

## Queue-to-Core Mapping

### Best Practice: 1 Queue per Core

**Why This Works**:
- No locking needed (each core owns its queue)
- Cache-friendly (core processes same flows)
- Scales linearly with cores

### Anti-Pattern: Multiple Cores, One Queue

```c
❌ BAD: Multiple cores polling same queue
// Requires locks → serialization → poor performance

while (1) {
    pthread_mutex_lock(&queue_lock);  // ← Kills performance
    nb_rx = rte_eth_rx_burst(port, 0, pkts, BURST);
    pthread_mutex_unlock(&queue_lock);
}
```

## Hairpin Queues

### What is Hairpin?

**Hairpin**: Direct NIC-to-NIC forwarding, bypassing CPU

**Key Characteristic**: Buffers stay entirely inside NIC hardware - no DMA to external memory

```
Normal Path:
    Port 0 RX → DMA to DDR → Queue → CPU → Queue → DMA from DDR → Port 1 TX
    (Software overhead + memory bandwidth)

Hairpin Path:
    Port 0 RX → Hairpin Queue (NIC internal) → Port 1 TX
    (Hardware only, zero CPU, zero external memory)
```

**Use Cases**:
- Port mirroring
- Fast port-to-port forwarding
- Combining with flow rules for filtering

## Packet Buffers (mbufs)

### mbuf Structure

```c
struct rte_mbuf {
    // Metadata
    uint16_t data_off;      // Offset to packet data
    uint16_t data_len;      // Length of packet data
    uint32_t pkt_len;       // Total packet length

    // Buffer management
    struct rte_mempool *pool;  // Memory pool
    uint16_t nb_segs;          // Number of segments

    // Packet type info
    uint32_t packet_type;   // L2/L3/L4 types
    uint64_t ol_flags;      // Offload flags

    // Pointer to actual packet data
    char buf_addr[];
};
```

**Best Practices**:
- Create one pool per NUMA node
- Size = (num_queues × queue_size) × 2
- Enable per-core caching for performance

## Queue Memory Location and DMA

### Where Queues Live

**Software queues live in the memory of whoever owns them:**

```
ARM runs DPDK → Queues in ARM DDR (BlueField local memory)
Host runs DPDK → Queues in Host DDR (x86 server memory)

Each has its own memory space, not shared
```

**Key Points**:
- Queue memory is local to the processing entity
- ARM and Host have separate, independent memory spaces
- No shared memory between ARM and Host for queues

### DMA is Point-to-Point

**DMA is point-to-point, not shared access:**

```
NIC DMAs packets into a specific memory region (ARM or Host)
    ↓
The owner of that memory polls/processes the queue
    ↓
eSwitch doesn't "access" these buffers - it tells the DMA engine where to put packets
```

**How It Works**:
1. Flow rule specifies destination (e.g., "send to Host VF0")
2. NIC DMA engine writes packet to Host memory
3. Host application polls its queue in Host memory
4. eSwitch logic only routes - doesn't touch the actual packet buffers

**Example Flow**:
```
Packet arrives → eSwitch matches flow → DMA to Host VF queue → Host polls and receives
                 (flow decision)      (point-to-point DMA)    (in Host DDR)
```

### Hairpin is Special

**Hairpin queues work differently:**

```
Hairpin: Buffers stay inside NIC hardware
         No DMA to external memory at all
         That's why it's fastest (zero memory copies)
```

**Comparison**:
```
Normal Queue:
    NIC → DMA to DDR → CPU reads from DDR → CPU writes to DDR → DMA from DDR → NIC
    (Multiple memory operations)

Hairpin Queue:
    NIC → Internal buffer → NIC
    (Zero external memory operations)
```

This is why hairpin achieves true line-rate forwarding - packets never leave the NIC hardware.

## Key Takeaways

1. **Queues are buffers**, not sockets or communication endpoints
2. **Ports represent interfaces**, physical or virtual (representors)
3. **SFs have two interfaces**: netdev (for DPDK) and representor (for OVS)
4. **Representors are virtual ports** for eSwitch endpoints
5. **1 Queue per Core** is the optimal pattern (lock-free)
6. **RSS distributes load** across queues automatically
7. **Hairpin queues** bypass CPU entirely (hardware-only path)
8. **DMA is point-to-point** - queues live in the memory of their owner
9. **mbufs are reused** via memory pools (no malloc/free)

## Next Steps
- See [[Eswitch Flow Engine|eSwitch and Flow Engine]] for port representor programming
- See [[Packet Pipeline]] for understanding how packets flow through the system
- Read [[SF Management]] for creating and managing SFs
- Check [[DPDK Integration]] for queue configuration examples
