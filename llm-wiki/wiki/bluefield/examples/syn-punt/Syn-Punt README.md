---
type: Wiki Entry
title: "SYN Punt Application"
description: "A production-quality DOCA application demonstrating hardware-accelerated packet processing with selective exception handling on NVIDIA BlueField-3 DPU."
tags: [bluefield, examples, syn-punt]
timestamp: 2026-05-23T16:09:41+03:00
---

Source: `infra/bluefield/examples/syn-punt/README.md`

# SYN Punt Application

A production-quality DOCA application demonstrating hardware-accelerated packet processing with selective exception handling on NVIDIA BlueField-3 DPU.

## Overview

This application leverages DOCA Flow to program the BlueField-3 eswitch for intelligent packet steering:

- **SYN packets**: Punted to software (exception path) for inspection and logging
- **All other packets**: Fast-forwarded in hardware (data path bypass)

### Key Features

✅ **Hardware Offload**: DOCA Flow programs eswitch for line-rate forwarding
✅ **Selective Processing**: Only SYN packets processed by ARM cores
✅ **Zero Performance Impact**: Non-SYN packets bypass software entirely
✅ **Structured Codebase**: OOP-style C with clear module separation
✅ **Production Ready**: Comprehensive error handling and logging
✅ **Test Suite**: Automated testing with packet generation and verification

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  BlueField-3 DPU                        │
│                                                         │
│  Network ──► eSwitch ──┬──► RSS Queues ──► Fast Path  │
│                  │     │                                │
│                  │     └──► Queue 0 ──► SYN Punt App   │
│                  │            (ARM)         │           │
│                  │                          ▼           │
│                  │                    Print & Forward   │
│                  │                          │           │
│                  └──────────────────────────┴──► Network│
└─────────────────────────────────────────────────────────┘

DOCA Flow Pipeline:
┌──────────────────────────────────────────┐
│  Root Pipe: Match TCP SYN                │
│  ├─ Match: TCP flags & 0x02 = 0x02       │
│  ├─ Action (hit): Forward to Queue 0     │
│  └─ Action (miss): Forward to RSS        │
└──────────────────────────────────────────┘
```

## Code Structure

```
syn-punt/
├── src/
│   ├── main.c              # Entry point, argument parsing, initialization
│   ├── utils.{c,h}         # Common types, context management
│   ├── dpdk_init.{c,h}     # DPDK EAL and port initialization
│   ├── doca_flow.{c,h}     # DOCA Flow pipe creation and management
│   ├── packet_parser.{c,h} # TCP/IP packet parsing
│   └── packet_processor.{c,h} # RX/TX loop and packet handling
├── tests/
│   ├── test_sender.py      # Scapy-based packet generator
│   └── test_verify.sh      # Automated verification script
├── meson.build             # Build configuration
├── run.sh                  # Quick launch script
└── README.md               # This file
```

### Module Responsibilities

| Module | Responsibility |
|--------|----------------|
| `main.c` | Application lifecycle, argument parsing (DOCA argp) |
| `dpdk_init` | DPDK EAL initialization, port configuration, queue setup |
| `doca_flow` | DOCA Flow init, pipe creation, entry management |
| `packet_parser` | L2/L3/L4 header parsing, TCP flag detection |
| `packet_processor` | RX burst, packet inspection, TX forwarding |
| `utils` | Shared types, context management, formatting |

## Prerequisites

### Hardware
- NVIDIA BlueField-3 DPU
- 2x Scalable Functions (SFs) configured (see [SF Setup](#sf-setup))

### Software
- DOCA SDK 2.5.0 or later (`/opt/mellanox/doca/`)
- DPDK 22.11 or later (`/opt/mellanox/dpdk/`)
- Meson build system (`apt install meson`)
- Python 3.8+ with scapy (`pip3 install scapy`)

### Verify Installation
```bash
# Check DOCA SDK
ls /opt/mellanox/doca/lib/

# Check DPDK
dpdk-testpmd --version

# Check hugepages
cat /proc/meminfo | grep HugePages
```

## Build Instructions

### Option 1: Native Build (on DPU ARM)
```bash
cd examples/syn-punt

# Configure build
meson setup build

# Compile
ninja -C build

# Binary location
ls build/syn_punt
```

### Option 2: Docker Build (recommended)
```bash
# Pull DOCA Docker image
docker pull nvcr.io/nvidia/doca/doca:2.5.0-devel

# Run container with SF access
docker run -it --rm \
    --privileged \
    --network host \
    -v $(pwd):/workspace \
    nvcr.io/nvidia/doca/doca:2.5.0-devel \
    bash

# Inside container
cd /workspace/examples/syn-punt
meson setup build
ninja -C build
```

## Running the Application

### Quick Start
```bash
# Run with default settings (port 0)
sudo ./run.sh

# Or run directly
sudo ./build/syn_punt -l 0-1 -a 03:00.0 -- -p 0
```

### EAL Arguments Explained
```bash
sudo ./build/syn_punt \
    -l 0-1                  # Use CPU cores 0-1
    -a 03:00.0              # Attach PCI device (adjust for your SF)
    --                      # Separator between EAL and app args
    -p 0                    # Use DPDK port 0
    -t 60                   # Run for 60 seconds (optional)
```

### Finding Your SF PCI Address
```bash
# List all network devices
lspci | grep Mellanox

# Get representor ports
dpdk-testpmd -l 0-1 -a 03:00.0,representor=sf0 -- --list

# Or use ip link
ip link show | grep sf
```

## Testing

### Manual Testing

**Terminal 1 - Run Application:**
```bash
sudo ./build/syn_punt -l 0-1 -a 03:00.0 -- -p 0
```

**Terminal 2 - Send Test Packets:**
```bash
# Send SYN packets (should be printed by app)
sudo python3 tests/test_sender.py eth0 --syn-only --syn-count 10

# Send comprehensive test
sudo python3 tests/test_sender.py eth0 --syn-count 10 --data-count 100
```

### Automated Testing
```bash
# Run full verification suite
sudo tests/test_verify.sh eth0
```

### Expected Output

**Application Output (SYN packets):**
```
=== SYN Packet Detected ===
  ETH: 00:11:22:33:44:55 -> ff:ff:ff:ff:ff:ff
  IP:  192.168.1.100 -> 10.0.0.2
  TCP: 54321 -> 80
  Seq: 1000, Ack: 0
  Flags: SYN
===========================
```

**Non-SYN packets**: No output (fast-forwarded in hardware)

## SF Setup

### Creating Scalable Functions

```bash
# Enable SR-IOV
echo 2 > /sys/class/net/p0/device/sriov_numvfs

# Create SF on PF0
mlxdevm sf add pci/0000:03:00.0 pfnum 0 sfnum 0
mlxdevm sf add pci/0000:03:00.0 pfnum 0 sfnum 1

# Activate SFs
mlxdevm sf state set pci/0000:03:00.0/0 state active
mlxdevm sf state set pci/0000:03:00.0/1 state active

# Verify SFs
mlxdevm sf show
```

### Binding SF to Docker Container

```bash
# Get SF representor PCI address
SF_PCI=$(mlxdevm sf show | grep sf0 | awk '{print $1}')

# Run container with SF access
docker run -it --rm \
    --privileged \
    --network host \
    --device /dev/infiniband/uverbs0 \
    --device /dev/infiniband/uverbs1 \
    -v /sys/class/net:/sys/class/net \
    -v /dev/hugepages:/dev/hugepages \
    nvcr.io/nvidia/doca/doca:2.5.0-devel \
    bash
```

## OVS Bridge Configuration

**Note**: For basic SF-to-SF forwarding, OVS bridges are **NOT required**. The application works with default SF representor ports.

**When you DO need OVS**:
- Connecting SFs to external physical ports
- Traffic cloning/mirroring
- Multiple applications with different traffic steering

**Example OVS Setup** (optional):
```bash
# Create bridge
ovs-vsctl add-br br0

# Add physical port
ovs-vsctl add-port br0 p0

# Add SF representors
ovs-vsctl add-port br0 pf0sf0_repr
ovs-vsctl add-port br0 pf0sf1_repr

# Configure flows
ovs-ofctl add-flow br0 "in_port=pf0sf0_repr,actions=output:p0"
ovs-ofctl add-flow br0 "in_port=p0,actions=output:pf0sf0_repr"
```

## Performance Considerations

### Fast Path Performance
- **Non-SYN packets**: Line-rate forwarding (hardware only)
- **Zero CPU overhead**: Non-SYN traffic bypasses ARM cores
- **Latency**: Sub-microsecond (eswitch switching)

### Exception Path Performance
- **SYN packets**: ~1-2 µs ARM processing + parsing + printing
- **Throughput**: ~1M SYN packets/sec per core
- **CPU usage**: Linear with SYN packet rate

### Tuning
```bash
# Increase RX/TX descriptors for high SYN rate
# Edit src/utils.h:
#define RING_SIZE 4096  # Default: 1024

# Add more RX queues
# Edit main.c initialization:
ctx.config.nb_queues = 4;
```

## Troubleshooting

### Application Won't Start

**Error**: `Failed to initialize DPDK EAL`
```bash
# Check hugepages
sudo sysctl -w vm.nr_hugepages=2048
cat /proc/meminfo | grep HugePages
```

**Error**: `Failed to start DOCA Flow port`
```bash
# Verify PCI device is correct
lspci | grep Mellanox

# Check if device is already bound
ls /sys/bus/pci/devices/0000:03:00.0/
```

### No SYN Packets Detected

**Check hardware flow rules**:
```bash
# Verify DOCA Flow entries (requires root)
sudo doca_flow_dump -p 0

# Or use ethtool
sudo ethtool -S p0 | grep hw_flow
```

**Verify packet generator**:
```bash
# Capture on sending interface
sudo tcpdump -i eth0 'tcp[tcpflags] & tcp-syn != 0' -n
```

### Performance Issues

**High CPU usage**:
```bash
# Check if non-SYN packets are being punted (they shouldn't be)
# Monitor application statistics output

# Verify hardware offload is active
cat /sys/class/net/p0/device/*/hw_tc_offload
```

## Development

### Adding New Features

**Example: Add RST packet punt**

1. **Update DOCA Flow** (`src/doca_flow.c`):
```c
match.outer.tcp.flags = RTE_TCP_SYN_FLAG | RTE_TCP_RST_FLAG;
match_mask.outer.tcp.flags = RTE_TCP_SYN_FLAG | RTE_TCP_RST_FLAG;
```

2. **Update Parser** (`src/packet_parser.h`):
```c
static inline bool is_rst_packet(const struct packet_info *info) {
    return info->is_tcp && (info->tcp_flags & RTE_TCP_RST_FLAG);
}
```

3. **Update Processor** (`src/packet_processor.c`):
```c
if (is_syn_packet(&info)) {
    // Handle SYN
} else if (is_rst_packet(&info)) {
    // Handle RST
}
```

### Code Style
- Follow Linux kernel coding style
- Use DOCA logging macros (DOCA_LOG_INFO, DOCA_LOG_ERR)
- Document all public functions with Doxygen comments
- Keep modules focused (single responsibility principle)

## References

- [DOCA Flow Programming Guide](https://docs.nvidia.com/doca/sdk/doca+flow+programming+guide/)
- [BlueField DPU Documentation](https://docs.nvidia.com/networking/display/bluefielddpuosdocumentation)
- [DPDK Programmer's Guide](https://doc.dpdk.org/guides/prog_guide/)

## License

Copyright (c) 2024 NVIDIA CORPORATION & AFFILIATES. ALL RIGHTS RESERVED.

## Support

For issues and questions:
- File issues on GitHub
- Check DOCA SDK documentation
- NVIDIA Developer Forums: https://forums.developer.nvidia.com/
