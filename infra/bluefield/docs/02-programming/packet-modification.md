# Packet Modification and Generation

This document is combined from packet modification and packet generation capabilities.

## Capability Matrix

| Modification | NIC Flow Engine | DPA | ARM (DPDK) |
|--------------|-----------------|-----|------------|
| **MAC Address** | ✅ Yes | ✅ Yes | ✅ Yes |
| **IP Address (NAT)** | ✅ Yes | ✅ Yes | ✅ Yes |
| **TCP/UDP Ports (PAT)** | ✅ Yes | ✅ Yes | ✅ Yes |
| **VLAN Push/Pop** | ✅ Yes | ✅ Yes | ✅ Yes |
| **TTL Decrement** | ✅ Yes | ✅ Yes | ✅ Yes |
| **TCP Seq/Ack Numbers** | ❌ No | ✅ Yes | ✅ Yes |
| **TCP Window Size** | ❌ No | ✅ Yes | ✅ Yes |
| **TCP Flags** | ❌ No | ✅ Yes | ✅ Yes |
| **VXLAN Encap/Decap** | ✅ Yes | ✅ Yes | ✅ Yes |
| **GRE Encap/Decap** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Custom Headers** | ❌ No | ✅ Yes | ✅ Yes |
| **Packet Generation** | ❌ No | ✅ Yes | ✅ Yes |
| **Checksums** | ✅ Auto | ✅ Manual | ✅ Manual/Auto |

## NIC Flow Engine: What Can Be Modified

The flow engine supports standard modifications only. See [DOCA Flow API](doca-flow-api.md) for examples of NAT, VLAN, and tunnel operations.

**What CANNOT be modified**:
- TCP sequence/acknowledgment numbers
- TCP flags
- Custom protocol headers
- Packet generation

## DPA: Full Packet Control

DPA has complete access to packet memory and can modify any field or generate packets from scratch.

### Example: TCP Sequence Number Modification

See the TCP modifier example in [DPA Programming](dpa-programming.md).

### Example: Packet Generation

```c
__dpa_global__ struct rte_mbuf *generate_synack(struct rte_mbuf *syn_pkt) {
    struct rte_mbuf *synack = rte_pktmbuf_alloc(pool);

    // Parse SYN headers
    struct rte_ether_hdr *syn_eth = rte_pktmbuf_mtod(syn_pkt, struct rte_ether_hdr *);
    struct rte_ipv4_hdr *syn_ip = (struct rte_ipv4_hdr *)(syn_eth + 1);
    struct rte_tcp_hdr *syn_tcp = (struct rte_tcp_hdr *)(syn_ip + 1);

    // Build SYN-ACK (swap addresses, set flags)
    // ... implementation details ...

    return synack;
}
```

## Decision Tree

```
Need to modify packets?
    ├─ Standard (MAC/IP/Port/VLAN)? → NIC Flow Engine (400 Gbps)
    ├─ TCP seq/ack or custom? → DPA (50-100 Gbps) or ARM (10-20 Gbps)
    └─ Generate packets? → DPA or ARM only
```

## Key Takeaways

1. **Flow engine**: Standard modifications at line-rate
2. **DPA**: Any modification + packet generation at high rate
3. **ARM**: Full flexibility at moderate rate
4. **Packet generation**: Only DPA or ARM (not flow engine)

## Next Steps
- See [DPA Programming](dpa-programming.md) for custom modifications
- Read [DOCA Flow API](doca-flow-api.md) for hardware modifications
- Check [../04-development/code-examples.md](../04-development/code-examples.md) for complete examples
