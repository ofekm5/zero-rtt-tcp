# DOCA DPL (P4) Programming

## Overview
DOCA DPL (Declarative Programming Language) is based on P4 and provides a high-level way to program the BlueField-3 packet processing pipeline, including the hardware parser.

## DPL vs DPA vs rte_flow

| Aspect | DOCA DPL (P4) | DPA (C) | rte_flow API |
|--------|---------------|---------|--------------|
| **Abstraction** | High (declarative) | Low (imperative) | Medium (API calls) |
| **Language** | P4-like | C | C API |
| **Target** | Parser + Flow Engine + DPA | DPA only | Flow Engine only |
| **Compilation** | Compiler decides placement | Manual | Runtime |
| **Complexity** | Medium | High | Low |
| **Flexibility** | Medium | Highest | Lowest |
| **Best For** | Pipeline-style processing | Custom algorithms | Simple forwarding |

## What is P4?

**P4 (Programming Protocol-Independent Packet Processors)** is a domain-specific language for describing packet processing.

### P4 Concepts

```p4
// Parser: Define how to extract headers
parser MyParser(packet_in packet, out headers hdr) {
    state start {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4;
            default: accept;
        }
    }
}

// Match-Action Tables: Define forwarding logic
table ipv4_forward {
    key = {
        hdr.ipv4.dstAddr: exact;
    }
    actions = {
        forward;
        drop;
    }
    default_action = drop;
}

// Control: Pipeline flow
control MyIngress(inout headers hdr, inout metadata meta) {
    apply {
        if (hdr.ipv4.isValid()) {
            ipv4_forward.apply();
        }
    }
}
```

## DOCA DPL Architecture

### How DPL Programs Get Compiled

```
┌──────────────────────────────────────┐
│     P4/DPL Source Code               │
│     (myapp.p4)                       │
└──────────────┬───────────────────────┘
               ↓
┌──────────────────────────────────────┐
│     DOCA DPL Compiler                │
│     (doca-p4c)                       │
└──────────────┬───────────────────────┘
               ↓
        ┌──────┴────────┐
        │               │
        ↓               ↓
┌──────────────┐  ┌────────────────┐
│ Parser Cfg   │  │ Flow Rules     │
│ (Hardware)   │  │ (Hardware)     │
└──────────────┘  └────────────────┘
        │               │
        └───────┬───────┘
                ↓
        ┌──────────────┐
        │ DPA Programs │
        │ (Complex ops)│
        └──────────────┘
```

### Compilation Output

The DPL compiler generates:
1. **Parser configurations** → Hardware parser
2. **Match-action rules** → NIC flow engine
3. **Complex logic** → DPA programs
4. **Runtime API** → Control plane interface

## Basic DPL Example

### Simple L2 Forwarding

```p4
// headers.p4 - Define packet headers
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

header ipv4_t {
    bit<4>  version;
    bit<4>  ihl;
    bit<8>  tos;
    bit<16> totalLen;
    bit<16> identification;
    bit<3>  flags;
    bit<13> fragOffset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdrChecksum;
    bit<32> srcAddr;
    bit<32> dstAddr;
}

struct headers_t {
    ethernet_t ethernet;
    ipv4_t     ipv4;
}

struct metadata_t {
    bit<16> output_port;
}

// parser.p4 - Define parser
parser MyParser(
    packet_in packet,
    out headers_t hdr,
    inout metadata_t meta)
{
    state start {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }
}

// pipeline.p4 - Define pipeline
control MyIngress(
    inout headers_t hdr,
    inout metadata_t meta,
    inout standard_metadata_t std_meta)
{
    action forward(bit<16> port) {
        meta.output_port = port;
    }

    action drop() {
        mark_to_drop(std_meta);
    }

    table mac_forward {
        key = {
            hdr.ethernet.dstAddr: exact;
        }
        actions = {
            forward;
            drop;
        }
        size = 1024;
        default_action = drop;
    }

    apply {
        if (hdr.ethernet.isValid()) {
            mac_forward.apply();
        }
    }
}

// deparser.p4 - Define deparser
control MyDeparser(
    packet_out packet,
    in headers_t hdr)
{
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
    }
}

// main.p4 - Top level
V1Switch(
    MyParser(),
    verifyChecksum(),
    MyIngress(),
    MyEgress(),
    computeChecksum(),
    MyDeparser()
) main;
```

## Hardware Parser Programming

### Quick Answer

**Is DOCA DPL the only way to program the hardware parser?**

**YES**, for true custom parser programming. Here are your options:

| Method | Can Program Parser? | Complexity | Use Case |
|--------|---------------------|------------|----------|
| **DOCA DPL (P4)** | ✅ Yes (full custom) | High | Custom protocols |
| **Parser Profiles** | ⚠️ Limited presets | Low | Enable specific features |
| **rte_flow / DOCA Flow** | ❌ No | Low | Use existing parser |
| **DPA** | ❌ No (but can parse in software) | Medium | Parse after receiving |

### What the Parser Does

```
Packet arrives
    ↓
Hardware Parser (ASIC)
    ↓
Extracts headers:
  • Ethernet: src/dst MAC, ethertype
  • VLAN: tags, priorities
  • IP: src/dst addresses, protocol
  • TCP/UDP: ports, flags
  • Tunnels: VXLAN VNI, GRE keys
    ↓
Feeds metadata to Flow Engine
```

### Standard Parser Capabilities

**Without any programming**, the parser supports:

```
✅ Ethernet (802.1Q, 802.1ad multiple VLANs)
✅ IPv4 / IPv6
✅ TCP / UDP / ICMP
✅ VXLAN (standard port 4789)
✅ GRE
✅ GENEVE
✅ MPLS
✅ GTP
✅ IPsec ESP

❌ Custom protocols
❌ Non-standard encapsulations
❌ Proprietary headers
```

### Example: Custom Protocol Parser

```p4
// Define custom header
header my_custom_t {
    bit<16> magic;
    bit<16> version;
    bit<32> session_id;
    bit<16> payload_len;
}

// Custom parser state machine
parser MyParser(packet_in packet, out headers_t hdr) {
    state start {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x9999: parse_custom;  // Custom ethertype
            0x0800: parse_ipv4;
            default: accept;
        }
    }

    state parse_custom {
        packet.extract(hdr.my_custom);
        transition select(hdr.my_custom.magic) {
            0xDEAD: parse_inner_ipv4;
            default: accept;
        }
    }

    state parse_inner_ipv4 {
        packet.extract(hdr.inner_ipv4);
        transition accept;
    }
}
```

**Compilation**:
```bash
doca-p4c --target bf3 myparser.p4 -o myparser.json
```

### Parser Profiles (Limited Alternative)

Some parsing features can be enabled via firmware configuration:

```bash
# Enable MPLS parsing
mlxconfig -d /dev/mst/mt41686_pciconf0 set FLEX_PARSER_PROFILE_ENABLE=1

# Enable additional VLAN parsing
mlxconfig -d /dev/mst/mt41686_pciconf0 set MAX_VLAN_TAGS=2

# Apply changes (requires reboot)
mlxfwreset -d /dev/mst/mt41686_pciconf0 reset
```

**Limitations**:
- Only pre-defined profiles
- Cannot add new protocols
- Firmware-level changes only

## Advanced Example: Custom Header Processing

### Problem: Insert Custom Telemetry Header

```p4
// Define custom header
header telemetry_t {
    bit<32> timestamp;
    bit<16> queue_depth;
    bit<16> device_id;
}

struct headers_t {
    ethernet_t  ethernet;
    ipv4_t      ipv4;
    telemetry_t telemetry;  // Custom header
    tcp_t       tcp;
}

// Parser with custom protocol
parser MyParser(
    packet_in packet,
    out headers_t hdr,
    inout metadata_t meta)
{
    state start {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4;
            0x9999: parse_custom;  // Custom ethertype
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            6: parse_tcp;
            default: accept;
        }
    }

    state parse_custom {
        packet.extract(hdr.telemetry);
        transition parse_ipv4;
    }

    state parse_tcp {
        packet.extract(hdr.tcp);
        transition accept;
    }
}

// Insert telemetry header
control MyIngress(
    inout headers_t hdr,
    inout metadata_t meta,
    inout standard_metadata_t std_meta)
{
    action add_telemetry() {
        // Make telemetry header valid
        hdr.telemetry.setValid();

        // Set values
        hdr.telemetry.timestamp = (bit<32>)std_meta.ingress_global_timestamp;
        hdr.telemetry.queue_depth = (bit<16>)std_meta.enq_qdepth;
        hdr.telemetry.device_id = 0x1234;

        // Update ethertype
        hdr.ethernet.etherType = 0x9999;
    }

    table telemetry_enable {
        key = {
            hdr.ipv4.dstAddr: exact;
        }
        actions = {
            add_telemetry;
            NoAction;
        }
        default_action = NoAction;
    }

    apply {
        if (hdr.ipv4.isValid()) {
            telemetry_enable.apply();
        }
    }
}

// Deparser emits all headers
control MyDeparser(
    packet_out packet,
    in headers_t hdr)
{
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.telemetry);  // Custom header
        packet.emit(hdr.ipv4);
        packet.emit(hdr.tcp);
    }
}
```

## Stateful Processing in DPL

### Example: Per-Flow Packet Counter

```p4
control MyIngress(
    inout headers_t hdr,
    inout metadata_t meta,
    inout standard_metadata_t std_meta)
{
    // Define register array (stateful memory)
    register<bit<32>>(1024) flow_packet_count;

    action count_packet() {
        bit<32> count;
        bit<10> flow_id;

        // Calculate flow ID (hash of 5-tuple)
        hash(flow_id, HashAlgorithm.crc16,
             (bit<10>)0,
             { hdr.ipv4.srcAddr,
               hdr.ipv4.dstAddr,
               hdr.tcp.srcPort,
               hdr.tcp.dstPort,
               hdr.ipv4.protocol },
             (bit<10>)1024);

        // Read current count
        flow_packet_count.read(count, (bit<32>)flow_id);

        // Increment
        count = count + 1;

        // Write back
        flow_packet_count.write((bit<32>)flow_id, count);

        // Store in metadata for later use
        meta.packet_count = count;
    }

    apply {
        if (hdr.tcp.isValid()) {
            count_packet();
        }
    }
}
```

## Compilation and Deployment

### Compile DPL Program

```bash
# Compile P4 to DOCA DPL
doca-p4c \
    --target bf3 \
    --arch v1model \
    myapp.p4 \
    -o myapp.json

# Generates:
# - myapp.json: Runtime configuration
# - myapp_parser.bin: Parser configuration
# - myapp_dpa.bin: DPA programs
```

### Load Program at Runtime

```c
#include <doca_flow.h>

int main() {
    // Initialize DOCA Flow
    struct doca_flow_cfg cfg = {
        .pipe_queues = 4,
        .mode = DOCA_FLOW_MODE_SWITCH,
    };
    doca_flow_init(&cfg);

    // Load DPL program
    struct doca_flow_pipe_cfg pipe_cfg = {
        .attr = {
            .name = "DPL_PIPELINE",
            .type = DOCA_FLOW_PIPE_P4,
            .p4_file = "myapp.json",
        },
    };

    struct doca_flow_pipe *pipe;
    doca_flow_pipe_create(&pipe_cfg, NULL, NULL, &pipe);

    // Add table entries at runtime
    struct doca_flow_match match = {
        .outer_eth_dst = {0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff},
    };

    struct doca_flow_actions actions = {
        .meta = {
            .pkt_meta = 1,  // Set metadata
        },
    };

    doca_flow_pipe_add_entry(0, pipe, &match, &actions,
                             NULL, NULL, 0, NULL, NULL);

    return 0;
}
```

## DPL vs Direct Programming

### When to Use DPL

```
✅ Complex parsing requirements
✅ Multiple protocol layers
✅ Pipeline-style processing
✅ Want compiler to optimize placement
✅ Familiar with P4
✅ Standard SDN workflows
```

### When NOT to Use DPL

```
❌ Simple forwarding (use rte_flow directly)
❌ Need fine-grained control (use DPA)
❌ Performance-critical custom algorithms
❌ Debugging is important (DPL is harder to debug)
❌ Team unfamiliar with P4
```

## Debugging DPL Programs

### Enable Logging

```bash
# Compiler verbosity
doca-p4c --log-level debug myapp.p4

# Runtime debugging
DOCA_LOG_LEVEL=debug ./myapp
```

### Inspect Generated Code

```bash
# View parser configuration
doca-p4c-inspect myapp_parser.bin

# View flow rules
doca-flow-dump --pipe DPL_PIPELINE

# View DPA programs
objdump -d myapp_dpa.bin
```

### Common Issues

```p4
// ❌ BAD: Unsupported operation
action bad_action() {
    // Division not supported in hardware
    hdr.ipv4.ttl = hdr.ipv4.ttl / 2;
}

// ✅ GOOD: Use supported operations
action good_action() {
    // Decrement is supported
    hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
}
```

## Performance Considerations

### Hardware vs DPA Placement

```p4
// Compiler decides where to run each action

// Simple action → Hardware (line-rate)
action hw_action() {
    hdr.ipv4.ttl = hdr.ipv4.ttl - 1;  // TTL decrement
    // Runs at 400 Gbps in hardware
}

// Complex action → DPA (high-rate)
action dpa_action() {
    // Custom computation
    bit<32> result = complex_calc(hdr.tcp.seqNo);
    hdr.tcp.seqNo = result;
    // Runs at ~50-100 Gbps on DPA
}
```

## Key Takeaways

1. **DPL is P4-based** declarative language for packet processing
2. **Compiler decides placement** (hardware vs DPA)
3. **Best for complex pipelines** with multiple protocol layers
4. **Custom parser** programming requires DPL (can't use rte_flow)
5. **Only way to program hardware parser** for custom protocols
6. **Stateful processing** possible with registers
7. **Harder to debug** than direct programming
8. **Coexists with rte_flow and DPA** in same system

## Next Steps
- See [DPA Programming](dpa-programming.md) for comparison with imperative approach
- Read [DOCA Flow API](doca-flow-api.md) for runtime flow programming
- Check [../04-development/code-examples.md](../04-development/code-examples.md) for complete programs
- Review [../01-architecture/packet-pipeline.md](../01-architecture/packet-pipeline.md) for understanding packet flow
