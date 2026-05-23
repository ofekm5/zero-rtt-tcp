# Performance Optimization

## Performance Targets

| Component | Target Performance |
|-----------|-------------------|
| NIC Flow Engine | 400 Gbps, <1 μs |
| DPA | 50-100 Gbps, 5-20 μs |
| ARM DPDK | 10-20 Gbps/core, 50-200 μs |

## Hardware Offload Checklist

### ✅ Verify Hardware Offload

```bash
# Check if rules are offloaded
ovs-appctl dpctl/dump-flows type=offloaded

# Check hardware counters (should increment)
ethtool -S p0 | grep offload

# Verify flow table usage
mlxdump -d <device> fsdump --type FT
```

### Common Offload Issues

```
❌ Rule too complex → Simplify actions
❌ Table full → Age out old flows
❌ Unsupported action → Use DPA instead
❌ Feature not enabled → Check switchdev mode
```

## DPDK Optimization

### 1. CPU Core Pinning

```bash
# Pin DPDK to specific cores
./dpdk-app -l 0-3 -a 0000:03:00.0

# Set CPU affinity
taskset -c 0-3 ./dpdk-app

# Isolate cores (add to kernel boot params)
isolcpus=0-3 nohz_full=0-3
```

### 2. NUMA Awareness

```c
// Allocate memory on same NUMA node as NIC
int socket_id = rte_eth_dev_socket_id(port_id);
pool = rte_pktmbuf_pool_create("pool", NUM, CACHE, 0, SIZE, socket_id);

// Pin thread to NUMA node
cpu_set_t cpuset;
CPU_ZERO(&cpuset);
CPU_SET(core_id, &cpuset);
pthread_setaffinity_np(pthread_self(), sizeof(cpuset), &cpuset);
```

### 3. Queue Configuration

```c
// Optimal queue sizes (power of 2)
#define RX_RING_SIZE 2048
#define TX_RING_SIZE 2048

// One queue per core
num_queues = rte_lcore_count();

// Enable RSS for multi-queue
struct rte_eth_conf port_conf = {
    .rxmode = {
        .mq_mode = RTE_ETH_MQ_RX_RSS,
    },
    .rx_adv_conf = {
        .rss_conf = {
            .rss_hf = RTE_ETH_RSS_IP | RTE_ETH_RSS_TCP | RTE_ETH_RSS_UDP,
        },
    },
};
```

### 4. Batch Processing

```c
// ✅ GOOD: Process in bursts
struct rte_mbuf *pkts[BURST_SIZE];
uint16_t nb_rx = rte_eth_rx_burst(port, queue, pkts, BURST_SIZE);

for (int i = 0; i < nb_rx; i++) {
    process(pkts[i]);
}

rte_eth_tx_burst(port, queue, pkts, nb_rx);

// ❌ BAD: One packet at a time
while (1) {
    rte_eth_rx_burst(port, queue, &pkt, 1);
    process(pkt);
    rte_eth_tx_burst(port, queue, &pkt, 1);
}
```

## DPA Optimization

### 1. Minimize Branching

```c
// ❌ BAD: Many branches
if (proto == TCP) {
    if (port == 80) { handle_http(); }
    else if (port == 443) { handle_https(); }
} else if (proto == UDP) { ... }

// ✅ GOOD: Lookup table
handler_t handlers[256][65536];
handler_t h = handlers[proto][port];
if (h) h(pkt);
```

### 2. Use Packet Templates

```c
// Pre-allocate common packet structures
__dpa_global__ struct rte_mbuf *template_syn;
__dpa_global__ struct rte_mbuf *template_ack;

// Clone instead of building from scratch
struct rte_mbuf *pkt = rte_pktmbuf_clone(template_syn, pool);
```

### 3. Batch DPA Operations

```c
// Process multiple packets per iteration
#define DPA_BURST 32

while (1) {
    struct rte_mbuf *pkts[DPA_BURST];
    uint16_t nb = dpa_queue_dequeue(RX_Q, pkts, DPA_BURST);
    
    for (int i = 0; i < nb; i++) {
        process(pkts[i]);
    }
    
    dpa_queue_enqueue(TX_Q, pkts, nb);
}
```

## Flow Engine Optimization

### 1. Use Priority Wisely

```c
// High priority (0) for specific rules
attr.priority = 0;
rte_flow_create(port, &attr, specific_pattern, actions, &error);

// Low priority (100) for catch-all
attr.priority = 100;
rte_flow_create(port, &attr, generic_pattern, actions, &error);
```

### 2. Age Out Inactive Flows

```c
// Enable flow aging
struct rte_flow_action_age age = {
    .timeout = 60,  // Seconds
};

struct rte_flow_action actions[] = {
    { .type = RTE_FLOW_ACTION_TYPE_AGE, .conf = &age },
    // ... other actions
};

// Periodically clean up aged flows
rte_flow_get_aged_flows(port, contexts, nb_contexts, &error);
```

### 3. Use Hardware Counters

```c
// Add counter to track usage
struct rte_flow_action actions[] = {
    { .type = RTE_FLOW_ACTION_TYPE_COUNT },
    // ... other actions
};

// Query periodically
struct rte_flow_query_count count;
rte_flow_query(port, flow, &count, &error);

if (count.hits == 0) {
    // Remove unused flow
    rte_flow_destroy(port, flow, &error);
}
```

## Memory Optimization

### 1. Hugepages

```bash
# Configure hugepages (add to /etc/sysctl.conf)
vm.nr_hugepages = 1024

# Or at runtime
echo 1024 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

# Mount hugepages
mkdir /mnt/huge
mount -t hugetlbfs nodev /mnt/huge
```

### 2. Mempool Sizing

```c
// Size = (num_ports × num_queues × queue_size) × 2
#define NUM_MBUFS ((NUM_PORTS * NUM_QUEUES * QUEUE_SIZE) * 2)

pool = rte_pktmbuf_pool_create(
    "mbuf_pool",
    NUM_MBUFS,
    MBUF_CACHE_SIZE,  // Per-core cache (256 typical)
    0,
    RTE_MBUF_DEFAULT_BUF_SIZE,
    socket_id
);
```

## Monitoring Performance

### Key Metrics

```bash
# Packet rate
ethtool -S p0 | grep -E "rx_packets|tx_packets"

# Drop rate
ethtool -S p0 | grep drop

# CPU utilization
mpstat -P ALL 1

# Hardware offload statistics
ovs-appctl dpctl/dump-flows type=offloaded | wc -l
```

### Bottleneck Identification

```
High packet drops?
    → Increase queue sizes
    → Add more cores
    → Offload to hardware

High CPU usage?
    → Enable hardware offload
    → Optimize packet processing
    → Use batching

Low throughput?
    → Check RSS configuration
    → Verify NUMA placement
    → Enable jumbo frames
```

## Quick Wins

1. **Enable hardware offload** (10-20x improvement)
2. **Use hugepages** (10-20% improvement)
3. **Pin cores** (5-10% improvement)
4. **Batch processing** (2-5x improvement)
5. **NUMA-aware allocation** (10-30% improvement)

## Key Takeaways

- **Hardware offload first** - biggest performance gain
- **Batch everything** - amortize overhead
- **Pin to cores** - avoid context switches
- **Use NUMA correctly** - avoid cross-socket memory access
- **Monitor continuously** - track drops and offload status
