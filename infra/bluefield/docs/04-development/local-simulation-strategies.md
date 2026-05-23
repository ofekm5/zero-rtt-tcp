# Local Simulation Strategies for DOCA/DPDK Development

## Overview

This guide covers strategies for developing and testing DOCA/DPDK applications locally without physical BlueField hardware. Local simulation can validate approximately **70-80%** of code functionality before deployment to actual DPUs.

### What Can Be Tested Locally

| Component | Local Testing | Requires Hardware |
|-----------|---------------|-------------------|
| DPDK EAL initialization | ✅ | |
| Packet buffer management | ✅ | |
| rte_flow rule syntax | ✅ | |
| Application logic | ✅ | |
| Basic packet I/O | ✅ | |
| Multi-queue handling | ✅ | |
| Hardware offload verification | | ✅ |
| Line-rate performance | | ✅ |
| eSwitch/representors | | ✅ |
| DPA programming | | ✅ |
| Actual flow offloading | | ✅ |

---

## Part 1: DPDK Virtual Devices

### 1.1 Available Virtual PMDs

DPDK provides several virtual Poll Mode Drivers for testing:

| PMD | Use Case | Features |
|-----|----------|----------|
| `net_null` | Performance testing | Drops all packets, no I/O |
| `net_ring` | Inter-process communication | Ring-based packet transfer |
| `net_pcap` | Capture/replay | Read/write PCAP files |
| `net_tap` | Kernel integration | Linux TAP devices |
| `net_veth` | Container networking | Virtual ethernet pairs |
| `net_af_packet` | Raw sockets | Linux AF_PACKET |
| `net_memif` | High-speed IPC | Shared memory interface |

### 1.2 Null PMD (net_null)

Best for: Testing application logic and basic DPDK operations without actual packet I/O.

```bash
# Run application with null PMD
./my_app -l 0-3 -n 4 \
    --vdev 'net_null0' \
    --vdev 'net_null1'
```

```c
// In code: configure null ports
#define NULL_PMD_DRIVER "net_null"

int init_null_ports(void) {
    char devargs[64];
    
    // Create two null ports
    snprintf(devargs, sizeof(devargs), "%s0", NULL_PMD_DRIVER);
    if (rte_eal_hotplug_add("vdev", devargs, "") < 0) {
        return -1;
    }
    
    snprintf(devargs, sizeof(devargs), "%s1", NULL_PMD_DRIVER);
    if (rte_eal_hotplug_add("vdev", devargs, "") < 0) {
        return -1;
    }
    
    return 0;
}
```

**Limitations**: No actual packet data, counters always zero.

### 1.3 PCAP PMD (net_pcap)

Best for: Replaying captured traffic and validating packet processing logic.

```bash
# Replay PCAP file
./my_app -l 0-3 -n 4 \
    --vdev 'net_pcap0,rx_pcap=input.pcap,tx_pcap=output.pcap'

# Multiple interfaces with different files
./my_app -l 0-3 -n 4 \
    --vdev 'net_pcap0,rx_pcap=port0_rx.pcap,tx_pcap=port0_tx.pcap' \
    --vdev 'net_pcap1,rx_pcap=port1_rx.pcap,tx_pcap=port1_tx.pcap'

# Infinite replay mode
./my_app -l 0-3 -n 4 \
    --vdev 'net_pcap0,rx_pcap=input.pcap,infinite_rx=1'
```

**Creating Test PCAPs with Scapy**:

```python
#!/usr/bin/env python3
# generate_test_pcap.py
from scapy.all import *

packets = []

# TCP SYN packets
for i in range(100):
    pkt = Ether(src="00:11:22:33:44:55", dst="aa:bb:cc:dd:ee:ff") / \
          IP(src=f"10.0.0.{i % 256}", dst="192.168.1.1") / \
          TCP(sport=1024 + i, dport=80, flags="S", seq=1000 + i)
    packets.append(pkt)

# UDP packets
for i in range(100):
    pkt = Ether(src="00:11:22:33:44:55", dst="aa:bb:cc:dd:ee:ff") / \
          IP(src="10.0.0.1", dst="192.168.1.1") / \
          UDP(sport=5000, dport=53) / \
          DNS(rd=1, qd=DNSQR(qname=f"test{i}.example.com"))
    packets.append(pkt)

# VXLAN encapsulated packets
for i in range(50):
    inner = Ether(src="00:00:00:00:00:01", dst="00:00:00:00:00:02") / \
            IP(src="172.16.0.1", dst="172.16.0.2") / \
            TCP(sport=8080, dport=443)
    
    outer = Ether(src="00:11:22:33:44:55", dst="aa:bb:cc:dd:ee:ff") / \
            IP(src="10.0.0.1", dst="10.0.0.2") / \
            UDP(sport=4789, dport=4789) / \
            VXLAN(vni=100) / \
            inner
    packets.append(outer)

wrpcap("test_traffic.pcap", packets)
print(f"Generated {len(packets)} packets")
```

### 1.4 TAP PMD (net_tap)

Best for: Integration with Linux networking stack and tools like tcpdump.

```bash
# Create TAP interface
./my_app -l 0-3 -n 4 \
    --vdev 'net_tap0,iface=dtap0' \
    --vdev 'net_tap1,iface=dtap1'
```

```bash
# In another terminal: configure and monitor TAP interfaces
sudo ip link set dtap0 up
sudo ip addr add 10.0.0.1/24 dev dtap0

# Capture traffic
sudo tcpdump -i dtap0 -w captured.pcap

# Send traffic to the TAP interface
sudo ip netns exec test_ns ping 10.0.0.1
```

**TAP with Network Namespaces**:

```bash
#!/bin/bash
# setup_tap_namespaces.sh

# Create network namespace
sudo ip netns add ns_sender
sudo ip netns add ns_receiver

# Create veth pairs
sudo ip link add veth_sender type veth peer name veth_sender_br
sudo ip link add veth_receiver type veth peer name veth_receiver_br

# Move to namespaces
sudo ip link set veth_sender netns ns_sender
sudo ip link set veth_receiver netns ns_receiver

# Configure sender namespace
sudo ip netns exec ns_sender ip addr add 10.0.0.1/24 dev veth_sender
sudo ip netns exec ns_sender ip link set veth_sender up
sudo ip netns exec ns_sender ip link set lo up

# Configure receiver namespace
sudo ip netns exec ns_receiver ip addr add 10.0.0.2/24 dev veth_receiver
sudo ip netns exec ns_receiver ip link set veth_receiver up
sudo ip netns exec ns_receiver ip link set lo up

# Bring up bridge-side interfaces
sudo ip link set veth_sender_br up
sudo ip link set veth_receiver_br up

echo "Namespaces ready. Start DPDK app with TAP PMD connected to veth_*_br"
```

### 1.5 Ring PMD (net_ring)

Best for: Inter-process communication and testing multi-process DPDK applications.

```c
#include <rte_ring.h>
#include <rte_eth_ring.h>

int setup_ring_ports(void) {
    struct rte_ring *ring_rx, *ring_tx;
    
    // Create rings
    ring_rx = rte_ring_create("ring_rx", 1024, SOCKET_ID_ANY, 
                               RING_F_SP_ENQ | RING_F_SC_DEQ);
    ring_tx = rte_ring_create("ring_tx", 1024, SOCKET_ID_ANY,
                               RING_F_SP_ENQ | RING_F_SC_DEQ);
    
    if (!ring_rx || !ring_tx) {
        return -1;
    }
    
    // Create ring-based ethernet device
    int port_id = rte_eth_from_rings("net_ring0", 
                                      &ring_rx, 1,  // RX rings
                                      &ring_tx, 1,  // TX rings
                                      SOCKET_ID_ANY);
    
    return port_id;
}
```

### 1.6 Memif PMD (net_memif)

Best for: High-performance testing between containers or processes.

```bash
# Server mode (master)
./my_app -l 0-3 -n 4 \
    --vdev 'net_memif0,role=server,socket=/tmp/memif.sock'

# Client mode (slave) - in another process/container
./my_app -l 4-7 -n 4 \
    --vdev 'net_memif0,role=client,socket=/tmp/memif.sock'
```

---

## Part 2: testpmd Workflows

### 2.1 Basic testpmd Usage

testpmd is DPDK's built-in packet testing application, perfect for validating configurations.

```bash
# Start testpmd with virtual devices
sudo dpdk-testpmd -l 0-3 -n 4 \
    --vdev 'net_pcap0,rx_pcap=input.pcap,tx_pcap=output.pcap' \
    --vdev 'net_null1' \
    -- -i --portmask=0x3

# Interactive mode commands
testpmd> show port info all
testpmd> show port stats all
testpmd> start
testpmd> stop
testpmd> quit
```

### 2.2 testpmd Flow Rule Testing

Test rte_flow rules without hardware:

```bash
# Start testpmd
sudo dpdk-testpmd -l 0-3 -n 4 \
    --vdev 'net_null0' \
    --vdev 'net_null1' \
    -- -i

# Create flow rules
testpmd> flow create 0 ingress pattern eth / ipv4 dst is 192.168.1.1 / end actions queue index 1 / end
testpmd> flow create 0 ingress pattern eth / ipv4 / tcp dst is 80 / end actions drop / end

# List flows
testpmd> flow list 0

# Query flow
testpmd> flow query 0 0 count

# Destroy flow
testpmd> flow destroy 0 rule 0

# Validate without creating
testpmd> flow validate 0 ingress pattern eth / ipv4 / end actions queue index 0 / end
```

### 2.3 testpmd Forwarding Modes

```bash
# I/O forwarding (default)
testpmd> set fwd io

# MAC address swapping
testpmd> set fwd mac

# Checksum offload testing
testpmd> set fwd csum
testpmd> csum set ip hw 0
testpmd> csum set tcp hw 0

# Flow generator
testpmd> set fwd flowgen

# Receive only (for debugging)
testpmd> set fwd rxonly

# Transmit only
testpmd> set fwd txonly
```

### 2.4 testpmd Scripting

```bash
#!/bin/bash
# testpmd_flow_test.sh

cat << 'EOF' | sudo dpdk-testpmd -l 0-3 -n 4 \
    --vdev 'net_pcap0,rx_pcap=test.pcap,tx_pcap=out.pcap' \
    --vdev 'net_null1' \
    -- -i --portmask=0x3

# Setup
set fwd io
set verbose 1

# Create flow rules
flow create 0 ingress pattern eth / ipv4 dst is 10.0.0.1 / end actions queue index 0 / end
flow create 0 ingress pattern eth / ipv4 dst is 10.0.0.2 / end actions queue index 1 / end
flow create 0 ingress pattern eth / ipv4 / tcp dst is 80 / end actions count / queue index 2 / end

# Show configured flows
flow list 0

# Start forwarding
start

# Wait for packets to process
sleep 5

# Show statistics
show port stats all
flow query 0 2 count

# Cleanup
stop
flow flush 0
quit
EOF
```

---

## Part 3: Container-Based Testing

### 3.1 DPDK Development Container

```dockerfile
# Dockerfile.dpdk-dev
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DPDK_VERSION=23.11

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    meson \
    ninja-build \
    python3-pyelftools \
    libnuma-dev \
    libpcap-dev \
    libelf-dev \
    pkg-config \
    git \
    wget \
    pciutils \
    iproute2 \
    tcpdump \
    python3-scapy \
    && rm -rf /var/lib/apt/lists/*

# Download and build DPDK
WORKDIR /opt
RUN wget https://fast.dpdk.org/rel/dpdk-${DPDK_VERSION}.tar.xz && \
    tar xf dpdk-${DPDK_VERSION}.tar.xz && \
    cd dpdk-${DPDK_VERSION} && \
    meson setup build && \
    cd build && \
    ninja && \
    ninja install && \
    ldconfig

# Set environment
ENV PKG_CONFIG_PATH=/usr/local/lib/x86_64-linux-gnu/pkgconfig
ENV LD_LIBRARY_PATH=/usr/local/lib/x86_64-linux-gnu

# Create working directory
WORKDIR /app

# Copy application source
COPY . /app/

# Build application
RUN meson setup build && cd build && ninja

CMD ["/bin/bash"]
```

### 3.2 Docker Compose for Multi-Container Testing

```yaml
# docker-compose.yml
version: '3.8'

services:
  dpdk-app:
    build:
      context: .
      dockerfile: Dockerfile.dpdk-dev
    container_name: dpdk_app
    privileged: true
    volumes:
      - /dev/hugepages:/dev/hugepages
      - /sys/bus/pci/devices:/sys/bus/pci/devices
      - /sys/kernel/mm/hugepages:/sys/kernel/mm/hugepages
      - /sys/devices/system/node:/sys/devices/system/node
      - ./pcaps:/app/pcaps
      - ./logs:/app/logs
      - memif_socket:/var/run/memif
    environment:
      - DPDK_ARGS=-l 0-3 -n 4 --vdev net_memif0,role=server,socket=/var/run/memif/memif.sock
    networks:
      dpdk_net:
        ipv4_address: 172.20.0.10
    command: >
      bash -c "
        echo 1024 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
        /app/build/my_app $$DPDK_ARGS
      "

  traffic-generator:
    build:
      context: .
      dockerfile: Dockerfile.dpdk-dev
    container_name: traffic_gen
    privileged: true
    volumes:
      - /dev/hugepages:/dev/hugepages
      - ./pcaps:/app/pcaps
      - memif_socket:/var/run/memif
    depends_on:
      - dpdk-app
    networks:
      dpdk_net:
        ipv4_address: 172.20.0.11
    command: >
      bash -c "
        sleep 5
        dpdk-testpmd -l 4-5 -n 4 \
          --vdev net_memif0,role=client,socket=/var/run/memif/memif.sock \
          -- --txonly --txpkts=64 --stats-period=1
      "

  packet-capture:
    image: nicolaka/netshoot
    container_name: packet_capture
    network_mode: "service:dpdk-app"
    volumes:
      - ./pcaps:/pcaps
    command: tcpdump -i any -w /pcaps/capture.pcap

volumes:
  memif_socket:

networks:
  dpdk_net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24
```

### 3.3 Hugepages Setup for Containers

```bash
#!/bin/bash
# setup_hugepages.sh

# Allocate 2MB hugepages
echo 1024 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

# Mount hugepages (if not already mounted)
if ! mount | grep -q hugetlbfs; then
    sudo mkdir -p /dev/hugepages
    sudo mount -t hugetlbfs nodev /dev/hugepages
fi

# Verify
cat /proc/meminfo | grep Huge
```

### 3.4 Container Testing Script

```bash
#!/bin/bash
# run_container_tests.sh

set -e

# Setup
echo "Setting up hugepages..."
./setup_hugepages.sh

# Build containers
echo "Building containers..."
docker-compose build

# Run tests
echo "Starting test environment..."
docker-compose up -d dpdk-app

# Wait for app to initialize
sleep 10

# Start traffic generator
docker-compose up -d traffic-generator

# Collect logs
echo "Running tests for 30 seconds..."
sleep 30

# Get statistics
docker exec dpdk_app cat /app/logs/stats.txt

# Capture packets
docker-compose up -d packet-capture
sleep 10
docker-compose stop packet-capture

# Analyze results
echo "Analyzing captured packets..."
tcpdump -r ./pcaps/capture.pcap | head -100

# Cleanup
echo "Cleaning up..."
docker-compose down -v

echo "Tests complete!"
```

---

## Part 4: Testing Strategies

### 4.1 Unit Testing with Mocks

```c
// test_packet_processing.c
#include <stdarg.h>
#include <stddef.h>
#include <setjmp.h>
#include <cmocka.h>
#include <rte_mbuf.h>

// Mock mbuf for testing
static struct rte_mbuf *create_test_mbuf(void) {
    static struct rte_mbuf mbuf;
    static uint8_t data[2048];
    
    memset(&mbuf, 0, sizeof(mbuf));
    mbuf.buf_addr = data;
    mbuf.buf_len = sizeof(data);
    mbuf.data_off = 128;
    mbuf.pkt_len = 64;
    mbuf.data_len = 64;
    
    return &mbuf;
}

// Mock Ethernet + IPv4 + TCP packet
static void setup_tcp_packet(struct rte_mbuf *mbuf,
                             uint32_t src_ip, uint32_t dst_ip,
                             uint16_t src_port, uint16_t dst_port) {
    uint8_t *data = rte_pktmbuf_mtod(mbuf, uint8_t *);
    
    // Ethernet header
    struct rte_ether_hdr *eth = (struct rte_ether_hdr *)data;
    eth->ether_type = rte_cpu_to_be_16(RTE_ETHER_TYPE_IPV4);
    
    // IPv4 header
    struct rte_ipv4_hdr *ip = (struct rte_ipv4_hdr *)(eth + 1);
    ip->version_ihl = 0x45;
    ip->total_length = rte_cpu_to_be_16(40);
    ip->next_proto_id = IPPROTO_TCP;
    ip->src_addr = rte_cpu_to_be_32(src_ip);
    ip->dst_addr = rte_cpu_to_be_32(dst_ip);
    
    // TCP header
    struct rte_tcp_hdr *tcp = (struct rte_tcp_hdr *)(ip + 1);
    tcp->src_port = rte_cpu_to_be_16(src_port);
    tcp->dst_port = rte_cpu_to_be_16(dst_port);
    tcp->data_off = 0x50;
    
    mbuf->pkt_len = sizeof(*eth) + sizeof(*ip) + sizeof(*tcp);
    mbuf->data_len = mbuf->pkt_len;
}

// Test: Verify packet parsing
static void test_parse_tcp_packet(void **state) {
    struct rte_mbuf *mbuf = create_test_mbuf();
    setup_tcp_packet(mbuf, 0x0A000001, 0x0A000002, 1234, 80);
    
    // Call your packet parsing function
    struct packet_info info;
    int ret = parse_packet(mbuf, &info);
    
    assert_int_equal(ret, 0);
    assert_int_equal(info.src_ip, 0x0A000001);
    assert_int_equal(info.dst_ip, 0x0A000002);
    assert_int_equal(info.src_port, 1234);
    assert_int_equal(info.dst_port, 80);
    assert_int_equal(info.protocol, IPPROTO_TCP);
}

// Test: Verify flow matching
static void test_flow_match(void **state) {
    struct rte_mbuf *mbuf = create_test_mbuf();
    setup_tcp_packet(mbuf, 0x0A000001, 0xC0A80101, 1234, 80);
    
    // Create flow rule
    struct flow_rule rule = {
        .dst_ip = 0xC0A80101,      // 192.168.1.1
        .dst_port = 80,
        .action = ACTION_FORWARD,
        .fwd_port = 1
    };
    
    // Test matching
    int matched = match_flow(mbuf, &rule);
    assert_true(matched);
}

int main(void) {
    const struct CMUnitTest tests[] = {
        cmocka_unit_test(test_parse_tcp_packet),
        cmocka_unit_test(test_flow_match),
    };
    
    return cmocka_run_group_tests(tests, NULL, NULL);
}
```

### 4.2 Integration Testing with PCAP

```python
#!/usr/bin/env python3
# integration_test.py

import subprocess
import time
from scapy.all import *

def generate_test_traffic(output_file):
    """Generate test PCAP with known traffic patterns."""
    packets = []
    
    # Pattern 1: HTTP traffic (should match rule 1)
    for i in range(10):
        pkt = Ether()/IP(src="10.0.0.1", dst="192.168.1.1")/TCP(dport=80)
        packets.append(pkt)
    
    # Pattern 2: DNS traffic (should match rule 2)
    for i in range(10):
        pkt = Ether()/IP(src="10.0.0.1", dst="8.8.8.8")/UDP(dport=53)
        packets.append(pkt)
    
    # Pattern 3: Unknown traffic (should go to default queue)
    for i in range(10):
        pkt = Ether()/IP(src="10.0.0.1", dst="1.2.3.4")/ICMP()
        packets.append(pkt)
    
    wrpcap(output_file, packets)
    return len(packets)

def run_dpdk_app(input_pcap, output_pcap, duration=10):
    """Run DPDK application with PCAP PMD."""
    cmd = [
        "./build/my_app",
        "-l", "0-3", "-n", "4",
        "--vdev", f"net_pcap0,rx_pcap={input_pcap},tx_pcap={output_pcap}",
        "--", "--duration", str(duration)
    ]
    
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = proc.communicate(timeout=duration + 5)
    
    return proc.returncode, stdout.decode(), stderr.decode()

def analyze_output(output_pcap, expected_count):
    """Analyze output PCAP and verify results."""
    try:
        packets = rdpcap(output_pcap)
    except:
        print("ERROR: Could not read output PCAP")
        return False
    
    # Verify packet count
    if len(packets) != expected_count:
        print(f"ERROR: Expected {expected_count} packets, got {len(packets)}")
        return False
    
    # Verify modifications were applied
    for pkt in packets:
        if TCP in pkt and pkt[TCP].dport == 80:
            # Verify HTTP packets were processed correctly
            if pkt[Ether].dst != "aa:bb:cc:dd:ee:ff":
                print("ERROR: MAC modification not applied to HTTP packet")
                return False
    
    print(f"SUCCESS: All {len(packets)} packets processed correctly")
    return True

def main():
    input_pcap = "/tmp/test_input.pcap"
    output_pcap = "/tmp/test_output.pcap"
    
    print("Generating test traffic...")
    packet_count = generate_test_traffic(input_pcap)
    
    print(f"Running DPDK application with {packet_count} packets...")
    ret, stdout, stderr = run_dpdk_app(input_pcap, output_pcap)
    
    if ret != 0:
        print(f"ERROR: Application failed with code {ret}")
        print(stderr)
        return 1
    
    print("Analyzing output...")
    if not analyze_output(output_pcap, packet_count):
        return 1
    
    print("All tests passed!")
    return 0

if __name__ == "__main__":
    exit(main())
```

### 4.3 Performance Baseline Testing

```bash
#!/bin/bash
# performance_baseline.sh

# Test with null PMD for maximum theoretical throughput
echo "Testing with null PMD (no I/O overhead)..."
sudo dpdk-testpmd -l 0-7 -n 4 \
    --vdev 'net_null0' \
    --vdev 'net_null1' \
    -- --forward-mode=io \
       --stats-period=1 \
       --txpkts=64 \
       --burst=32 \
       --rxq=4 --txq=4 \
       2>&1 | tee null_pmd_results.txt &

PID=$!
sleep 30
kill $PID

# Parse results
echo "Results:"
grep "Tx-pps" null_pmd_results.txt | tail -5

# Test with PCAP PMD (realistic traffic)
echo "Testing with PCAP PMD..."
sudo dpdk-testpmd -l 0-7 -n 4 \
    --vdev 'net_pcap0,rx_pcap=test_traffic.pcap,infinite_rx=1' \
    --vdev 'net_null1' \
    -- --forward-mode=io \
       --stats-period=1 \
       --burst=32 \
       2>&1 | tee pcap_pmd_results.txt &

PID=$!
sleep 30
kill $PID

echo "PCAP Results:"
grep "Rx-pps" pcap_pmd_results.txt | tail -5
```

---

## Part 5: Debugging Techniques

### 5.1 Verbose DPDK Logging

```c
// Enable debug logging in application
#include <rte_log.h>

#define RTE_LOGTYPE_APP RTE_LOGTYPE_USER1

int main(int argc, char **argv) {
    // Set log level
    rte_log_set_global_level(RTE_LOG_DEBUG);
    rte_log_set_level(RTE_LOGTYPE_APP, RTE_LOG_DEBUG);
    
    RTE_LOG(INFO, APP, "Application starting\n");
    RTE_LOG(DEBUG, APP, "Debug message: port=%u queue=%u\n", port_id, queue_id);
    
    return 0;
}
```

```bash
# Run with increased logging
./my_app --log-level=8  # DPDK debug level
```

### 5.2 Packet Inspection

```c
// Dump packet contents for debugging
void dump_packet(struct rte_mbuf *mbuf) {
    printf("=== Packet Dump ===\n");
    printf("pkt_len: %u, data_len: %u\n", mbuf->pkt_len, mbuf->data_len);
    printf("nb_segs: %u, port: %u, queue: %u\n", 
           mbuf->nb_segs, mbuf->port, mbuf->hash.rss);
    
    uint8_t *data = rte_pktmbuf_mtod(mbuf, uint8_t *);
    printf("Data (first 64 bytes):\n");
    for (int i = 0; i < 64 && i < mbuf->data_len; i++) {
        printf("%02x ", data[i]);
        if ((i + 1) % 16 == 0) printf("\n");
    }
    printf("\n");
    
    // Parse headers
    struct rte_ether_hdr *eth = rte_pktmbuf_mtod(mbuf, struct rte_ether_hdr *);
    printf("Ethernet: %02x:%02x:%02x:%02x:%02x:%02x -> %02x:%02x:%02x:%02x:%02x:%02x\n",
           eth->src_addr.addr_bytes[0], eth->src_addr.addr_bytes[1],
           eth->src_addr.addr_bytes[2], eth->src_addr.addr_bytes[3],
           eth->src_addr.addr_bytes[4], eth->src_addr.addr_bytes[5],
           eth->dst_addr.addr_bytes[0], eth->dst_addr.addr_bytes[1],
           eth->dst_addr.addr_bytes[2], eth->dst_addr.addr_bytes[3],
           eth->dst_addr.addr_bytes[4], eth->dst_addr.addr_bytes[5]);
    printf("EtherType: 0x%04x\n", rte_be_to_cpu_16(eth->ether_type));
}
```

### 5.3 Flow Rule Debugging

```bash
# In testpmd, enable flow rule debugging
testpmd> set verbose 1

# Validate rule before creating
testpmd> flow validate 0 ingress pattern eth / ipv4 / end actions queue index 0 / end

# Create with detailed output
testpmd> flow create 0 ingress pattern eth / ipv4 dst is 10.0.0.1 / end actions queue index 1 / end

# Dump flow details
testpmd> flow dump 0 all

# Check flow capabilities
testpmd> show port 0 flow_ctrl
```

---

## Part 6: CI/CD Integration

### 6.1 GitLab CI Pipeline

```yaml
# .gitlab-ci.yml
stages:
  - build
  - test
  - integration

variables:
  DPDK_VERSION: "23.11"

build:
  stage: build
  image: ubuntu:22.04
  script:
    - apt-get update && apt-get install -y build-essential meson ninja-build libnuma-dev libpcap-dev python3-pyelftools
    - meson setup build
    - cd build && ninja
  artifacts:
    paths:
      - build/
    expire_in: 1 hour

unit-tests:
  stage: test
  image: ubuntu:22.04
  dependencies:
    - build
  script:
    - apt-get update && apt-get install -y libcmocka-dev
    - cd build && ninja test
  artifacts:
    reports:
      junit: build/meson-logs/testlog.junit.xml

pcap-tests:
  stage: test
  image: ubuntu:22.04
  dependencies:
    - build
  script:
    - apt-get update && apt-get install -y python3-scapy tcpdump
    - python3 generate_test_pcap.py
    - ./integration_test.py

container-tests:
  stage: integration
  image: docker:latest
  services:
    - docker:dind
  script:
    - docker-compose build
    - docker-compose up -d
    - sleep 30
    - docker-compose logs
    - docker-compose down
  when: manual
```

### 6.2 GitHub Actions

```yaml
# .github/workflows/dpdk-test.yml
name: DPDK Tests

on: [push, pull_request]

jobs:
  build-and-test:
    runs-on: ubuntu-22.04
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Install dependencies
      run: |
        sudo apt-get update
        sudo apt-get install -y \
          build-essential meson ninja-build \
          libnuma-dev libpcap-dev python3-pyelftools \
          python3-scapy libcmocka-dev
    
    - name: Setup hugepages
      run: |
        echo 256 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
        sudo mkdir -p /dev/hugepages
        sudo mount -t hugetlbfs nodev /dev/hugepages || true
    
    - name: Build
      run: |
        meson setup build
        cd build && ninja
    
    - name: Run unit tests
      run: |
        cd build && ninja test
    
    - name: Generate test traffic
      run: |
        python3 scripts/generate_test_pcap.py
    
    - name: Run PCAP tests
      run: |
        sudo ./build/my_app -l 0-1 -n 2 \
          --vdev 'net_pcap0,rx_pcap=test.pcap,tx_pcap=out.pcap' \
          -- --test-mode
```

---

## Summary: Local Testing Checklist

### Before Hardware Deployment

- [ ] Unit tests pass with mocked mbufs
- [ ] PCAP-based integration tests pass
- [ ] Flow rule syntax validated in testpmd
- [ ] Container-based end-to-end tests pass
- [ ] Performance baseline established with null PMD
- [ ] Memory leaks checked (valgrind with DPDK)
- [ ] Error handling paths tested

### What to Test on Hardware

- [ ] Actual flow offloading verification
- [ ] Line-rate performance testing
- [ ] eSwitch and representor functionality
- [ ] DPA/FlexIO integration
- [ ] Multi-port scenarios
- [ ] Hardware counter accuracy

## Quick Reference

| Task | Tool/Method |
|------|-------------|
| Test app logic | Null PMD + unit tests |
| Validate packet parsing | PCAP PMD + Scapy |
| Test flow rules | testpmd flow commands |
| Integration testing | Docker + memif PMD |
| Performance baseline | testpmd txonly/rxonly |
| Debug packets | TAP PMD + tcpdump |
| CI/CD | GitHub Actions / GitLab CI |

## Next Steps

- [Testing Strategies](testing-strategies.md) - Comprehensive testing approaches
- [Debugging Guide](debugging-guide.md) - Troubleshooting techniques
- [Performance Optimization](performance-optimization.md) - Tuning for production
- [Code Examples](code-examples.md) - Complete working examples