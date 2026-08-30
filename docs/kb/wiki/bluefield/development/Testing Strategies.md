---
type: Wiki Entry
title: "Testing Strategies for BF3 DPU Applications"
description: "Comprehensive testing approach for validating DPDK/DOCA applications on BlueField-3."
tags: [bluefield, development]
timestamp: 2026-05-23T16:09:41+03:00
---

Source: `infra/bluefield/docs/04-development/testing-strategies.md`

# Testing Strategies for BF3 DPU Applications

## Overview
Comprehensive testing approach for validating DPDK/DOCA applications on BlueField-3.

**Note**: This guide covers testing **with physical hardware**. For local development and testing without hardware access, see [[Local Simulation Strategies]] which covers DPDK virtual devices, testpmd workflows, and container-based testing.

## Testing Tool Comparison

| Tool | Performance | Complexity | Best For |
|------|-------------|------------|----------|
| **tcpdump + scapy** | Low (~1-10 Gbps) | Very Low | Functional testing, debugging |
| **iperf3** | Medium (~10-40 Gbps) | Low | TCP throughput, real connections |
| **pktgen** | High (~10-40 Gbps) | Medium | Kernel-based load testing |
| **DOCA Test Framework** | Highest (~100-400 Gbps) | High | Performance benchmarking, line-rate |

## Testing Pyramid

```
                    ┌─────────────────┐
                    │  Performance    │  DOCA Framework
                    │  Benchmarking   │  (Hours)
                    └─────────────────┘
                ┌───────────────────────┐
                │    Load Testing       │  pktgen
                │    (Moderate scale)   │  (30 min)
                └───────────────────────┘
        ┌───────────────────────────────────┐
        │     Functional Testing            │  scapy/tcpdump
        │     (Quick validation)            │  (5 min)
        └───────────────────────────────────┘
```

## Method 1: tcpdump + scapy (Functional Testing)

### When to Use
- ✅ Quick connectivity validation
- ✅ Debugging packet modifications
- ✅ Protocol compliance testing
- ✅ Analyzing packet headers
- ❌ NOT for performance testing

### Setup

```bash
# Terminal 1 (Receiver): Capture packets
sudo tcpdump -i enp3s0f0 -e -n -vv

# Terminal 2 (Sender): Generate packets
sudo python3 -c '
from scapy.all import *
sendp(
    Ether(dst="aa:bb:cc:dd:ee:ff")/
    IP(dst="10.0.0.2")/
    UDP(dport=12345)/
    Raw(load="test payload"),
    iface="enp3s0f1",
    count=10
)
'
```

### Example Test Cases

#### Test 1: Basic Connectivity
```python
from scapy.all import *

# Send simple packet
pkt = Ether(dst="ff:ff:ff:ff:ff:ff")/IP(dst="10.0.0.2")/ICMP()
sendp(pkt, iface="eth0", count=5)
```

#### Test 2: Verify MAC Modification
```python
# Send with specific MAC
pkt = Ether(src="00:11:22:33:44:55", dst="aa:bb:cc:dd:ee:ff")/IP()
sendp(pkt, iface="eth0")

# On receiver, verify MAC was changed by DPU
# Expected: src MAC modified to something else
```

#### Test 3: VXLAN Encapsulation
```python
# Send inner packet
inner = Ether()/IP(dst="192.168.1.1")/TCP()
sendp(inner, iface="eth0")

# On receiver, verify VXLAN header added:
# Ether/IP/UDP(dport=4789)/VXLAN/InnerPacket
```

### Advantages
- ✅ Extremely simple
- ✅ See actual packet contents
- ✅ Easy to debug
- ✅ No compilation needed

### Limitations
- ❌ Low performance (~1-10 Gbps)
- ❌ Can't test line-rate
- ❌ High CPU overhead

## Method 2: iperf3 (TCP Throughput)

### When to Use
- ✅ Real TCP connection testing
- ✅ Bandwidth measurements
- ✅ Stateful flow testing
- ✅ Comparing with baseline

### Setup

```bash
# Server (receiver)
iperf3 -s

# Client (sender)
iperf3 -c 10.0.0.2 -t 60 -P 10
# -t 60: Run for 60 seconds
# -P 10: 10 parallel connections
```

### Example Test Cases

#### Test 1: Single Connection Throughput
```bash
iperf3 -c 10.0.0.2 -t 30
```

#### Test 2: Multiple Connections (Stress Test)
```bash
iperf3 -c 10.0.0.2 -t 60 -P 100
# 100 parallel TCP connections
```

#### Test 3: UDP Bandwidth Test
```bash
# Server
iperf3 -s

# Client: Send at 10 Gbps
iperf3 -c 10.0.0.2 -u -b 10G -t 60
```

#### Test 4: Bidirectional
```bash
iperf3 -c 10.0.0.2 -t 30 --bidir
```

### Advantages
- ✅ Real TCP behavior
- ✅ Easy to use
- ✅ Standard tool
- ✅ Measures actual throughput

### Limitations
- ❌ Limited to TCP/UDP
- ❌ Can't customize packets
- ❌ ~10-40 Gbps max

## Method 3: pktgen (Kernel Packet Generator)

### When to Use
- ✅ High-rate UDP testing
- ✅ Automated testing
- ✅ Simple CI/CD integration
- ✅ Medium-scale load tests

### Setup Script

```bash
#!/bin/bash
set -euo pipefail

# Configuration
IF="ens16f0np0"
SRC_IP="10.13.36.33"
DST_IP="10.13.36.46"
DST_MAC="02:25:f2:8d:a2:4c"
PKT_SIZE="512"
PKT_COUNT="1000000"
DELAY_NS="0"  # 0 = line-rate

# Load pktgen module
modprobe pktgen

# Helper function
pg_write() {
    echo "$2" > "$1"
}

# Reset and assign device
pg_write /proc/net/pktgen/kpktgend_0 "rem_device_all"
pg_write /proc/net/pktgen/kpktgend_0 "add_device $IF"

PGDEV="/proc/net/pktgen/$IF"

# Configure
pg_write "$PGDEV" "clone_skb 0"
pg_write "$PGDEV" "pkt_size $PKT_SIZE"
pg_write "$PGDEV" "delay $DELAY_NS"
pg_write "$PGDEV" "count $PKT_COUNT"
pg_write "$PGDEV" "dst_mac $DST_MAC"
pg_write "$PGDEV" "dst $DST_IP"
pg_write "$PGDEV" "src_min $SRC_IP"
pg_write "$PGDEV" "src_max $SRC_IP"

# Start test
echo "Starting pktgen test..."
pg_write /proc/net/pktgen/pgctrl "start"

# Results
echo "=== RESULTS ==="
cat "$PGDEV"

echo "=== NIC STATS ==="
cat "/sys/class/net/$IF/statistics/tx_packets"
cat "/sys/class/net/$IF/statistics/rx_packets"
```

### Advanced pktgen: Multi-Flow

```bash
# Generate multiple flows (different src IPs)
pg_write "$PGDEV" "src_min 10.0.0.1"
pg_write "$PGDEV" "src_max 10.0.0.254"
pg_write "$PGDEV" "flows 1000"
# Now generates 1000 different src IPs
```

### Advantages
- ✅ High performance (~40 Gbps)
- ✅ Scriptable
- ✅ Built into Linux
- ✅ Good for automation

### Limitations
- ❌ Kernel-based (not true line-rate)
- ❌ Limited packet customization
- ❌ UDP only (no TCP)

## Method 4: DOCA Test Framework (Performance Benchmarking)

### When to Use
- ✅ Line-rate performance testing
- ✅ Hardware offload validation
- ✅ Latency measurements
- ✅ Production readiness

### Example Test Application

```c
#include <rte_eal.h>
#include <rte_ethdev.h>
#include <rte_mbuf.h>
#include <time.h>

#define BURST_SIZE 32
#define TEST_DURATION_SEC 60

struct test_stats {
    uint64_t tx_packets;
    uint64_t rx_packets;
    uint64_t tx_bytes;
    uint64_t rx_bytes;
    uint64_t drops;
    double duration_sec;
};

void benchmark_throughput(uint16_t port_id, uint16_t queue_id) {
    struct rte_mbuf *tx_pkts[BURST_SIZE];
    struct rte_mbuf *rx_pkts[BURST_SIZE];
    struct test_stats stats = {0};
    
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);
    
    while (1) {
        // Generate packets
        if (rte_pktmbuf_alloc_bulk(pktmbuf_pool, tx_pkts, BURST_SIZE) == 0) {
            for (int i = 0; i < BURST_SIZE; i++) {
                build_test_packet(tx_pkts[i], 64);  // Min size packet
            }
            
            // Send burst
            uint16_t nb_tx = rte_eth_tx_burst(port_id, queue_id, 
                                              tx_pkts, BURST_SIZE);
            stats.tx_packets += nb_tx;
            stats.tx_bytes += nb_tx * 64;
            
            // Free unsent
            for (int i = nb_tx; i < BURST_SIZE; i++) {
                rte_pktmbuf_free(tx_pkts[i]);
            }
        }
        
        // Receive packets
        uint16_t nb_rx = rte_eth_rx_burst(port_id, queue_id, 
                                          rx_pkts, BURST_SIZE);
        stats.rx_packets += nb_rx;
        
        for (int i = 0; i < nb_rx; i++) {
            stats.rx_bytes += rte_pktmbuf_pkt_len(rx_pkts[i]);
            rte_pktmbuf_free(rx_pkts[i]);
        }
        
        // Check duration
        clock_gettime(CLOCK_MONOTONIC, &end);
        double elapsed = (end.tv_sec - start.tv_sec) + 
                        (end.tv_nsec - start.tv_nsec) / 1e9;
        
        if (elapsed >= TEST_DURATION_SEC) {
            stats.duration_sec = elapsed;
            break;
        }
    }
    
    // Calculate metrics
    double tx_gbps = (stats.tx_bytes * 8) / (stats.duration_sec * 1e9);
    double rx_gbps = (stats.rx_bytes * 8) / (stats.duration_sec * 1e9);
    double tx_mpps = stats.tx_packets / (stats.duration_sec * 1e6);
    double rx_mpps = stats.rx_packets / (stats.duration_sec * 1e6);
    
    printf("=== BENCHMARK RESULTS ===\n");
    printf("Duration: %.2f seconds\n", stats.duration_sec);
    printf("TX: %.2f Gbps, %.2f Mpps\n", tx_gbps, tx_mpps);
    printf("RX: %.2f Gbps, %.2f Mpps\n", rx_gbps, rx_mpps);
    printf("Packets: TX=%lu, RX=%lu\n", stats.tx_packets, stats.rx_packets);
}
```

### Latency Measurement

```c
#include <rte_cycles.h>

void measure_latency(uint16_t port_id) {
    const int NUM_SAMPLES = 10000;
    uint64_t latencies[NUM_SAMPLES];
    
    for (int i = 0; i < NUM_SAMPLES; i++) {
        struct rte_mbuf *pkt = rte_pktmbuf_alloc(pool);
        
        // Add timestamp to packet
        uint64_t *ts = rte_pktmbuf_mtod(pkt, uint64_t *);
        *ts = rte_get_tsc_cycles();
        
        // Send packet
        while (rte_eth_tx_burst(port_id, 0, &pkt, 1) == 0);
        
        // Receive (assuming loopback)
        struct rte_mbuf *rx_pkt;
        while (rte_eth_rx_burst(port_id, 0, &rx_pkt, 1) == 0);
        
        // Calculate latency
        uint64_t *rx_ts = rte_pktmbuf_mtod(rx_pkt, uint64_t *);
        latencies[i] = rte_get_tsc_cycles() - *rx_ts;
        
        rte_pktmbuf_free(rx_pkt);
    }
    
    // Calculate statistics
    uint64_t sum = 0, min = UINT64_MAX, max = 0;
    for (int i = 0; i < NUM_SAMPLES; i++) {
        sum += latencies[i];
        if (latencies[i] < min) min = latencies[i];
        if (latencies[i] > max) max = latencies[i];
    }
    
    uint64_t avg = sum / NUM_SAMPLES;
    double freq_ghz = rte_get_tsc_hz() / 1e9;
    
    printf("=== LATENCY RESULTS ===\n");
    printf("Min: %.2f μs\n", min / freq_ghz / 1000);
    printf("Avg: %.2f μs\n", avg / freq_ghz / 1000);
    printf("Max: %.2f μs\n", max / freq_ghz / 1000);
}
```

### Advantages
- ✅ True line-rate (400 Gbps)
- ✅ Hardware timestamp support
- ✅ Full packet control
- ✅ Accurate measurements

### Limitations
- ❌ Complex setup
- ❌ Requires C programming
- ❌ Time-consuming development

## Recommended Testing Workflow

### Stage 1: Quick Validation (5 minutes)

```bash
# Test connectivity
ping 10.0.0.2

# Verify packet flow
sudo tcpdump -i eth0 -c 10 &
sudo python3 -c 'from scapy.all import *; sendp(IP(dst="10.0.0.2")/ICMP(), iface="eth1", count=5)'

# Check: Packets visible on both interfaces?
```

### Stage 2: Functional Testing (30 minutes)

```python
# test_suite.py
from scapy.all import *

def test_mac_forwarding():
    """Test basic MAC-based forwarding"""
    pkt = Ether(dst="aa:bb:cc:dd:ee:01")/IP()
    sendp(pkt, iface="eth0")
    # Verify on tcpdump

def test_vlan_handling():
    """Test VLAN push/pop"""
    pkt = Ether()/Dot1Q(vlan=100)/IP()
    sendp(pkt, iface="eth0")
    # Verify VLAN removed/modified

def test_nat():
    """Test IP address translation"""
    pkt = Ether()/IP(src="10.0.0.1", dst="10.0.0.2")/TCP()
    sendp(pkt, iface="eth0")
    # Verify IP modified

# Run all tests
test_mac_forwarding()
test_vlan_handling()
test_nat()
```

### Stage 3: Load Testing (1 hour)

```bash
# Use pktgen for moderate load
./pktgen_test.sh

# Check results
echo "Expected: >10 Gbps, <0.1% loss"
# Verify hardware counters
ethtool -S eth0 | grep -E "(rx_|tx_)"
```

### Stage 4: Performance Benchmarking (2 hours)

```bash
# Compile DOCA test app
cd doca-test-framework
meson build
ninja -C build

# Run throughput test
./build/doca_perf_test --mode throughput --duration 60

# Run latency test
./build/doca_perf_test --mode latency --samples 100000

# Verify offload
ovs-appctl dpctl/dump-flows type=offloaded
```

### Stage 5: Stress Testing (24 hours)

```bash
# Long-running stability test
./build/doca_perf_test --mode stress --duration 86400 --rate 80

# Monitor for:
# - Packet loss
# - Memory leaks
# - Performance degradation
# - Error counters
```

## Test Checklist

### Functional Tests
- [ ] Basic connectivity (ping)
- [ ] MAC-based forwarding
- [ ] VLAN tagging/untagging
- [ ] IP modification (NAT)
- [ ] Port modification (PAT)
- [ ] Tunnel encap/decap (VXLAN)
- [ ] Multi-flow support
- [ ] Broadcast/multicast handling

### Performance Tests
- [ ] Maximum throughput (small packets)
- [ ] Maximum throughput (large packets)
- [ ] Multi-queue RSS distribution
- [ ] Latency measurements
- [ ] Packet loss at line-rate
- [ ] CPU utilization

### Stress Tests
- [ ] 24-hour stability
- [ ] Table capacity (max flows)
- [ ] Burst traffic handling
- [ ] Resource exhaustion
- [ ] Failover scenarios

### Offload Validation
- [ ] Rules offloaded to hardware
- [ ] Hardware counters incrementing
- [ ] No software fallback
- [ ] Consistent performance

## Debugging Failed Tests

### High Packet Loss

```bash
# Check interface errors
ethtool -S eth0 | grep -E "drop|error"

# Check queue depths
cat /proc/net/pktgen/eth0

# Increase queue size
ethtool -G eth0 rx 4096 tx 4096

# Check flow table capacity
mlxdump -d <device> fsdump --type FT
```

### Low Throughput

```bash
# Check CPU pinning
taskset -cp <pid>

# Check NUMA
numactl --hardware
numactl --cpubind=0 --membind=0 ./app

# Check RSS configuration
ethtool -x eth0

# Enable hardware offloads
ethtool -K eth0 rx-checksumming on
ethtool -K eth0 tx-checksumming on
```

### Rules Not Offloaded

```bash
# Check why rule failed
ovs-appctl dpctl/dump-flows

# Simplify rule (remove unsupported actions)
# Check hardware capacity
mlxdump -d <device> fsdump --type FT | grep "num_of_entries"

# Enable debug logging
ovs-appctl vlog/set dpif_netlink_offload:dbg
```

## Key Takeaways

1. **Use tcpdump + scapy** for quick functional tests
2. **Use pktgen** for automated medium-scale testing
3. **Use DOCA framework** for line-rate performance
4. **Test in stages**: Functional → Load → Performance → Stress
5. **Always verify hardware offload** with counters
6. **Measure latency separately** from throughput
7. **Run long-term stability tests** before production

## Next Steps
- See [[Local Simulation Strategies]] for testing without hardware
- See [[Code Examples]] for complete test implementations
- Read [[Debugging Guide]] for troubleshooting
- Check [[Performance Tuning]] for optimization
