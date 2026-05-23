# DOCA Flow API Programming

## Overview

This document covers hardware flow programming using both the standard DPDK `rte_flow` API and the higher-level NVIDIA `doca_flow` API. Both can be used on BlueField DPUs for hardware-accelerated packet processing.

## API Comparison

| Feature | rte_flow (DPDK) | doca_flow (NVIDIA) |
|---------|-----------------|-------------------|
| Abstraction level | Low | High |
| Pipe concept | No | Yes |
| Connection tracking | Manual | Built-in (doca_flow_ct) |
| Entry batching | No | Yes |
| Async operations | Limited | Full support |
| Mode selection | N/A | vnf, switch, remote_vnf |

## Part 1: rte_flow API

The rte_flow API is the standard DPDK interface for programming hardware packet processing rules. It allows you to:
- Match packets based on header fields
- Perform actions (forward, modify, drop)
- Offload processing to hardware for line-rate performance

### Basic rte_flow Structure

Every flow rule consists of three components:

```c
struct rte_flow_attr attr;      // Attributes (direction, priority)
struct rte_flow_item pattern[]; // Match criteria
struct rte_flow_action actions[]; // Actions to perform
```

### Example: eSwitch Rule Installation (VM-to-VM Forwarding)

This example demonstrates VM-to-VM forwarding using eSwitch representors:

```c
// eswitch_forward.c - VM-to-VM forwarding
#include <rte_flow.h>

int setup_vm_forwarding(uint16_t vf0_port, uint16_t vf1_port) {
    struct rte_flow_attr attr = { .ingress = 1, .priority = 0 };
    struct rte_flow_error error;

    // VF0 → VF1
    uint8_t vm1_mac[6] = {0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0x01};
    uint8_t vm2_mac[6] = {0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0x02};

    struct rte_flow_item pattern[] = {
        {
            .type = RTE_FLOW_ITEM_TYPE_ETH,
            .spec = &(struct rte_flow_item_eth){
                .dst.addr_bytes = {vm2_mac[0], vm2_mac[1], vm2_mac[2],
                                   vm2_mac[3], vm2_mac[4], vm2_mac[5]}
            },
            .mask = &(struct rte_flow_item_eth){
                .dst.addr_bytes = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff}
            }
        },
        { .type = RTE_FLOW_ITEM_TYPE_END }
    };

    struct rte_flow_action actions[] = {
        {
            .type = RTE_FLOW_ACTION_TYPE_PORT_REPRESENTOR,
            .conf = &(struct rte_flow_action_port_representor){
                .port_id = vf1_port
            }
        },
        { .type = RTE_FLOW_ACTION_TYPE_END }
    };

    struct rte_flow *flow = rte_flow_create(vf0_port, &attr, pattern,
                                            actions, &error);
    if (!flow) {
        printf("Flow creation failed: %s\n", error.message);
        return -1;
    }

    return 0;
}
```

### Common rte_flow Patterns

#### Match IPv4 Destination

```c
struct rte_flow_item pattern[] = {
    { .type = RTE_FLOW_ITEM_TYPE_ETH },
    {
        .type = RTE_FLOW_ITEM_TYPE_IPV4,
        .spec = &(struct rte_flow_item_ipv4){
            .hdr.dst_addr = rte_cpu_to_be_32(0x0A000001) // 10.0.0.1
        },
        .mask = &(struct rte_flow_item_ipv4){
            .hdr.dst_addr = 0xFFFFFFFF // Match exact IP
        }
    },
    { .type = RTE_FLOW_ITEM_TYPE_END }
};
```

#### Match TCP Port

```c
struct rte_flow_item pattern[] = {
    { .type = RTE_FLOW_ITEM_TYPE_ETH },
    { .type = RTE_FLOW_ITEM_TYPE_IPV4 },
    {
        .type = RTE_FLOW_ITEM_TYPE_TCP,
        .spec = &(struct rte_flow_item_tcp){
            .hdr.dst_port = rte_cpu_to_be_16(80)
        },
        .mask = &(struct rte_flow_item_tcp){
            .hdr.dst_port = 0xFFFF
        }
    },
    { .type = RTE_FLOW_ITEM_TYPE_END }
};
```

### Flow Rule Lifecycle (rte_flow)

```c
// Validate before creating
int ret = rte_flow_validate(port_id, &attr, pattern, actions, &error);

// Create flow
struct rte_flow *flow = rte_flow_create(port_id, &attr, pattern, actions, &error);

// Query statistics
struct rte_flow_query_count count;
rte_flow_query(port_id, flow, RTE_FLOW_ACTION_TYPE_COUNT, &count, &error);

// Destroy flow
rte_flow_destroy(port_id, flow, &error);

// Flush all flows
rte_flow_flush(port_id, &error);
```

---

## Part 2: DOCA Flow API

DOCA Flow provides a higher-level abstraction for hardware-accelerated packet processing with pipe-based programming model.

### DOCA Flow Concepts

**Pipe**: A template that defines packet processing without adding specific HW rules. Contains match criteria, actions, and forwarding configuration.

**Entry**: A specific instance of a pipe with concrete values. Adding an entry installs the actual HW rule.

**Mode**: Determines traffic flow architecture:
- `vnf`: Virtual Network Function mode - packets can be processed and forwarded
- `switch`: eSwitch mode - packets routed between representors
- `remote_vnf`: Remote VNF mode for host-based applications

### DOCA Flow Initialization

```c
#include <doca_flow.h>

int init_doca_flow(void) {
    struct doca_flow_cfg cfg = {0};
    struct doca_flow_error error;
    
    // Configure DOCA Flow
    cfg.queues = 4;                    // Number of HW acceleration queues
    cfg.mode_args = "vnf,hws";         // VNF mode with hardware steering
    cfg.resource.nb_counters = 1024;   // Number of counters
    cfg.resource.nb_meters = 512;      // Number of meters
    cfg.queue_depth = 128;             // Operations per queue
    cfg.aging = true;                  // Enable flow aging
    
    // Initialize
    doca_error_t result = doca_flow_init(&cfg);
    if (result != DOCA_SUCCESS) {
        printf("DOCA Flow init failed\n");
        return -1;
    }
    
    return 0;
}
```

### Starting DOCA Flow Ports

```c
struct doca_flow_port *start_doca_port(uint16_t dpdk_port_id) {
    struct doca_flow_port_cfg port_cfg = {0};
    struct doca_flow_error error;
    char port_id_str[8];
    
    // Convert DPDK port ID to string
    snprintf(port_id_str, sizeof(port_id_str), "%u", dpdk_port_id);
    
    // Configure port
    port_cfg.port_id = dpdk_port_id;
    port_cfg.type = DOCA_FLOW_PORT_DPDK_BY_ID;
    port_cfg.devargs = port_id_str;
    port_cfg.priv_data_size = sizeof(struct my_port_data); // Optional
    
    // Start port
    struct doca_flow_port *port = doca_flow_port_start(&port_cfg, &error);
    if (!port) {
        printf("Port start failed: %s\n", error.message);
        return NULL;
    }
    
    return port;
}
```

### Creating a DOCA Flow Pipe

```c
struct doca_flow_pipe *create_5tuple_pipe(struct doca_flow_port *port) {
    struct doca_flow_pipe_cfg pipe_cfg = {0};
    struct doca_flow_match match = {0};
    struct doca_flow_match match_mask = {0};
    struct doca_flow_actions actions = {0};
    struct doca_flow_fwd fwd = {0};
    struct doca_flow_fwd fwd_miss = {0};
    struct doca_flow_error error;
    struct doca_flow_pipe *pipe;
    
    // Pipe attributes
    pipe_cfg.attr.name = "5TUPLE_PIPE";
    pipe_cfg.attr.type = DOCA_FLOW_PIPE_BASIC;
    pipe_cfg.attr.is_root = true;       // First pipe to process packets
    pipe_cfg.attr.nb_flows = 8192;      // Max entries
    pipe_cfg.port = port;
    
    // Match on 5-tuple (changeable per entry)
    // Value = 0, Mask = 0xFFFF means changeable field
    match.out_src_ip4_addr = 0;
    match.out_dst_ip4_addr = 0;
    match.out_src_port = 0;
    match.out_dst_port = 0;
    match.out_ip_proto = IPPROTO_TCP;   // Constant: only TCP
    
    match_mask.out_src_ip4_addr = 0xFFFFFFFF;
    match_mask.out_dst_ip4_addr = 0xFFFFFFFF;
    match_mask.out_src_port = 0xFFFF;
    match_mask.out_dst_port = 0xFFFF;
    match_mask.out_ip_proto = 0xFF;
    
    pipe_cfg.match = &match;
    pipe_cfg.match_mask = &match_mask;
    
    // Actions: modify destination MAC (changeable per entry)
    actions.mod_dst_mac[0] = 0xFF;      // Changeable indicator
    pipe_cfg.actions = &actions;
    
    // Forward to port on match
    fwd.type = DOCA_FLOW_FWD_PORT;
    fwd.port_id = 1;                    // Forward to port 1
    
    // Forward to RSS on miss
    fwd_miss.type = DOCA_FLOW_FWD_RSS;
    fwd_miss.rss_queues = (uint16_t[]){0, 1, 2, 3};
    fwd_miss.num_of_queues = 4;
    
    // Create pipe
    doca_error_t result = doca_flow_pipe_create(&pipe_cfg, &fwd, &fwd_miss, &pipe);
    if (result != DOCA_SUCCESS) {
        printf("Pipe creation failed\n");
        return NULL;
    }
    
    return pipe;
}
```

### Adding Entries to a Pipe

```c
int add_flow_entry(struct doca_flow_pipe *pipe, 
                   uint32_t src_ip, uint32_t dst_ip,
                   uint16_t src_port, uint16_t dst_port,
                   uint8_t *new_dst_mac) {
    struct doca_flow_match match = {0};
    struct doca_flow_actions actions = {0};
    struct doca_flow_monitor monitor = {0};
    struct doca_flow_error error;
    
    // Specific match values for this entry
    match.out_src_ip4_addr = rte_cpu_to_be_32(src_ip);
    match.out_dst_ip4_addr = rte_cpu_to_be_32(dst_ip);
    match.out_src_port = rte_cpu_to_be_16(src_port);
    match.out_dst_port = rte_cpu_to_be_16(dst_port);
    
    // Actions for this entry
    memcpy(actions.mod_dst_mac, new_dst_mac, 6);
    
    // Enable counter
    monitor.counter_type = DOCA_FLOW_RESOURCE_TYPE_NON_SHARED;
    
    // Add entry (use queue 0, no wait)
    struct doca_flow_pipe_entry *entry = doca_flow_pipe_add_entry(
        0,                              // pipe_queue (unique per core)
        pipe,
        &match,
        &actions,
        &monitor,
        NULL,                           // Use pipe's default FWD
        DOCA_FLOW_NO_WAIT,
        NULL,                           // user context
        &error
    );
    
    if (!entry) {
        printf("Entry add failed: %s\n", error.message);
        return -1;
    }
    
    // Process entries to complete HW offload
    doca_flow_entries_process(port, 0, 0, 0);
    
    return 0;
}
```

### Querying Entry Statistics

```c
void query_entry_stats(struct doca_flow_pipe_entry *entry) {
    struct doca_flow_query query = {0};
    
    doca_error_t result = doca_flow_query_entry(entry, &query);
    if (result == DOCA_SUCCESS) {
        printf("Packets: %lu, Bytes: %lu\n", 
               query.total_pkts, query.total_bytes);
    }
}
```

### Complete DOCA Flow Example

```c
#include <doca_flow.h>
#include <rte_eal.h>
#include <rte_ethdev.h>

int main(int argc, char **argv) {
    struct doca_flow_port *ports[2];
    struct doca_flow_pipe *pipe;
    
    // Initialize DPDK
    rte_eal_init(argc, argv);
    
    // Configure and start DPDK ports
    // ... (standard DPDK port setup)
    
    // Initialize DOCA Flow
    struct doca_flow_cfg cfg = {
        .queues = 4,
        .mode_args = "vnf,hws",
        .resource.nb_counters = 1024,
    };
    doca_flow_init(&cfg);
    
    // Start DOCA Flow ports
    ports[0] = start_doca_port(0);
    ports[1] = start_doca_port(1);
    
    // Pair ports for forwarding
    doca_flow_port_pair(ports[0], ports[1]);
    doca_flow_port_pair(ports[1], ports[0]);
    
    // Create pipe
    pipe = create_5tuple_pipe(ports[0]);
    
    // Add entries
    uint8_t new_mac[6] = {0x00, 0x11, 0x22, 0x33, 0x44, 0x55};
    add_flow_entry(pipe, 
                   0x0A000001,  // 10.0.0.1
                   0x0A000002,  // 10.0.0.2
                   1234, 80,
                   new_mac);
    
    // Main loop - process packets
    while (running) {
        // Process entries periodically
        doca_flow_entries_process(ports[0], 0, 1000, 0);
        
        // Handle aged entries if aging is enabled
        // ...
    }
    
    // Cleanup
    doca_flow_pipe_destroy(pipe);
    doca_flow_port_stop(ports[0]);
    doca_flow_port_stop(ports[1]);
    doca_flow_destroy();
    
    return 0;
}
```

### DOCA Flow Pipe Types

| Type | Use Case | Features |
|------|----------|----------|
| `DOCA_FLOW_PIPE_BASIC` | General flow matching | Standard 5-tuple, tunnels |
| `DOCA_FLOW_PIPE_CONTROL` | Priority-based routing | Direct entries to other pipes |
| `DOCA_FLOW_PIPE_LPM` | Longest prefix match | IP routing tables |
| `DOCA_FLOW_PIPE_ACL` | Access control lists | IP ranges, port ranges |
| `DOCA_FLOW_PIPE_ORDERED_LIST` | Ordered processing | Sequential action lists |
| `DOCA_FLOW_PIPE_HASH` | Hash-based lookup | Fast exact match |

### DOCA Flow Modes

```c
// VNF Mode - packet processing application
cfg.mode_args = "vnf,hws";

// Switch Mode - eSwitch based forwarding
cfg.mode_args = "switch,hws";

// Remote VNF Mode - host-based processing
cfg.mode_args = "remote_vnf,hws";
```

---

## Best Practices

1. **Validate before creating**: Use `rte_flow_validate()` to catch errors early
2. **Add counters**: Include monitoring for debugging
3. **Use priority wisely**: Specific rules at priority 0, catch-all at higher values
4. **Check offload status**: Verify rules are actually offloaded to hardware
5. **Age out old flows**: Use flow aging to prevent table exhaustion
6. **Handle errors**: Always check return values and error messages
7. **Queue per core**: Each core should use a dedicated pipe_queue in DOCA Flow

## Troubleshooting

### Flow Creation Fails

```c
struct rte_flow_error error;
struct rte_flow *flow = rte_flow_create(port, &attr, pattern, actions, &error);
if (!flow) {
    printf("Type: %d\n", error.type);
    printf("Message: %s\n", error.message);
}
```

### Rule Not Matching Packets

- Add counter and query it to verify matches
- Check pattern spec and mask values
- Verify packet format matches pattern
- Check rule priority

### Hardware Offload Verification

```bash
# OVS offloaded flows
ovs-appctl dpctl/dump-flows type=offloaded

# Check hardware counters
ethtool -S p0 | grep offload
```

## Key Takeaways

1. **rte_flow** is the standard DPDK API for hardware flow programming
2. **doca_flow** provides higher abstraction with pipe-based model
3. **Hardware offload** provides line-rate performance (400 Gbps)
4. **DOCA Flow** supports connection tracking, aging, and advanced features
5. **Mode selection** (vnf/switch) determines traffic flow architecture

## Next Steps

- See [DPDK Integration](dpdk-integration.md) for queue setup
- Read [Packet Modification](packet-modification.md) for actions
- Check [../01-architecture/eswitch-flow-engine.md](../01-architecture/eswitch-flow-engine.md) for hardware details
- Review [../05-reference/api-cheatsheet.md](../05-reference/api-cheatsheet.md) for function signatures
