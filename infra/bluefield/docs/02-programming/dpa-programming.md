# DPA Programming Guide

> **⚠️ IMPORTANT NOTE**: The code examples in this document use DPA-specific function names (e.g., `doca_dpa_*`, `dpa_queue_*`, `dpa_printf`) that may not reflect the current DOCA API. These examples are illustrative and may use deprecated or placeholder function names. Always refer to the official NVIDIA DOCA SDK documentation and headers for the current API. The concepts and patterns shown here remain valid, but actual function signatures may differ.

## What is DPA?

### Definition

**DPA (Data Path Accelerator)**: Programmable hardware cores on BlueField-3 for custom packet processing.

```
Type: Programmable hardware (NOT software, NOT ARM cores)
Architecture: SIMT (Single Instruction Multiple Threads) like GPU
Programming: C language via DPACC compiler
Performance: 10-100 Gbps (hardware accelerated, but not line-rate)
```

### DPA vs Other Options

| Component | Type | Performance | Flexibility | Programming |
|-----------|------|-------------|-------------|-------------|
| **NIC Flow Engine** | Fixed ASIC | 400 Gbps | Low | rte_flow API |
| **DPA** | Programmable HW | 50-100 Gbps | High | C (DPACC) |
| **ARM Cores** | CPU | 10-20 Gbps | Highest | Any language |

## When to Use DPA

### ✅ Good Use Cases

```
✅ Custom packet field modifications (TCP seq/ack, custom headers)
✅ Packet generation from scratch
✅ Stateful processing (connection tracking)
✅ Complex algorithms (crypto, compression)
✅ Dynamic flow rule installation
✅ Operations not supported by flow engine
```

### ❌ Bad Use Cases

```
❌ Simple forwarding (use flow engine instead)
❌ Standard NAT/VXLAN (use flow engine)
❌ When line-rate 400 Gbps required (DPA can't achieve this)
❌ Complex control plane logic (use ARM)
```

## DPA Architecture

### Hardware Structure

```
┌────────────────────────────────────────┐
│          DPA Subsystem                 │
│                                        │
│  ┌──────────┐  ┌──────────┐          │
│  │ DPA Core │  │ DPA Core │  ...     │
│  │  Thread  │  │  Thread  │          │
│  │  Pool    │  │  Pool    │          │
│  └──────────┘  └──────────┘          │
│                                        │
│  ┌──────────────────────────┐        │
│  │  Shared DPA Memory       │        │
│  │  • Global variables      │        │
│  │  • Connection tables     │        │
│  │  • Statistics            │        │
│  └──────────────────────────┘        │
│                                        │
│  ┌──────────────────────────┐        │
│  │  DPA Queues              │        │
│  │  • Input from NIC        │        │
│  │  • Output to NIC         │        │
│  └──────────────────────────┘        │
└────────────────────────────────────────┘
```

### Thread Model

```c
// DPA threads are SIMT (like CUDA)
// Many threads execute same code on different data

__dpa_global__ void packet_processor(void) {
    // Each thread processes different packets
    int thread_id = dpa_thread_id();
    
    while (1) {
        struct rte_mbuf *pkt = dpa_dequeue(input_queue);
        
        // Process packet
        process_packet(pkt);
        
        // Send to output
        dpa_enqueue(output_queue, pkt);
    }
}
```

## DPA Programming Model

### Basic Structure

```c
// dpa_app.c
#include <doca_dpa.h>
#include <rte_mbuf.h>

// Global DPA memory (shared across threads)
__dpa_global__ struct {
    uint64_t packet_count;
    uint64_t byte_count;
} stats;

// DPA kernel (runs on DPA cores)
__dpa_global__ void packet_handler(void) {
    struct rte_mbuf *pkts[BURST_SIZE];
    
    while (1) {
        // Receive packets from NIC
        uint16_t nb_pkts = dpa_queue_dequeue(RX_QUEUE, pkts, BURST_SIZE);
        
        for (int i = 0; i < nb_pkts; i++) {
            // Access packet data
            uint8_t *data = rte_pktmbuf_mtod(pkts[i], uint8_t *);
            
            // Modify packet
            modify_packet(data, pkts[i]->pkt_len);
            
            // Update stats
            __atomic_add_fetch(&stats.packet_count, 1, __ATOMIC_RELAXED);
            __atomic_add_fetch(&stats.byte_count, pkts[i]->pkt_len, 
                             __ATOMIC_RELAXED);
        }
        
        // Send back to NIC
        dpa_queue_enqueue(TX_QUEUE, pkts, nb_pkts);
    }
}

// Host-side initialization
int main(int argc, char **argv) {
    // Initialize DOCA DPA
    struct doca_dpa *dpa_ctx;
    doca_dpa_create(&dpa_ctx);
    
    // Load DPA program
    doca_dpa_load_program(dpa_ctx, "dpa_app.dpa");
    
    // Launch DPA threads
    doca_dpa_launch_threads(dpa_ctx, packet_handler, NUM_THREADS);
    
    // Monitor from host
    while (1) {
        sleep(1);
        uint64_t pkts, bytes;
        doca_dpa_read_memory(dpa_ctx, &stats, &pkts, sizeof(pkts));
        printf("Packets: %lu\n", pkts);
    }
    
    return 0;
}
```

### Compilation

```bash
# Compile DPA code
dpacc -c dpa_app.c -o dpa_app.o

# Link into DPA binary
dpacc dpa_app.o -o dpa_app.dpa

# Compile host code
gcc host_app.c -o host_app -ldoca_dpa -lrte_eal -lrte_mbuf

# Run
./host_app
```

## Use Case: TCP Sequence Number Modification

### Problem Statement
Modify TCP sequence and acknowledgment numbers for specific IP addresses at high rate.

**Why DPA?** NIC flow engine cannot modify arbitrary TCP fields.

### Solution Architecture

```
Packet Flow:
1. NIC Flow Engine filters specific IP → Send to DPA Queue
2. DPA modifies TCP seq/ack numbers
3. DPA sends back to NIC
4. NIC forwards to destination
```

### Implementation

```c
// TCP seq/ack modifier on DPA

#include <doca_dpa.h>
#include <rte_mbuf.h>
#include <rte_tcp.h>
#include <rte_ip.h>

// Configuration (set by host)
__dpa_global__ struct {
    uint32_t target_ip;       // IP to match
    int32_t seq_offset;       // Add to seq_num
    int32_t ack_offset;       // Subtract from ack_num
} config;

// Statistics
__dpa_global__ struct {
    uint64_t packets_processed;
    uint64_t packets_modified;
} stats;

// Helper: Get TCP header from packet
static inline struct rte_tcp_hdr *get_tcp_hdr(struct rte_mbuf *pkt) {
    struct rte_ether_hdr *eth = rte_pktmbuf_mtod(pkt, struct rte_ether_hdr *);
    struct rte_ipv4_hdr *ip = (struct rte_ipv4_hdr *)(eth + 1);
    struct rte_tcp_hdr *tcp = (struct rte_tcp_hdr *)(ip + 1);
    return tcp;
}

// Helper: Recalculate TCP checksum
static inline void update_tcp_checksum(struct rte_mbuf *pkt) {
    struct rte_ether_hdr *eth = rte_pktmbuf_mtod(pkt, struct rte_ether_hdr *);
    struct rte_ipv4_hdr *ip = (struct rte_ipv4_hdr *)(eth + 1);
    struct rte_tcp_hdr *tcp = (struct rte_tcp_hdr *)(ip + 1);
    
    // Zero out old checksum
    tcp->cksum = 0;
    
    // Calculate new checksum
    uint32_t tcp_len = rte_be_to_cpu_16(ip->total_length) - 
                      ((ip->version_ihl & 0x0F) * 4);
    tcp->cksum = rte_ipv4_udptcp_cksum(ip, tcp);
}

// Main DPA kernel
__dpa_global__ void tcp_seq_ack_modifier(void) {
    struct rte_mbuf *pkts[BURST_SIZE];
    
    while (1) {
        // Receive packets from flow engine
        uint16_t nb_rx = dpa_queue_dequeue(DPA_RX_QUEUE, pkts, BURST_SIZE);
        
        for (int i = 0; i < nb_rx; i++) {
            __atomic_add_fetch(&stats.packets_processed, 1, __ATOMIC_RELAXED);
            
            // Get headers
            struct rte_ether_hdr *eth = rte_pktmbuf_mtod(pkts[i], 
                                                         struct rte_ether_hdr *);
            struct rte_ipv4_hdr *ip = (struct rte_ipv4_hdr *)(eth + 1);
            
            // Check if target IP (already filtered by flow engine, but double-check)
            if (ip->src_addr == config.target_ip) {
                struct rte_tcp_hdr *tcp = (struct rte_tcp_hdr *)(ip + 1);
                
                // Modify sequence number
                uint32_t old_seq = rte_be_to_cpu_32(tcp->sent_seq);
                uint32_t new_seq = old_seq + config.seq_offset;
                tcp->sent_seq = rte_cpu_to_be_32(new_seq);
                
                // Modify acknowledgment number
                uint32_t old_ack = rte_be_to_cpu_32(tcp->recv_ack);
                uint32_t new_ack = old_ack - config.ack_offset;
                tcp->recv_ack = rte_cpu_to_be_32(new_ack);
                
                // Recalculate checksum
                update_tcp_checksum(pkts[i]);
                
                __atomic_add_fetch(&stats.packets_modified, 1, __ATOMIC_RELAXED);
            }
        }
        
        // Send back to NIC for forwarding
        dpa_queue_enqueue(DPA_TX_QUEUE, pkts, nb_rx);
    }
}
```

### Host-Side Setup

```c
// host_app.c
#include <doca_dpa.h>
#include <rte_flow.h>

int main(int argc, char **argv) {
    // Initialize DPDK
    rte_eal_init(argc, argv);
    
    // Initialize DPA
    struct doca_dpa *dpa;
    doca_dpa_create(&dpa);
    doca_dpa_load_program(dpa, "tcp_modifier.dpa");
    
    // Configure DPA
    struct dpa_config cfg = {
        .target_ip = IPv4(10, 0, 0, 1),
        .seq_offset = 1000,
        .ack_offset = 500,
    };
    doca_dpa_write_memory(dpa, &config, &cfg, sizeof(cfg));
    
    // Setup flow rule: Filter TCP from target IP → DPA
    struct rte_flow_item pattern[] = {
        {
            .type = RTE_FLOW_ITEM_TYPE_IPV4,
            .spec = &(struct rte_flow_item_ipv4){
                .hdr.src_addr = rte_cpu_to_be_32(IPv4(10,0,0,1))
            }
        },
        { .type = RTE_FLOW_ITEM_TYPE_TCP },
        { .type = RTE_FLOW_ITEM_TYPE_END }
    };
    
    struct rte_flow_action actions[] = {
        {
            .type = RTE_FLOW_ACTION_TYPE_QUEUE,
            .conf = &(struct rte_flow_action_queue){ .index = DPA_QUEUE }
        },
        { .type = RTE_FLOW_ACTION_TYPE_END }
    };
    
    rte_flow_create(port_id, &attr, pattern, actions, &error);
    
    // Launch DPA threads
    doca_dpa_launch_threads(dpa, tcp_seq_ack_modifier, 4);
    
    // Monitor statistics
    while (1) {
        sleep(1);
        struct dpa_stats s;
        doca_dpa_read_memory(dpa, &stats, &s, sizeof(s));
        printf("Processed: %lu, Modified: %lu\n", 
               s.packets_processed, s.packets_modified);
    }
    
    return 0;
}
```

## Use Case: Packet Generation (SYN-ACK Proxy)

### Problem Statement
Generate SYN-ACK responses for incoming SYN packets at high rate.

**Why DPA?** NIC flow engine cannot generate packets.

### Implementation

```c
// SYN-ACK generator on DPA

__dpa_global__ uint32_t isn_seed = 0x12345678;  // Initial Sequence Number seed

// Generate ISN (simple version)
static inline uint32_t generate_isn(uint32_t src_ip, uint16_t src_port) {
    return (src_ip ^ src_port ^ isn_seed) + rte_get_tsc_cycles();
}

// Build SYN-ACK packet
static inline struct rte_mbuf *build_synack(struct rte_mbuf *syn_pkt) {
    // Allocate new packet buffer
    struct rte_mbuf *synack = dpa_pktmbuf_alloc(pktmbuf_pool);
    if (!synack) return NULL;
    
    // Parse SYN packet
    struct rte_ether_hdr *syn_eth = rte_pktmbuf_mtod(syn_pkt, 
                                                      struct rte_ether_hdr *);
    struct rte_ipv4_hdr *syn_ip = (struct rte_ipv4_hdr *)(syn_eth + 1);
    struct rte_tcp_hdr *syn_tcp = (struct rte_tcp_hdr *)(syn_ip + 1);
    
    // Build SYN-ACK headers
    struct rte_ether_hdr *ack_eth = rte_pktmbuf_mtod(synack, 
                                                      struct rte_ether_hdr *);
    struct rte_ipv4_hdr *ack_ip = (struct rte_ipv4_hdr *)(ack_eth + 1);
    struct rte_tcp_hdr *ack_tcp = (struct rte_tcp_hdr *)(ack_ip + 1);
    
    // Ethernet: Swap MACs
    rte_ether_addr_copy(&syn_eth->src_addr, &ack_eth->dst_addr);
    rte_ether_addr_copy(&syn_eth->dst_addr, &ack_eth->src_addr);
    ack_eth->ether_type = syn_eth->ether_type;
    
    // IPv4: Swap IPs
    ack_ip->src_addr = syn_ip->dst_addr;
    ack_ip->dst_addr = syn_ip->src_addr;
    ack_ip->version_ihl = 0x45;  // IPv4, 20 bytes
    ack_ip->total_length = rte_cpu_to_be_16(40);  // IP + TCP headers only
    ack_ip->time_to_live = 64;
    ack_ip->next_proto_id = IPPROTO_TCP;
    
    // TCP: Build SYN-ACK
    ack_tcp->src_port = syn_tcp->dst_port;  // Swap ports
    ack_tcp->dst_port = syn_tcp->src_port;
    ack_tcp->sent_seq = rte_cpu_to_be_32(
        generate_isn(syn_ip->src_addr, syn_tcp->src_port)
    );
    ack_tcp->recv_ack = rte_cpu_to_be_32(
        rte_be_to_cpu_32(syn_tcp->sent_seq) + 1  // ACK = SYN seq + 1
    );
    ack_tcp->data_off = 0x50;  // 20 bytes, no options
    ack_tcp->tcp_flags = RTE_TCP_SYN_FLAG | RTE_TCP_ACK_FLAG;
    ack_tcp->rx_win = rte_cpu_to_be_16(65535);
    
    // Calculate checksums
    ack_ip->hdr_checksum = 0;
    ack_ip->hdr_checksum = rte_ipv4_cksum(ack_ip);
    
    ack_tcp->cksum = 0;
    ack_tcp->cksum = rte_ipv4_udptcp_cksum(ack_ip, ack_tcp);
    
    // Set packet length
    synack->pkt_len = synack->data_len = 54;  // Eth + IP + TCP
    
    return synack;
}

// Main DPA kernel
__dpa_global__ void syn_proxy(void) {
    struct rte_mbuf *syn_pkts[BURST_SIZE];
    struct rte_mbuf *synack_pkts[BURST_SIZE];
    
    while (1) {
        // Receive SYN packets
        uint16_t nb_rx = dpa_queue_dequeue(SYN_QUEUE, syn_pkts, BURST_SIZE);
        
        uint16_t nb_synack = 0;
        for (int i = 0; i < nb_rx; i++) {
            // Generate SYN-ACK
            synack_pkts[nb_synack] = build_synack(syn_pkts[i]);
            
            if (synack_pkts[nb_synack]) {
                nb_synack++;
            }
            
            // Free original SYN
            rte_pktmbuf_free(syn_pkts[i]);
        }
        
        // Send SYN-ACKs
        if (nb_synack > 0) {
            dpa_queue_enqueue(SYNACK_TX_QUEUE, synack_pkts, nb_synack);
        }
    }
}
```

## Memory Management

### DPA Memory Types

```c
// Global memory (shared across all threads)
__dpa_global__ uint64_t global_counter;

// Shared memory (explicit allocation)
__dpa_shared__ uint8_t shared_buffer[1024];

// Local memory (per-thread)
void my_function(void) {
    uint32_t local_var;  // On stack, per-thread
}
```

### Accessing Host Memory

```c
// Host-side
uint64_t *host_mem = malloc(sizeof(uint64_t));
doca_dpa_map_memory(dpa, host_mem, sizeof(uint64_t), &dpa_handle);

// DPA-side
__dpa_global__ void kernel(void) {
    uint64_t *ptr = dpa_get_ptr(dpa_handle);
    *ptr = 12345;  // Write to host memory
}
```

## Synchronization

### Atomic Operations

```c
__dpa_global__ uint64_t shared_counter;

__dpa_global__ void increment_counter(void) {
    // Atomic increment
    __atomic_add_fetch(&shared_counter, 1, __ATOMIC_RELAXED);
    
    // Atomic compare-and-swap
    uint64_t old = 10;
    __atomic_compare_exchange_n(&shared_counter, &old, 20, 
                                 false, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED);
}
```

### Locks (Use Sparingly)

```c
__dpa_global__ dpa_spinlock_t lock;

__dpa_global__ void critical_section(void) {
    dpa_spin_lock(&lock);
    
    // Critical section
    modify_shared_data();
    
    dpa_spin_unlock(&lock);
}
```

## Performance Optimization

### Batching

```c
// ❌ BAD: Process one packet at a time
while (1) {
    struct rte_mbuf *pkt;
    dpa_queue_dequeue(RX_Q, &pkt, 1);
    process(pkt);
    dpa_queue_enqueue(TX_Q, &pkt, 1);
}

// ✅ GOOD: Process in bursts
while (1) {
    struct rte_mbuf *pkts[32];
    uint16_t nb = dpa_queue_dequeue(RX_Q, pkts, 32);
    for (int i = 0; i < nb; i++) {
        process(pkts[i]);
    }
    dpa_queue_enqueue(TX_Q, pkts, nb);
}
```

### Minimize Branching

```c
// ❌ BAD: Lots of branches
if (protocol == TCP) {
    if (port == 80) {
        handle_http();
    } else if (port == 443) {
        handle_https();
    }
} else if (protocol == UDP) {
    ...
}

// ✅ GOOD: Use lookup tables
typedef void (*handler_t)(struct rte_mbuf *);
__dpa_global__ handler_t handlers[256][65536];  // protocol][port]

handler_t h = handlers[protocol][port];
if (h) h(pkt);
```

## Debugging

### Print from DPA

```c
__dpa_global__ void debug_kernel(void) {
    dpa_printf("Hello from DPA! Counter=%lu\n", counter);
}
```

### Dump Memory

```bash
# From host
doca_dpa_debug --dump-memory <addr> <size>
```

### Performance Profiling

```c
__dpa_global__ void profiled_kernel(void) {
    uint64_t start = dpa_get_cycles();
    
    process_packet(pkt);
    
    uint64_t end = dpa_get_cycles();
    uint64_t cycles = end - start;
    
    // Log timing
    dpa_printf("Processing took %lu cycles\n", cycles);
}
```

## Key Takeaways

1. **DPA is programmable hardware**, not software
2. **Performance: 50-100 Gbps** (better than ARM, worse than pure hardware)
3. **Use for custom operations** not supported by flow engine
4. **Batch processing** is critical for performance
5. **Minimize synchronization** (locks kill performance)
6. **Generate packets** possible (unlike flow engine)
7. **C programming** via DPACC compiler

## Next Steps
- See [Packet Modification](packet-modification.md) for packet generation examples
- Read [../04-development/performance-tuning.md](../04-development/performance-tuning.md) for tuning
- Check [../04-development/code-examples.md](../04-development/code-examples.md) for complete implementations
