# Code Examples Repository

## Overview

This document contains practical code examples for BlueField-3 development. Examples 1-3 have been moved to their respective programming guides.

## Example 4: Test Script (pktgen)

```bash
#!/bin/bash
# pktgen_test.sh - Automated packet generation

IF="ens16f0np0"
DST_MAC="02:25:f2:8d:a2:4c"
PKT_SIZE="512"
PKT_COUNT="1000000"

modprobe pktgen

pg_write() {
    echo "$2" > "$1"
}

pg_write /proc/net/pktgen/kpktgend_0 "rem_device_all"
pg_write /proc/net/pktgen/kpktgend_0 "add_device $IF"

PGDEV="/proc/net/pktgen/$IF"

pg_write "$PGDEV" "clone_skb 0"
pg_write "$PGDEV" "pkt_size $PKT_SIZE"
pg_write "$PGDEV" "count $PKT_COUNT"
pg_write "$PGDEV" "dst_mac $DST_MAC"

echo "Starting test..."
pg_write /proc/net/pktgen/pgctrl "start"

echo "Results:"
cat "$PGDEV"
```

## Example 5: Performance Benchmark

```c
// benchmark.c - Throughput test
#include <rte_cycles.h>
#include <time.h>

void benchmark_throughput(uint16_t port) {
    struct timespec start, end;
    uint64_t total_packets = 0, total_bytes = 0;

    clock_gettime(CLOCK_MONOTONIC, &start);

    for (int iter = 0; iter < 1000; iter++) {
        struct rte_mbuf *pkts[32];
        uint16_t nb_rx = rte_eth_rx_burst(port, 0, pkts, 32);

        for (int i = 0; i < nb_rx; i++) {
            total_bytes += rte_pktmbuf_pkt_len(pkts[i]);
            rte_pktmbuf_free(pkts[i]);
        }

        total_packets += nb_rx;
    }

    clock_gettime(CLOCK_MONOTONIC, &end);
    double elapsed = (end.tv_sec - start.tv_sec) +
                    (end.tv_nsec - start.tv_nsec) / 1e9;

    double gbps = (total_bytes * 8) / (elapsed * 1e9);
    double mpps = total_packets / (elapsed * 1e6);

    printf("Throughput: %.2f Gbps, %.2f Mpps\n", gbps, mpps);
}
```

## Building and Running

### Compile DPDK Application
```bash
gcc -o simple_forward simple_forward.c \
    $(pkg-config --cflags --libs libdpdk)

# Run with hugepages
sudo ./simple_forward -l 0-3 -a 0000:03:00.0
```

### Compile DPA Program
```bash
dpacc -c dpa_tcp_mod.c -o dpa_tcp_mod.o
dpacc dpa_tcp_mod.o -o dpa_tcp_mod.dpa
```

## Example Repository Structure

```
examples/
├── basic/
│   ├── l2_forward.c
│   ├── l3_forward.c
│   └── vlan_filter.c
├── eswitch/
│   ├── vm_networking.c
│   └── tunnel_encap.c
├── dpa/
│   ├── tcp_proxy.c
│   ├── synack_gen.c
│   └── custom_header.c
└── testing/
    ├── pktgen_test.sh
    ├── iperf_test.sh
    └── scapy_test.py
```

All examples available in the DOCA SDK samples directory.

## Additional Examples by Category

### Basic DPDK Examples
See [../02-programming/dpdk-integration.md](../02-programming/dpdk-integration.md) for:
- Example 1: Basic DPDK Forwarding

### eSwitch Examples
See [../02-programming/doca-flow-api.md](../02-programming/doca-flow-api.md) for:
- Example 2: eSwitch Rule Installation (VM-to-VM forwarding)

### DPA Examples
See [../02-programming/packet-modification.md](../02-programming/packet-modification.md) for:
- Example 3: DPA TCP Modifier (sequence number modification)
- Packet generation examples

## Key Takeaways

1. **pktgen** for automated testing
2. **Benchmarking** measures real throughput
3. **Compile separately**: DPDK with gcc, DPA with dpacc
4. **Examples organized** by complexity and use case
5. **Full examples** available in DOCA SDK

## Next Steps
- See [../02-programming/](../02-programming/) for detailed programming guides
- Read [testing-strategies.md](testing-strategies.md) for comprehensive testing approaches
- Check [debugging-guide.md](debugging-guide.md) for troubleshooting
