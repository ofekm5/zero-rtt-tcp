---
type: Wiki Entry
title: "Hardware Architecture - BlueField-3 Components"
description: "This document maps all hardware components in the BlueField-3 DPU and explains their relationships."
tags: [bluefield, architecture]
timestamp: 2026-05-23T16:09:41+03:00
---

Source: `infra/bluefield/docs/01-architecture/hardware-overview.md`

# Hardware Architecture - BlueField-3 Components

## Overview
This document maps all hardware components in the BlueField-3 DPU and explains their relationships.

## Complete Hardware Map

```
┌─────────────────────────────────────────────────────────────────┐
│                        BlueField-3 DPU SoC                      │
│                                                                 │
│  ┌──────────────────┐                                          │
│  │   ARM Cores      │  (16x Cortex-A78, up to 400 Gbps DPDK)  │
│  │   (CPU Complex)  │  • Run control plane software            │
│  │                  │  • OVS, DPDK apps, Linux kernel          │
│  └────────┬─────────┘                                          │
│           │ PCIe/AXI interconnect                              │
│           │                                                     │
│  ┌────────┴─────────────────────────────────────────────────┐ │
│  │              ConnectX NIC Engine (ASIC)                   │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────┐   │ │
│  │  │  Packet Processing Pipeline (ASAP²)              │   │ │
│  │  │                                                    │   │ │
│  │  │  ┌─────────────┐      ┌──────────────────┐      │   │ │
│  │  │  │   Parser    │─────→│  NIC Flow Engine │      │   │ │
│  │  │  │  (hardware) │      │  (Steering/ACL)  │      │   │ │
│  │  │  └─────────────┘      │                  │      │   │ │
│  │  │         │              │  • Match tables  │      │   │ │
│  │  │         │              │  • Action engine │      │   │ │
│  │  │         │              │  • Counters      │      │   │ │
│  │  │         │              └────────┬─────────┘      │   │ │
│  │  │         │                       │                │   │ │
│  │  │         │              ┌────────┴─────────┐     │   │ │
│  │  │         └─────────────→│    eSwitch       │     │   │ │
│  │  │                        │  (Virtual switch)│     │   │ │
│  │  │                        │                  │     │   │ │
│  │  │                        │  Representors:   │     │   │ │
│  │  │                        │  • Physical ports│     │   │ │
│  │  │                        │  • Host PF/VFs   │     │   │ │
│  │  │                        │  • ARM uplink    │     │   │ │
│  │  │                        └──────────────────┘     │   │ │
│  │  └──────────────────────────────────────────────────┘   │ │
│  │                                                          │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  DPA (Data Path Accelerator) - Programmable Cores        │ │
│  │                                                            │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐               │ │
│  │  │ DPA Core │  │ DPA Core │  │ DPA Core │  ... (many)   │ │
│  │  │  Thread  │  │  Thread  │  │  Thread  │               │ │
│  │  └──────────┘  └──────────┘  └──────────┘               │ │
│  │                                                            │ │
│  │  • Custom packet processing                               │ │
│  │  • Access to packet buffers                               │ │
│  │  • Can read/write headers                                 │ │
│  └────────────┬───────────────────────────────────────────┘ │
│               │                                               │
│  ┌────────────┴──────────────┐                              │
│  │    Shared Memory/Buffers   │                              │
│  │    (Packet descriptors)    │                              │
│  └────────────────────────────┘                              │
│                                                                 │
└───────────────────────┬─────────────────────────────────────┘
                        │
                   Physical Ports
                   (200G/400G Ethernet)
```

## Component Descriptions

### 1. ARM Cores
- **Type**: 16x Cortex-A78 CPUs @ ~3 GHz
- **Role**: Control plane, software packet processing
- **Memory**: Shared DRAM access
- **Performance**: ~10-20 Gbps per core for packet processing
- **Use Cases**:
  - Run OVS control plane
  - DPDK applications
  - Linux networking stack
  - Management interfaces

### 2. ConnectX NIC Engine
- **Type**: Fixed-function ASIC for packet processing
- **Performance**: Up to 400 Gbps line-rate
- **Components**: Parser, Flow Engine, eSwitch
- **Memory**: On-chip SRAM/TCAM + external DRAM

### 3. Hardware Parser
- **Type**: Fixed-function packet parser in silicon
- **Function**: Extract packet headers (L2-L4)
- **Protocols Supported**:
  - Ethernet (802.1Q, 802.1ad)
  - IPv4/IPv6
  - TCP/UDP/ICMP
  - VXLAN, GRE, GENEVE, MPLS
  - GTP, IPsec ESP
- **Customization**: Only via DOCA DPL (P4)
- **Output**: Parsed metadata fed to flow engine

### 4. NIC Flow Engine (Flow Steering)
- **Type**: Hardware flow tables (TCAM + Hash)
- **Capacity**: ~1-16M flows (varies by complexity)
- **Functions**:
  - Packet matching
  - Action execution
  - Counters and meters
- **Tables**:
  - On-chip SRAM/TCAM: ~100K-1M entries (fast)
  - On-chip Hash: ~1M-16M entries (medium)
  - External DRAM: Overflow (slower)

**Supported Actions**:
```
✅ Forward to port/queue
✅ Modify IP addresses (NAT)
✅ Modify TCP/UDP ports (PAT)
✅ VLAN push/pop
✅ Tunnel encap/decap (VXLAN, GRE)
✅ TTL decrement
✅ Checksum recalculation
✅ Counting/metering
✅ Mark/flag packets

❌ Arbitrary packet field modification
❌ Packet generation
❌ Complex stateful operations
❌ Deep packet inspection
```

### 5. eSwitch (Embedded Switch)
- **Type**: Virtual switch logic within NIC flow engine
- **NOT**: Separate hardware component
- **Function**: Connect multiple representor ports
- **Implementation**: Flow table entries with port-to-port forwarding

**Ports (PF/VF/SF)**:
Ports are the logical endpoints representing network interfaces. They're where packets "enter" and "exit" from DPDK's perspective.

**Port Representors** (internal port IDs):
```
Port 0:  Physical Port 0 (external network)
Port 1:  Physical Port 1 (external network)
Port 2:  Host PF (x86 server PCIe)
Port 3:  Host VF0 (VM0 on x86)
Port 4:  Host VF1 (VM1 on x86)
Port 5:  ARM Uplink (to ARM cores)
Port 6:  DPA Queue 0
...
```

### 6. DPA (Data Path Accelerator)
- **Type**: Programmable hardware cores
- **Architecture**: Similar to GPU streaming multiprocessors (SIMT)
- **Programming**: C language via DPACC compiler
- **Performance**: ~10-100 Gbps (depends on complexity)
- **Use Cases**:
  - Custom packet processing
  - Stateful operations
  - Packet generation
  - Complex header modifications
  - Crypto/compression offload

**Key Capabilities**:
```
✅ Read/write any packet field
✅ Generate packets from scratch
✅ Stateful processing (connection tracking)
✅ Complex algorithms
✅ Dynamic flow rule installation

❌ Not true line-rate (400 Gbps)
❌ Requires programming expertise
```

### 7. ASAP² (Accelerated Switching and Packet Processing)
- **Type**: Marketing name for the hardware offload architecture
- **Components**: Parser + Flow Engine + eSwitch
- **Not**: A separate component, but the collective name

## Hardware Interfaces

### ARM ↔ NIC
- **Interface**: PCIe / Memory-mapped I/O
- **Mechanism**: DPDK PMD (Poll Mode Driver)
- **Queues**: RX/TX ring buffers in shared memory
- **Performance**: Software-limited (~20 Gbps per core)

### NIC Flow Engine ↔ DPA
- **Interface**: Packet queues + shared memory
- **Direction**: Bidirectional
  - Flow Engine → DPA: Send packets for processing
  - DPA → Flow Engine: Send processed packets back
- **Use**: Hybrid processing (hardware filter + software process)

### DPA ↔ Flow Engine (Rule Installation)
- **Interface**: DOCA Flow API
- **Function**: DPA can dynamically install flow rules
- **Use Case**: Learn new flows → program hardware fast path

## Memory Hierarchy

```
┌─────────────────────────────────────────┐
│  On-chip SRAM/TCAM (fastest)            │
│  • Flow tables (priority rules)         │
│  • ~100K-1M entries                     │
│  • <1 μs access latency                 │
├─────────────────────────────────────────┤
│  On-chip Hash Tables (fast)             │
│  • Exact match flows                    │
│  • ~1M-16M entries                      │
│  • ~10 cycles access                    │
├─────────────────────────────────────────┤
│  External DRAM (medium)                 │
│  • Overflow flows                       │
│  • Packet buffers                       │
│  • Large flow tables                    │
│  • ~100 ns access                       │
├─────────────────────────────────────────┤
│  Host Memory (slowest)                  │
│  • Packets to/from x86 host             │
│  • Over PCIe                            │
│  • ~1-10 μs latency                     │
└─────────────────────────────────────────┘
```

## Performance Characteristics

| Component | Throughput | Latency | Use Case |
|-----------|------------|---------|----------|
| NIC Flow Engine | 400 Gbps | <1 μs | Line-rate forwarding |
| DPA | 10-100 Gbps | 5-20 μs | Custom processing |
| ARM Cores | 10-20 Gbps/core | 50-200 μs | Control plane |
| PCIe to Host | 200 Gbps (PCIe 5.0) | 1-5 μs | VM traffic |

## Operating Modes

BlueField-3 can operate in fundamentally different modes, changing how packets flow through the system.

### Mode Comparison

| Aspect | Classic DPDK Mode | SmartNIC Mode |
|--------|-------------------|---------------|
| **Packet Path** | Through ARM cores | Hardware offload |
| **Performance** | 10-20 Gbps/core | Up to 400 Gbps |
| **CPU Usage** | High (ARM processes packets) | Low (ARM configures only) |
| **Latency** | 50-200 μs | <1 μs |
| **Flexibility** | Full (any processing) | Limited (flow engine actions) |
| **Programming Model** | DPDK application on ARM | rte_flow/DOCA Flow rules |

### Classic DPDK Mode (Separated Host Mode)

**Data Path**:
```
Packet arrives → NIC DMA to ARM → ARM polls RX queue →
DPDK app processes → ARM writes TX queue → NIC DMA from ARM →
Packet sent
```

**Use Cases**:
- Custom packet processing logic
- Complex stateful applications
- Flexibility more important than performance
- Prototyping and development

**Performance**: 10-20 Gbps per ARM core, 100% CPU usage

### SmartNIC Mode (Embedded Switch Mode)

**Data Path**:
```
Packet arrives → Hardware parser → Flow engine lookup →
Match found → Execute actions in hardware → Forward to destination
(ARM not involved in data path!)
```

**Use Cases**:
- High-performance virtual switching
- Line-rate packet forwarding
- Standard network operations (NAT, VXLAN, routing)
- OVS hardware offload

**Performance**: Up to 400 Gbps, <1% CPU usage

### Hybrid Mode (Best of Both Worlds)

**Architecture**:
```
                    ┌─────────────────────┐
                    │  NIC Flow Engine    │
                    │  (Hardware)         │
                    └──────┬──────────────┘
                           │
            ┌──────────────┼──────────────┐
            │              │              │
            ↓              ↓              ↓
     Known flows    Unknown flows   Exception
     (hardware)     (to ARM/DPA)    packets
            │              │              │
            ↓              ↓              ↓
        Line-rate    ARM processes   Complex
        forward      & installs      processing
                     flow rule
```

**Typical Deployment**: OVS with hardware offload
- First packet: ~100 μs (ARM slow path)
- Subsequent packets: <1 μs (hardware fast path)
- Result: Line-rate performance with ARM handling exceptions

### Mode Selection Guide

```
Question: Do you need line-rate performance (>40 Gbps)?
    │
    ├─ Yes → Question: Are your packet operations supported by flow engine?
    │         │
    │         ├─ Yes (NAT, VXLAN, L2/L3 forward) → SmartNIC Mode
    │         │
    │         └─ No (TCP seq/ack, custom headers) → Hybrid Mode (SmartNIC + DPA)
    │
    └─ No → Question: Do you need maximum flexibility?
              │
              ├─ Yes → Classic DPDK Mode
              │
              └─ No → SmartNIC Mode (simpler, more efficient)
```

## Key Architectural Insights

### 1. Unified Flow Pipeline
- There is **ONE** flow engine that handles everything
- eSwitch is not separate hardware - it's part of the flow engine
- All forwarding decisions go through the same tables

### 2. Hybrid Processing Model
```
Simple operations → NIC Flow Engine (line-rate, fixed-function)
Complex operations → DPA (high-rate, programmable)
Control plane → ARM Cores (flexible, software)
```

### 3. Port Representors Are Virtual
- Not physical ports, but logical endpoints
- Just IDs in the flow table
- Enable flexible virtual switching

### 4. DPA is Hardware, But Programmable
- Not software (it's physical cores)
- Not fixed-function (you program it)
- Best of both worlds: programmability + hardware speed

## Next Steps
- Read [[Packet Pipeline|Packet Processing Pipeline]] to understand data flow
- See [[Eswitch Flow Engine|eSwitch and Flow Engine]] for programming details
- Explore [[DPA Programming]] for custom processing
