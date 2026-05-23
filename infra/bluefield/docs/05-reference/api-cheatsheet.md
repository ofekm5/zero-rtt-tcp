# API Cheatsheet

## rte_flow Functions (DPDK) ✅ Verified

### Core Flow API

```c
// Validate flow rule before creating
int rte_flow_validate(uint16_t port_id,
                      const struct rte_flow_attr *attr,
                      const struct rte_flow_item pattern[],
                      const struct rte_flow_action actions[],
                      struct rte_flow_error *error);

// Create flow rule
struct rte_flow *rte_flow_create(uint16_t port_id,
                                  const struct rte_flow_attr *attr,
                                  const struct rte_flow_item pattern[],
                                  const struct rte_flow_action actions[],
                                  struct rte_flow_error *error);

// Destroy flow rule
int rte_flow_destroy(uint16_t port_id,
                     struct rte_flow *flow,
                     struct rte_flow_error *error);

// Flush all flows on a port
int rte_flow_flush(uint16_t port_id,
                   struct rte_flow_error *error);

// Query flow statistics
int rte_flow_query(uint16_t port_id,
                   struct rte_flow *flow,
                   const struct rte_flow_action *action,
                   void *data,
                   struct rte_flow_error *error);
```

## rte_eth Functions (DPDK Packet I/O) ✅ Verified

### Queue Operations

```c
// Receive packets
uint16_t rte_eth_rx_burst(uint16_t port_id,
                          uint16_t queue_id,
                          struct rte_mbuf **rx_pkts,
                          const uint16_t nb_pkts);

// Transmit packets
uint16_t rte_eth_tx_burst(uint16_t port_id,
                          uint16_t queue_id,
                          struct rte_mbuf **tx_pkts,
                          uint16_t nb_pkts);
```

### Port Configuration

```c
// Configure ethernet device
int rte_eth_dev_configure(uint16_t port_id,
                          uint16_t nb_rx_queue,
                          uint16_t nb_tx_queue,
                          const struct rte_eth_conf *eth_conf);

// Setup RX queue
int rte_eth_rx_queue_setup(uint16_t port_id,
                           uint16_t rx_queue_id,
                           uint16_t nb_rx_desc,
                           unsigned int socket_id,
                           const struct rte_eth_rxconf *rx_conf,
                           struct rte_mempool *mb_pool);

// Setup TX queue
int rte_eth_tx_queue_setup(uint16_t port_id,
                           uint16_t tx_queue_id,
                           uint16_t nb_tx_desc,
                           unsigned int socket_id,
                           const struct rte_eth_txconf *tx_conf);

// Start device
int rte_eth_dev_start(uint16_t port_id);

// Stop device
int rte_eth_dev_stop(uint16_t port_id);
```

## DOCA Flow Functions ✅ Verified

DOCA Flow provides a higher-level API for hardware-accelerated packet processing pipelines.

### Initialization

```c
// Initialize DOCA Flow (must be called first)
doca_error_t doca_flow_init(const struct doca_flow_cfg *cfg);

// Configuration structure
struct doca_flow_cfg {
    uint16_t queues;                    // Number of HW acceleration queues
    struct doca_flow_resources resource; // Resource quotas
    const char *mode_args;              // "vnf", "switch", or "remote_vnf"
    bool aging;                         // Enable flow aging
    uint32_t nr_shared_resources[DOCA_FLOW_SHARED_RESOURCE_MAX];
    uint32_t queue_depth;               // Operations per queue (default: 128)
    doca_flow_entry_process_cb cb;      // Entry callback
};

// Destroy DOCA Flow
void doca_flow_destroy(void);
```

### Port Management

```c
// Start a DOCA Flow port
struct doca_flow_port *doca_flow_port_start(
    const struct doca_flow_port_cfg *cfg,
    struct doca_flow_error *error);

// Port configuration
struct doca_flow_port_cfg {
    uint16_t port_id;                   // Port ID (DPDK port_id for DPDK type)
    enum doca_flow_port_type type;      // DOCA_FLOW_PORT_DPDK_BY_ID
    const char *devargs;                // DPDK port_id as string (e.g., "0")
    uint16_t priv_data_size;            // Private data size
    void *dev;                          // Optional doca_dev pointer
};

// Stop a port
doca_error_t doca_flow_port_stop(struct doca_flow_port *port);

// Pair ports for forwarding (unidirectional)
doca_error_t doca_flow_port_pair(struct doca_flow_port *port,
                                  struct doca_flow_port *pair_port);

// Get port's private data
void *doca_flow_port_priv_data(struct doca_flow_port *port);
```

### Pipe Management

```c
// Create a pipe (template for flow rules)
doca_error_t doca_flow_pipe_create(
    const struct doca_flow_pipe_cfg *cfg,
    const struct doca_flow_fwd *fwd,
    const struct doca_flow_fwd *fwd_miss,
    struct doca_flow_pipe **pipe);

// Pipe configuration
struct doca_flow_pipe_cfg {
    struct doca_flow_pipe_attr attr;     // Pipe attributes
    struct doca_flow_port *port;         // Port for the pipe
    struct doca_flow_match *match;       // Match template
    struct doca_flow_match *match_mask;  // Match mask (optional)
    struct doca_flow_actions *actions;   // Actions template
    struct doca_flow_monitor *monitor;   // Monitor template
};

// Pipe attributes
struct doca_flow_pipe_attr {
    const char *name;                    // Pipe name
    enum doca_flow_pipe_type type;       // BASIC, CONTROL, LPM, ACL
    enum doca_flow_pipe_domain domain;   // DEFAULT, SECURE_INGRESS, etc.
    bool is_root;                        // Root pipe (one per port)
    uint32_t nb_flows;                   // Max flow rules (default: 8K)
    uint8_t nb_actions;                  // Max actions array (default: 1)
};

// Destroy a pipe
doca_error_t doca_flow_pipe_destroy(struct doca_flow_pipe *pipe);

// Dump pipe info to file
doca_error_t doca_flow_pipe_dump(struct doca_flow_pipe *pipe, FILE *f);
```

### Entry Management

```c
// Add entry to a pipe
struct doca_flow_pipe_entry *doca_flow_pipe_add_entry(
    uint16_t pipe_queue,                 // Queue ID (unique per core)
    struct doca_flow_pipe *pipe,
    const struct doca_flow_match *match,
    const struct doca_flow_actions *actions,
    const struct doca_flow_monitor *mon,
    const struct doca_flow_fwd *fwd,
    uint32_t flags,                      // DOCA_FLOW_NO_WAIT, etc.
    void *usr_ctx,                       // User context for callback
    struct doca_flow_error *error);

// Remove entry from pipe
doca_error_t doca_flow_pipe_rm_entry(
    uint16_t pipe_queue,
    void *usr_ctx,
    struct doca_flow_pipe_entry *entry);

// Process entries (must call to complete offloading)
doca_error_t doca_flow_entries_process(
    struct doca_flow_port *port,
    uint16_t pipe_queue,
    uint64_t timeout,
    uint32_t max_processed);

// Query entry statistics
doca_error_t doca_flow_query_entry(
    struct doca_flow_pipe_entry *entry,
    struct doca_flow_query *query_stats);

// Query result structure
struct doca_flow_query {
    uint64_t total_bytes;                // Total bytes matched
    uint64_t total_pkts;                 // Total packets matched
};
```

### Forwarding Actions

```c
// Forwarding configuration
struct doca_flow_fwd {
    enum doca_flow_fwd_type type;        // RSS, PORT, PIPE, DROP
    
    // For RSS forwarding
    uint32_t rss_flags;                  // DOCA_FLOW_RSS_IP/UDP/TCP
    uint16_t *rss_queues;                // Queue array
    int num_of_queues;                   // Number of queues
    
    // For PORT forwarding  
    uint16_t port_id;                    // Destination port
    
    // For PIPE forwarding
    struct doca_flow_pipe *next_pipe;    // Next pipe
};

// Forwarding types
enum doca_flow_fwd_type {
    DOCA_FLOW_FWD_RSS,                   // Forward to RSS queues
    DOCA_FLOW_FWD_PORT,                  // Forward to port
    DOCA_FLOW_FWD_PIPE,                  // Forward to another pipe
    DOCA_FLOW_FWD_DROP,                  // Drop packet
    DOCA_FLOW_FWD_ORDERED_LIST_PIPE,     // Forward to ordered list
};
```

### Match Structure

```c
struct doca_flow_match {
    uint32_t flags;
    struct doca_flow_meta meta;          // Metadata matching
    
    // Outer headers
    uint8_t out_src_mac[6];
    uint8_t out_dst_mac[6];
    rte_be16_t out_eth_type;
    rte_be16_t out_vlan_id;
    
    rte_be32_t out_src_ip4_addr;
    rte_be32_t out_dst_ip4_addr;
    uint8_t out_src_ip6_addr[16];
    uint8_t out_dst_ip6_addr[16];
    
    uint8_t out_ip_proto;
    uint8_t out_ttl;
    
    rte_be16_t out_src_port;
    rte_be16_t out_dst_port;
    rte_be32_t out_tcp_flags;
    
    // Tunnel headers
    enum doca_flow_tun_type tun_type;    // VXLAN, GRE, GTP
    rte_be32_t vxlan_vni;
    rte_be32_t gre_key;
    rte_be32_t gtp_teid;
    
    // Inner headers (for tunneled traffic)
    // ... similar to outer headers with in_ prefix
};
```

### Actions Structure

```c
struct doca_flow_actions {
    uint32_t flags;
    bool decap;                          // Decapsulate tunnel
    bool pop_vlan;                       // Pop VLAN tag
    
    // Header modifications
    uint8_t mod_src_mac[6];
    uint8_t mod_dst_mac[6];
    rte_be32_t mod_src_ip4_addr;
    rte_be32_t mod_dst_ip4_addr;
    rte_be16_t mod_src_port;
    rte_be16_t mod_dst_port;
    
    bool dec_ttl;                        // Decrement TTL
    
    // Encapsulation
    struct doca_flow_encap_action encap; // Tunnel encapsulation
    
    // Metadata
    struct doca_flow_meta meta;
};
```

## FlexIO Functions (DPA Integration) ✅ Verified

Used for advanced hardware access and DPA programming.

```c
// Create FlexIO RQ (receive queue)
flexio_status flexio_rq_create(
    flexio_process *process,
    ibv_context *ibv_ctx,
    uint32_t cq_num,
    const flexio_wq_attr *fattr,
    flexio_rq **flexio_rq_ptr);

// Get RQ work queue number
uint32_t flexio_rq_get_wq_num(flexio_rq *rq);

// Get RQ TIR (Transport Interface Receive) object
mlx5dv_devx_obj *flexio_rq_get_tir(flexio_rq *rq);

// Destroy RQ
flexio_status flexio_rq_destroy(flexio_rq *flexio_rq);

// Create FlexIO SQ (send queue)
flexio_status flexio_sq_create(
    flexio_process *process,
    ibv_context *ibv_ctx,
    uint32_t cq_num,
    const flexio_wq_attr *fattr,
    flexio_sq **flexio_sq_ptr);

// Get SQ work queue number
uint32_t flexio_sq_get_wq_num(flexio_sq *sq);
```

## mlx5 PMD Functions ✅ Verified

```c
// Map external RX queue to DPDK flow index
int rte_pmd_mlx5_external_rx_queue_id_map(
    uint16_t port_id,
    uint16_t dpdk_idx,
    uint32_t hw_idx);

// Unmap external RX queue
int rte_pmd_mlx5_external_rx_queue_id_unmap(
    uint16_t port_id,
    uint16_t dpdk_idx);

// Map external TX queue (DPDK 24.07+)
int rte_pmd_mlx5_external_tx_queue_id_map(
    uint16_t port_id,
    uint16_t dpdk_idx,
    uint32_t hw_idx);
```

## Helper Functions ✅ Verified

### Checksum Calculation

```c
// IPv4 header checksum
uint16_t rte_ipv4_cksum(const struct rte_ipv4_hdr *ipv4_hdr);

// TCP/UDP checksum over IPv4
uint16_t rte_ipv4_udptcp_cksum(const struct rte_ipv4_hdr *ipv4_hdr,
                               const void *l4_hdr);

// TCP/UDP checksum over IPv6
uint16_t rte_ipv6_udptcp_cksum(const struct rte_ipv6_hdr *ipv6_hdr,
                               const void *l4_hdr);

// Verify TCP/UDP checksum
int rte_ipv4_udptcp_cksum_verify(const struct rte_ipv4_hdr *ipv4_hdr,
                                  const void *l4_hdr);
```

### Packet Buffer Management

```c
// Allocate mbuf
struct rte_mbuf *rte_pktmbuf_alloc(struct rte_mempool *mp);

// Free mbuf
void rte_pktmbuf_free(struct rte_mbuf *m);

// Create mempool
struct rte_mempool *rte_pktmbuf_pool_create(const char *name,
                                            unsigned n,
                                            unsigned cache_size,
                                            uint16_t priv_size,
                                            uint16_t data_room_size,
                                            int socket_id);

// Get pointer to packet data
#define rte_pktmbuf_mtod(m, t) ((t)((char *)(m)->buf_addr + (m)->data_off))
```

## Quick Reference

| Task | API | Header |
|------|-----|--------|
| **DPDK Flow** | | |
| Receive packets | `rte_eth_rx_burst()` | `rte_ethdev.h` |
| Send packets | `rte_eth_tx_burst()` | `rte_ethdev.h` |
| Create rte_flow | `rte_flow_create()` | `rte_flow.h` |
| Destroy rte_flow | `rte_flow_destroy()` | `rte_flow.h` |
| **DOCA Flow** | | |
| Initialize | `doca_flow_init()` | `doca_flow.h` |
| Start port | `doca_flow_port_start()` | `doca_flow.h` |
| Create pipe | `doca_flow_pipe_create()` | `doca_flow.h` |
| Add entry | `doca_flow_pipe_add_entry()` | `doca_flow.h` |
| Query entry | `doca_flow_query_entry()` | `doca_flow.h` |
| **Utilities** | | |
| Allocate packet | `rte_pktmbuf_alloc()` | `rte_mbuf.h` |
| Calculate checksum | `rte_ipv4_cksum()` | `rte_ip.h` |

## API Selection Guide

| Use Case | Recommended API |
|----------|-----------------|
| Simple flow rules | `rte_flow` (DPDK) |
| Complex pipelines | `doca_flow` (higher abstraction) |
| Connection tracking | `doca_flow_ct` |
| DPA integration | FlexIO SDK + `rte_pmd_mlx5_*` |
| VNF applications | DOCA Flow in `vnf` mode |
| Switch applications | DOCA Flow in `switch` mode |

## Next Steps

- See [../02-programming/doca-flow-api.md](../02-programming/doca-flow-api.md) for DOCA Flow examples
- Read [../02-programming/dpdk-integration.md](../02-programming/dpdk-integration.md) for DPDK setup
- Check [cli-commands.md](cli-commands.md) for CLI tools
- Review [gotchas.md](gotchas.md) for common mistakes