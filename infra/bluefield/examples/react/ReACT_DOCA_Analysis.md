# ReACT DOCA Application Analysis

## Credits

This ReACT DOCA application was developed by Dr David Hay at Princton University. The implementation demonstrates advanced DNS traffic filtering techniques using Bloom filters and hardware-accelerated packet processing on NVIDIA DPU hardware. Special thanks to David for developing this app and NVIDIA for providing the DOCA framework and sample infrastructure that served as the foundation for this research.

## Overview

ReACT is a **DNS traffic filtering application** built on NVIDIA's DOCA (Data Center Infrastructure on a Chip) framework designed to prevent DNS amplification attacks by filtering DNS responses based on previously seen legitimate requests using Bloom filters.

## Core Purpose & Goals

- **Filter DNS responses** based on previously seen DNS requests using Bloom filters
- **Prevent DNS amplification attacks** by only allowing responses to legitimate requests
- **Provide high-performance packet processing** using DPDK and DOCA Flow on DPU hardware
- **Demonstrate advanced data structures** (Bloom filters) with hardware-accelerated packet processing

## Architecture

### Network Flow
```
Internet → OVS Bridge → ReACT App → OVS Bridge → Host
         (br1)       (Filtering)    (br2)
```

- **Outgoing DNS requests** are copied to ReACT and forwarded normally
- **Incoming DNS responses** are sent to ReACT for filtering
- Only **legitimate responses** (matching previous requests) are forwarded to the host

### Key Components

1. **Main Application** (`react_main.c`): Entry point, argument parsing, DPDK initialization
2. **Packet Processing** (`react_arm.c`): Core packet processing logic on ARM cores
3. **Bloom Filter Implementation** (`react_sample.c`): Three types of Bloom filters
4. **Flow Management** (`react_sample.c`): DOCA Flow pipeline creation and management

## DNS Filtering Mechanism

### ❌ Common Misconception
The app does **NOT** block DNS requests. It actually **allows all DNS requests** to pass through normally.

### ✅ What ReACT Actually Does

**1. DNS Requests (Outgoing) - ALLOWED:**
- DNS requests are **copied** to the ReACT app for learning
- The original request **continues to the DNS server** normally
- ReACT extracts a 12-byte key: `(src_ip, dst_ip, client_port, dns_transaction_id)`
- This key is **added to the Bloom filter** for future reference
- The request packet is then **freed** (not forwarded by ReACT)

**2. DNS Responses (Incoming) - FILTERED:**
- DNS responses are sent to ReACT for **filtering decisions**
- ReACT extracts the same 12-byte key from the response
- **Checks the Bloom filter** to see if a matching request was seen
- **If found**: Response is forwarded to the client (legitimate)
- **If not found**: Response is **dropped** (potential attack)

### Packet Flow Diagram
```
Client Request → OVS br2 → [COPY] → ReACT App (learns key) → [DROP]
                    ↓
                DNS Server

DNS Server Response → OVS br1 → ReACT App (checks key) → [ALLOW/DROP]
                                                              ↓
                                                          Client
```

## Bloom Filter Types

The application implements **three different Bloom filter variants**:

1. **BLOOM_CLASSIC** (Type 0): Traditional bit array with sliding window
2. **BLOOM_COUNTING** (Type 1): Counts occurrences, decrements on hits
3. **BLOOM_THREAD_SAFE** (Type 2): Atomic operations for multi-threaded access

## Sliding Window Mechanism

- **3-phase rotation** for Classic and Thread-Safe filters
- **Bloom filter swapping** every `bloom_swap_interval` seconds (default: 6 seconds)
- **Phase management**: Each core maintains 3 Bloom filters (A, B, C) in rotation
- **Dual-checking**: Responses checked against current and previous phase filters

## Configuration Options

```bash
./react.sh [options]
  -s, --bloom-size <size>        # Bloom filter size in bits (default: 229376)
  -i, --bloom-swap <seconds>     # Swap interval (default: 6)
  -t, --bloom-type-counting <0|1|2>  # Filter type (default: 0)
  -c, --worker-cores <cores>     # Number of worker cores (default: 14)
  -o, --timeout <seconds>        # Application timeout (default: 0 = infinite)
```

## Packet Processing Logic

```c
if (burst_type == OUTGOING_REQUESTS) {
    // DNS REQUEST: Learn the key, then drop packet
    bloom_add(bf_add, key, 12);
    rte_pktmbuf_free(pkt);  // Drop - request already forwarded by OVS
}
else {
    // DNS RESPONSE: Check if we saw matching request
    if(bloom_check_with_indices(bf_add, h1, h2)) {
        // Found matching request - forward response
        tx_bufs[tx_count++] = pkt;
    }
    else {
        // No matching request - drop response (potential attack)
        rte_pktmbuf_free(pkt);
    }
}
```

## Deployment & Compilation

### Build System
- Uses **Meson** build system
- Requires **NVIDIA DOCA SDK** and **DPDK** dependencies
- Compiles with ARM Cortex-A72 optimizations (`-mcpu=cortex-a72+crc`)

### Build Commands
```bash
# Build the application
ninja -C build/

# Run with wrapper script
./react.sh [options]
```

### Dependencies
- `doca` (NVIDIA DOCA SDK)
- `libdpdk` (Data Plane Development Kit)
- Mellanox network hardware (`auxiliary:mlx5_core.sf.4`, `auxiliary:mlx5_core.sf.2`)

## Two Main Components

### 1. Main Control Thread (`react_main.c` + `flow_react()`)
- **Initialization**: Sets up DOCA Flow, DPDK, ports, and pipes
- **Bloom Filter Management**: Handles sliding window swapping every 6 seconds
- **Worker Coordination**: Launches and manages ARM core workers
- **Graceful Shutdown**: Handles signal processing and cleanup

### 2. Packet Processing Workers (`process_packets()` in `react_arm.c`)
- **Per-Core Processing**: Each ARM core runs this function
- **Packet Classification**: Distinguishes between DNS requests vs responses
- **Bloom Filter Operations**: Adds request keys, checks response legitimacy
- **High-Performance I/O**: Burst processing (64 packets/batch)

## Routing & Packet Steering

### OVS (Open vSwitch) Configuration
```bash
# DNS requests: Copy to ReACT + Forward normally
sudo ovs-ofctl add-flow br2 "priority=1000,in_port=5,dl_type=0x0800,nw_proto=17,tp_dst=53,actions=output:3,6"

# DNS responses: Send to ReACT for filtering  
sudo ovs-ofctl add-flow br1 "priority=1000,in_port=1,dl_type=0x0800,nw_proto=17,tp_src=53,actions=output:2"
```

### DOCA Flow Pipes
The app creates **5 different DOCA Flow pipes**:

1. **`react_PIPE_REQUESTS`** (Port 1): Captures outgoing DNS requests
2. **`react_PIPE_RESPONSES`** (Port 0): Captures incoming DNS responses  
3. **`COPY_TO_META_PIPE`** (Direction 0): Copies packet fields to metadata
4. **`COPY_TO_META_PIPE`** (Direction 1): Copies metadata back to packet headers
5. **`EGRESS_PIPE`** (Port 1): Handles egress traffic

## Testing & Evaluation Tools

The `test/` directory provides comprehensive testing infrastructure:

### Performance Testing
- `run_react_fp_sweep_20s.sh`: 20-second false positive rate sweep
- `run_react_fp_sweep_60s.sh`: 60-second false positive rate sweep

### Traffic Generation
- `generate_dns_queries.py`: Generate 1M DNS query packets
- `generate_dns_responses.py`: Generate 1M DNS response packets

### Analysis Tools
- `compare_dns_pcaps.py`: Compare before/after PCAPs for false positives/negatives
- `delay_dns_responses.sh`: Add artificial delay to DNS responses

### Monitoring
- `read_counters.sh`: Monitor interface packet counters
- `read_ovs_counters.sh`: Monitor OVS flow counters

### Automated Testing
- `run_dns_test_tmux.sh`: Full automated test environment with tmux

## Hardware Requirements

- **NVIDIA DPU** with DOCA support
- **Mellanox network interfaces** (`auxiliary:mlx5_core.sf.4`, `auxiliary:mlx5_core.sf.2`)
- **DPDK-compatible** network setup
- **OVS bridges** for traffic steering

## Performance Characteristics

- **Packet burst processing**: 64 packets per burst
- **Transmit batching**: 32 packets per TX burst
- **Flush interval**: 50µs
- **Multi-core processing**: Up to 14 worker cores
- **Memory optimization**: Cache-line aligned allocations

## Use Cases

1. **DNS Security**: Protection against DNS amplification attacks
2. **Traffic Filtering**: Legitimate request/response matching
3. **Performance Research**: Bloom filter algorithm comparison
4. **Network Middlebox**: High-speed packet processing demonstration

## Attack Prevention

This design prevents **DNS amplification attacks** where:
- Attackers send spoofed DNS requests with victim's IP
- DNS servers respond to the victim
- Victim gets flooded with unsolicited DNS responses

**ReACT's defense:**
- Only responses to **legitimate requests** (seen by ReACT) are forwarded
- Unsolicited responses are **dropped**
- The Bloom filter provides **fast lookup** for legitimate request/response matching

## Custom Development & File Structure

While built on NVIDIA DOCA sample boilerplate, significant custom development was added across multiple files. The core application files (`react_main.c`, `react_arm.c`, `react_sample.c`, `react.h`) contain extensive custom DNS filtering logic, Bloom filter implementations, and packet processing algorithms. The build system (`meson.build`) was customized to include the specific source files and dependencies. Additional custom files include the deployment wrapper (`react.sh`), OVS configuration (`ovs_config.sh`), and comprehensive testing infrastructure in the `test/` directory with Python scripts for traffic generation, performance evaluation, and automated testing. The entire `test/` directory represents a sophisticated custom testing framework built from scratch to evaluate the DNS filtering performance and false positive rates.

## Summary

ReACT is a sophisticated example of using DOCA for high-performance network security applications, combining advanced data structures (Bloom filters) with hardware-accelerated packet processing. The application serves as a **response filter** rather than a request blocker, ensuring only legitimate DNS responses reach clients while maintaining high throughput and low latency.
