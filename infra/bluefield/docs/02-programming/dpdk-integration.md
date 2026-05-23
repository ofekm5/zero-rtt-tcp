# DPDK Integration

## Overview

This document covers DPDK integration patterns for BlueField-3, including queue setup, packet processing loops, and integration with hardware features like DPA and FlexIO.

## RX Queue API

### How Packets Are Received

```c
struct rte_mbuf *pkts[32];
uint16_t nb_rx = rte_eth_rx_burst(port, queue_id, pkts, 32);
```

**What happens**:
1. Hardware DMA writes packets to memory
2. Packet descriptors added to RX queue ring
3. Application polls queue (no interrupts)
4. Descriptors point to packet buffers (mbufs)

### TX Queue API

### How Packets Are Sent

```c
uint16_t nb_tx = rte_eth_tx_burst(port, queue_id, pkts, nb_pkts);
```

**What happens**:
1. Application adds packet descriptors to TX queue
2. Hardware reads descriptors
3. DMA reads packet data from memory
4. Packets transmitted on wire

## Queue Ring Structure

```c
struct rte_ring {
    uint32_t prod_head;    // Producer write position
    uint32_t prod_tail;    // Producer commit position
    uint32_t cons_head;    // Consumer read position
    uint32_t cons_tail;    // Consumer commit position
    
    void *ring[];          // Array of packet descriptors
};
```

## Example 1: Basic DPDK Forwarding

```c
// simple_forward.c - Basic L2 forwarding
#include <rte_eal.h>
#include <rte_ethdev.h>
#include <rte_mbuf.h>

#define RX_RING_SIZE 1024
#define TX_RING_SIZE 1024
#define NUM_MBUFS 8191
#define MBUF_CACHE_SIZE 250
#define BURST_SIZE 32

int main(int argc, char **argv) {
    struct rte_mempool *mbuf_pool;
    uint16_t port = 0;
    
    // Initialize EAL
    rte_eal_init(argc, argv);
    
    // Create mempool
    mbuf_pool = rte_pktmbuf_pool_create("MBUF_POOL", NUM_MBUFS,
        MBUF_CACHE_SIZE, 0, RTE_MBUF_DEFAULT_BUF_SIZE, rte_socket_id());
    
    // Configure port
    struct rte_eth_conf port_conf = {0};
    rte_eth_dev_configure(port, 1, 1, &port_conf);
    rte_eth_rx_queue_setup(port, 0, RX_RING_SIZE,
        rte_eth_dev_socket_id(port), NULL, mbuf_pool);
    rte_eth_tx_queue_setup(port, 0, TX_RING_SIZE,
        rte_eth_dev_socket_id(port), NULL);
    rte_eth_dev_start(port);
    
    // Main loop
    while (1) {
        struct rte_mbuf *bufs[BURST_SIZE];
        uint16_t nb_rx = rte_eth_rx_burst(port, 0, bufs, BURST_SIZE);
        
        if (nb_rx > 0) {
            uint16_t nb_tx = rte_eth_tx_burst(port, 0, bufs, nb_rx);
            
            // Free unsent packets
            for (uint16_t i = nb_tx; i < nb_rx; i++) {
                rte_pktmbuf_free(bufs[i]);
            }
        }
    }
    
    return 0;
}
```

## Complete Queue Setup Example

```c
#define NUM_RX_QUEUES 4
#define NUM_TX_QUEUES 4
#define RX_RING_SIZE 1024
#define TX_RING_SIZE 1024

int setup_port(uint16_t port_id) {
    struct rte_eth_conf port_conf = {
        .rxmode = {
            .mq_mode = RTE_ETH_MQ_RX_RSS,  // Enable RSS
        },
        .rx_adv_conf = {
            .rss_conf = {
                .rss_key = NULL,
                .rss_hf = RTE_ETH_RSS_IP | RTE_ETH_RSS_TCP,
            },
        },
    };
    
    // Configure port
    rte_eth_dev_configure(port_id, NUM_RX_QUEUES, NUM_TX_QUEUES, &port_conf);
    
    // Setup RX queues
    for (int q = 0; q < NUM_RX_QUEUES; q++) {
        rte_eth_rx_queue_setup(port_id, q, RX_RING_SIZE,
                               rte_eth_dev_socket_id(port_id),
                               NULL, pktmbuf_pool);
    }
    
    // Setup TX queues
    for (int q = 0; q < NUM_TX_QUEUES; q++) {
        rte_eth_tx_queue_setup(port_id, q, TX_RING_SIZE,
                               rte_eth_dev_socket_id(port_id),
                               NULL);
    }
    
    // Start port
    rte_eth_dev_start(port_id);
    
    return 0;
}
```

## FlexIO Integration with rte_flow

FlexIO allows integration of custom DPA cores with DPDK rte_flow. Here's the integration sequence:

### Integration Steps

```
1. start DPDK with no ports
2. initialize the FLEXIO app
3. flexio_rq_get_wq_num to get the RQN
4. flexio_rq_get_tir + mlx5dv_devx_obj_destroy to destroy the TIR
5. rte_eal_hotplug_add to add the port with cmd_fd and pd_handle from the PD created in the flexio APP
6. rte_pmd_mlx5_external_rx_queue_id_map to add the flexio queues using the RQN retrieved in (1)
7. use rte_flow with the external queues
```

### What This Enables

- Custom DPA processing integrated with hardware flow rules
- External queues managed by FlexIO but accessible via rte_flow
- High-performance custom packet processing with standard DPDK API

## Multi-Queue RSS Configuration

```c
// Configure RSS
struct rte_eth_rss_conf rss_conf = {
    .rss_key = NULL,  // Use default key
    .rss_key_len = 40,
    .rss_hf = RTE_ETH_RSS_IP | RTE_ETH_RSS_TCP | RTE_ETH_RSS_UDP,
};

rte_eth_dev_configure(port_id, nb_rx_queues, nb_tx_queues, &port_conf);
```

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

## Per-Core Processing Pattern

```c
int lcore_main(void *arg) {
    unsigned lcore_id = rte_lcore_id();
    uint16_t queue_id = lcore_id;  // 1:1 mapping
    
    while (1) {
        struct rte_mbuf *pkts[BURST_SIZE];
        uint16_t nb_rx = rte_eth_rx_burst(port_id, queue_id, 
                                          pkts, BURST_SIZE);
        
        // Process packets on this core only
        for (int i = 0; i < nb_rx; i++) {
            process_packet(pkts[i]);
        }
        
        // Send packets
        rte_eth_tx_burst(port_id, queue_id, pkts, nb_rx);
    }
}
```

## Hardware Offload with DPDK

### Enable Checksum Offload

```c
// Option 1: Manual calculation (software)
ip->hdr_checksum = 0;
ip->hdr_checksum = rte_ipv4_cksum(ip);

// Option 2: Hardware offload
pkt->ol_flags |= RTE_MBUF_F_TX_IP_CKSUM | RTE_MBUF_F_TX_TCP_CKSUM;
pkt->l2_len = sizeof(struct rte_ether_hdr);
pkt->l3_len = sizeof(struct rte_ipv4_hdr);
// Hardware calculates on TX
```

### RSS Flow Director

```c
// Send specific traffic to specific queue
struct rte_flow_item pattern[] = {
    {
        .type = RTE_FLOW_ITEM_TYPE_TCP,
        .spec = &(struct rte_flow_item_tcp){
            .hdr.dst_port = rte_cpu_to_be_16(80)
        }
    },
    { .type = RTE_FLOW_ITEM_TYPE_END }
};

struct rte_flow_action actions[] = {
    {
        .type = RTE_FLOW_ACTION_TYPE_QUEUE,
        .conf = &(struct rte_flow_action_queue){ .index = 3 }
    },
    { .type = RTE_FLOW_ACTION_TYPE_END }
};

// All HTTP traffic → Queue 3
rte_flow_create(port_id, &attr, pattern, actions, &error);
```

## Key Takeaways

1. **rte_eth_rx_burst / rte_eth_tx_burst** are the core DPDK packet I/O APIs
2. **Queues are ring buffers** in memory, not communication channels
3. **RSS distributes packets** across queues automatically
4. **1 queue per core** is optimal for lock-free operation
5. **FlexIO integration** allows custom DPA cores with rte_flow
6. **Hardware offload** possible for checksums and other operations
7. **Batch processing** critical for performance

## Next Steps
- See [DPA Programming](dpa-programming.md) for custom packet processing
- Read [../01-architecture/queues-ports-sfs.md](../01-architecture/queues-ports-sfs.md) for queue concepts
- Check [../04-development/performance-tuning.md](../04-development/performance-tuning.md) for optimization
- Review [../04-development/code-examples.md](../04-development/code-examples.md) for more examples
