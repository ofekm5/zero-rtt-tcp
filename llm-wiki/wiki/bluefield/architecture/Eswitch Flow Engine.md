---
type: Wiki Entry
title: "eSwitch and NIC Flow Engine"
description: "The eSwitch IS NOT separate hardware - it's a logical concept implemented using the NIC Flow Engine."
tags: [bluefield, architecture]
timestamp: 2026-05-23T16:09:41+03:00
---

Source: `infra/bluefield/docs/01-architecture/eswitch-flow-engine.md`

# eSwitch and NIC Flow Engine

## Critical Understanding

**The eSwitch IS NOT separate hardware** - it's a logical concept implemented using the NIC Flow Engine.

```
❌ WRONG MODEL:
   Packet → NIC Flow Engine → eSwitch → Output

✅ CORRECT MODEL:
   Packet → NIC Flow Engine → Output
            (eSwitch is just port-to-port forwarding rules)
```

## What is the eSwitch?

### Definition

The **eSwitch (embedded switch)** is:
- A virtual switch connecting multiple representor ports
- Implemented as **flow table entries** in the NIC Flow Engine
- NOT a separate piece of hardware
- Just a way of thinking about port-to-port forwarding

### Port Representors

```
Hardware Internal Ports:

Port 0:  pf0 (Physical Port 0 - external network)
Port 1:  pf1 (Physical Port 1 - external network)  
Port 2:  pf0hpf (Host Physical Function)
Port 3:  pf0vf0 (Host VF 0 - VM 0)
Port 4:  pf0vf1 (Host VF 1 - VM 1)
Port 5:  ARM uplink (to ARM cores)
Port 6:  DPA queue 0
...

These are just IDs in the flow table!
```

## The NIC Flow Engine

### Architecture

```
┌──────────────────────────────────────────┐
│       NIC Flow Steering Engine           │
│                                          │
│  ┌────────────────────────────────┐    │
│  │  Stage 1: Root Table (Table 0) │    │
│  │  Priority: Highest              │    │
│  │  Type: TCAM (ternary match)     │    │
│  │  Size: ~100K entries            │    │
│  └──────────────┬─────────────────┘    │
│                 ↓                        │
│  ┌────────────────────────────────┐    │
│  │  Stage 2: Group Tables          │    │
│  │  Priority: Medium               │    │
│  │  Type: Hash (exact match)       │    │
│  │  Size: ~1M-16M entries          │    │
│  └──────────────┬─────────────────┘    │
│                 ↓                        │
│  ┌────────────────────────────────┐    │
│  │  Action Engine                  │    │
│  │  • Forward to port              │    │
│  │  • Modify headers               │    │
│  │  • Encap/Decap                  │    │
│  └────────────────────────────────┘    │
└──────────────────────────────────────────┘
```

### Flow Table Storage

**Physical Location**:
```
┌─────────────────────────────────────┐
│  On-chip SRAM/TCAM (fastest)        │
│  • High-priority rules              │
│  • ~100K-1M entries                 │
│  • <1 μs lookup                     │
├─────────────────────────────────────┤
│  On-chip Hash Tables (fast)         │
│  • Exact match flows                │
│  • ~1M-16M entries                  │
│  • ~10 cycles lookup                │
├─────────────────────────────────────┤
│  External DRAM (medium)             │
│  • Overflow/cold flows              │
│  • Larger capacity                  │
│  • ~100 ns lookup                   │
└─────────────────────────────────────┘
```

## How eSwitch Actually Works

### Example: VM-to-VM Communication

**Setup**: Two VMs on x86 host, both have VFs

```
VM1 → VF0 (MAC: aa:bb:cc:dd:ee:01)
VM2 → VF1 (MAC: aa:bb:cc:dd:ee:02)
```

**What Gets Programmed**:

```c
// Flow Rule 1: VF0 → VF1
rte_flow_create(
    port = vf0_representor,
    match = {
        .type = RTE_FLOW_ITEM_TYPE_ETH,
        .spec = { .dst.addr_bytes = {0xaa,0xbb,0xcc,0xdd,0xee,0x02} }
    },
    action = {
        .type = RTE_FLOW_ACTION_TYPE_PORT_REPRESENTOR,
        .conf = { .port_id = vf1_representor }
    }
);

// Flow Rule 2: VF1 → VF0
rte_flow_create(
    port = vf1_representor,
    match = {
        .type = RTE_FLOW_ITEM_TYPE_ETH,
        .spec = { .dst.addr_bytes = {0xaa,0xbb,0xcc,0xdd,0xee,0x01} }
    },
    action = {
        .type = RTE_FLOW_ACTION_TYPE_PORT_REPRESENTOR,
        .conf = { .port_id = vf0_representor }
    }
);
```

**In Hardware Flow Table**:

```
┌──────────────────────────────────────────────┐
│ Entry #1:                                    │
│   Match: {ingress_port=VF0 (ID:3),           │
│           dst_mac=aa:bb:cc:dd:ee:02}         │
│   Action: Forward to port VF1 (ID:4)         │
│   Counter: 1234 packets                      │
├──────────────────────────────────────────────┤
│ Entry #2:                                    │
│   Match: {ingress_port=VF1 (ID:4),           │
│           dst_mac=aa:bb:cc:dd:ee:01}         │
│   Action: Forward to port VF0 (ID:3)         │
│   Counter: 5678 packets                      │
└──────────────────────────────────────────────┘
```

**Packet Flow**:
```
1. VM1 sends packet (dst_mac = aa:bb:cc:dd:ee:02)
2. Packet arrives at VF0 (hardware port ID 3)
3. Flow engine looks up: ingress=3, dst_mac=aa:bb:cc:dd:ee:02
4. Match found → Action: Forward to port 4 (VF1)
5. Packet forwarded to VM2 via VF1
6. All in hardware, <1 μs, no ARM CPU involved
```

## Programming the eSwitch

### Method 1: Direct rte_flow API

```c
// Setup flow rule for eSwitch forwarding
int setup_eswitch_rule(uint16_t src_port, uint16_t dst_port,
                       uint8_t dst_mac[6]) {
    struct rte_flow_attr attr = {
        .ingress = 1,      // Match on ingress
        .priority = 0,     // High priority
    };
    
    struct rte_flow_item pattern[] = {
        {
            .type = RTE_FLOW_ITEM_TYPE_ETH,
            .spec = &(struct rte_flow_item_eth){
                .dst.addr_bytes = {
                    dst_mac[0], dst_mac[1], dst_mac[2],
                    dst_mac[3], dst_mac[4], dst_mac[5]
                }
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
                .port_id = dst_port
            }
        },
        {
            .type = RTE_FLOW_ACTION_TYPE_COUNT  // Optional: count packets
        },
        { .type = RTE_FLOW_ACTION_TYPE_END }
    };
    
    struct rte_flow_error error;
    struct rte_flow *flow = rte_flow_create(src_port, &attr, 
                                            pattern, actions, &error);
    
    if (!flow) {
        printf("Flow creation failed: %s\n", error.message);
        return -1;
    }
    
    return 0;
}
```

### Method 2: OVS-DPDK (Higher Level)

```bash
# Create OVS bridge
ovs-vsctl add-br br0

# Add representor ports to bridge
ovs-vsctl add-port br0 pf0hpf -- set interface pf0hpf type=dpdk
ovs-vsctl add-port br0 pf0vf0 -- set interface pf0vf0 type=dpdk
ovs-vsctl add-port br0 pf0vf1 -- set interface pf0vf1 type=dpdk

# Add flow rules (OVS will offload to hardware)
ovs-ofctl add-flow br0 "in_port=pf0vf0,dl_dst=aa:bb:cc:dd:ee:02,actions=output:pf0vf1"
ovs-ofctl add-flow br0 "in_port=pf0vf1,dl_dst=aa:bb:cc:dd:ee:01,actions=output:pf0vf0"

# Verify hardware offload
ovs-appctl dpctl/dump-flows type=offloaded
```

### Method 3: DOCA Flow API

```c
#include <doca_flow.h>

// Create forwarding pipe
struct doca_flow_match match = {
    .outer_l2_type = DOCA_FLOW_L2_TYPE_ETHER,
};

struct doca_flow_actions actions = {
    .action_type = DOCA_FLOW_ACTION_FORWARD,
};

struct doca_flow_fwd fwd = {
    .type = DOCA_FLOW_FWD_PORT,
    .port_id = dst_port_id,
};

struct doca_flow_pipe_cfg pipe_cfg = {
    .attr = {
        .name = "ESWITCH_FWD",
        .type = DOCA_FLOW_PIPE_BASIC,
        .is_root = true,
    },
    .port = doca_port,
    .match = &match,
    .actions = &actions,
};

struct doca_flow_pipe *pipe;
doca_flow_pipe_create(&pipe_cfg, &fwd, NULL, &pipe);

// Add entry
struct doca_flow_match match_entry = {
    .outer_eth_dst = {0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0x02},
};

doca_flow_pipe_add_entry(0, pipe, &match_entry, NULL, NULL, NULL, 0, NULL, NULL);
```

## Advanced eSwitch Scenarios

### Scenario 1: VLAN-Based Isolation

```c
// VM1 in VLAN 100, VM2 in VLAN 200
// Physical port receives tagged traffic

// Rule: VLAN 100 → VF0 (strip VLAN)
struct rte_flow_item pattern[] = {
    { .type = RTE_FLOW_ITEM_TYPE_ETH },
    {
        .type = RTE_FLOW_ITEM_TYPE_VLAN,
        .spec = &(struct rte_flow_item_vlan){ .tci = rte_cpu_to_be_16(100) }
    },
    { .type = RTE_FLOW_ITEM_TYPE_END }
};

struct rte_flow_action actions[] = {
    { .type = RTE_FLOW_ACTION_TYPE_OF_POP_VLAN },  // Strip VLAN
    {
        .type = RTE_FLOW_ACTION_TYPE_PORT_REPRESENTOR,
        .conf = &(struct rte_flow_action_port_representor){ .port_id = vf0 }
    },
    { .type = RTE_FLOW_ACTION_TYPE_END }
};
```

### Scenario 2: VXLAN Overlay Network

```c
// Encapsulate VM traffic into VXLAN for network

// VF0 → VXLAN (VNI 1000) → Physical Port
struct rte_flow_action actions[] = {
    {
        .type = RTE_FLOW_ACTION_TYPE_VXLAN_ENCAP,
        .conf = &(struct rte_flow_action_vxlan_encap){
            .definition = vxlan_encap_conf  // VNI, outer IPs, etc.
        }
    },
    {
        .type = RTE_FLOW_ACTION_TYPE_PORT_ID,
        .conf = &(struct rte_flow_action_port_id){ .id = physical_port }
    },
    { .type = RTE_FLOW_ACTION_TYPE_END }
};
```

### Scenario 3: Traffic Mirroring

```c
// Mirror VF0 traffic to ARM for inspection

struct rte_flow_action actions[] = {
    // Primary action: forward normally
    {
        .type = RTE_FLOW_ACTION_TYPE_PORT_REPRESENTOR,
        .conf = &(struct rte_flow_action_port_representor){ .port_id = vf1 }
    },
    // Secondary action: mirror to ARM
    {
        .type = RTE_FLOW_ACTION_TYPE_SAMPLE,
        .conf = &(struct rte_flow_action_sample){
            .ratio = 1,  // Mirror all packets (or 100 for 1%)
            .actions = (struct rte_flow_action[]){
                {
                    .type = RTE_FLOW_ACTION_TYPE_PORT_REPRESENTOR,
                    .conf = &(struct rte_flow_action_port_representor){
                        .port_id = arm_uplink
                    }
                },
                { .type = RTE_FLOW_ACTION_TYPE_END }
            }
        }
    },
    { .type = RTE_FLOW_ACTION_TYPE_END }
};
```

## Flow Table Management

### Checking Flow Rules

```bash
# Via OVS
ovs-appctl dpctl/dump-flows
ovs-appctl dpctl/dump-flows type=offloaded

# Via mlxdump (low-level)
mlxdump -d /dev/mst/mt41686_pciconf0 fsdump --type FT --gvmi=0

# Via DOCA
doca_flow_query(flow_entry, &query_stats);
```

### Flow Rule Priority

```c
// Higher priority = checked first
struct rte_flow_attr attr = {
    .priority = 0,     // Highest priority (specific rules)
};

// Lower priority numbers checked before higher
// Priority 0 > Priority 1 > Priority 2 > ...

// Example hierarchy:
// Priority 0: Specific IP rules (10.0.0.1 → VF0)
// Priority 100: General traffic (any → default)
```

### Flow Rule Limits

```
Hardware Capacity (approximate):
├─ TCAM entries: ~100K-1M (priority/wildcard rules)
├─ Hash entries: ~1M-16M (exact match rules)  
└─ Total active flows: Limited by table size + complexity

Rule Complexity affects capacity:
├─ Simple MAC forward: 16M flows possible
├─ MAC + IP + Port: 8M flows possible
└─ Complex multi-action: 1M flows possible
```

### When Flow Table is Full

```c
// rte_flow_create() will fail
struct rte_flow *flow = rte_flow_create(...);
if (flow == NULL) {
    // Options:
    // 1. Age out old flows (timeout)
    // 2. Use more general rules
    // 3. Fall back to software processing
}
```

## Hardware Offload Verification

### Check if Rule is Offloaded

```bash
# OVS: Check offload status
ovs-appctl dpctl/dump-flows type=offloaded

# DOCA: Query flow statistics
doca_flow_query(entry, &stats);
if (stats.offloaded) {
    printf("Rule is in hardware\n");
}

# Counters should increment at line-rate
ethtool -S <interface> | grep offload
```

### Common Reasons for Offload Failure

```
❌ Flow rule too complex for hardware
❌ Table full (capacity exceeded)
❌ Unsupported action (e.g., arbitrary field modification)
❌ Conflicting rules (same pattern, different action)
❌ Feature not enabled (SR-IOV not configured)
```

## Performance Comparison

| Method | Throughput | Latency | Setup Complexity |
|--------|------------|---------|------------------|
| **Hardware eSwitch** | 400 Gbps | <1 μs | Medium |
| **Software OVS on ARM** | 10-20 Gbps | 100-200 μs | Low |
| **DPDK on ARM** | 10-20 Gbps/core | 50-100 μs | High |

## Example: Complete eSwitch Setup

```c
#include <rte_flow.h>
#include <rte_ethdev.h>

int main(int argc, char **argv) {
    // Initialize DPDK
    rte_eal_init(argc, argv);
    
    // Get representor port IDs
    uint16_t pf0_port, vf0_port, vf1_port;
    get_representor_ports(&pf0_port, &vf0_port, &vf1_port);
    
    // Setup bidirectional VM-to-VM forwarding
    uint8_t vm1_mac[6] = {0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0x01};
    uint8_t vm2_mac[6] = {0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0x02};
    
    // VM1 → VM2
    setup_eswitch_rule(vf0_port, vf1_port, vm2_mac);
    
    // VM2 → VM1
    setup_eswitch_rule(vf1_port, vf0_port, vm1_mac);
    
    // Setup external connectivity
    // Physical Port → VMs (based on MAC)
    setup_eswitch_rule(pf0_port, vf0_port, vm1_mac);
    setup_eswitch_rule(pf0_port, vf1_port, vm2_mac);
    
    // VMs → Physical Port (default)
    setup_default_egress(vf0_port, pf0_port);
    setup_default_egress(vf1_port, pf0_port);
    
    printf("eSwitch configured, traffic is hardware-accelerated\n");
    
    // Monitor (optional)
    while (1) {
        print_flow_stats();
        sleep(1);
    }
    
    return 0;
}
```

## Key Takeaways

1. **eSwitch is NOT separate hardware** - it's flow table entries
2. **Port representors are just IDs** in the flow engine
3. **Flow rules implement switching logic** at line-rate
4. **All forwarding goes through one unified pipeline**
5. **Hardware offload is automatic** (if rule is supported)
6. **Priority controls rule matching order**
7. **Capacity is limited** by hardware table size
8. **OVS can program eSwitch** via rte_flow offload

## Next Steps
- See [[Hardware Overview]] for operating modes comparison
- Read [[Packet Modification]] for action types
- Check [[Code Examples]] for complete implementations
