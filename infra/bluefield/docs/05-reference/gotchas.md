# Common Gotchas and Pitfalls

## Things Claude Often Gets Wrong

This guide documents common misconceptions about BlueField-3 architecture and programming.

### 1. "Queue" is Not a Socket

**Wrong**: "Packets are sent through queues like network sockets"

**Correct**: Queues are ring buffers in memory containing packet descriptors. They are NOT communication endpoints.

```
❌ Thinking: Queue = socket/pipe between components
✅ Reality: Queue = circular buffer of packet pointers
```

### 2. eSwitch is Not Separate Hardware

**Wrong**: "The eSwitch is a separate chip or component"

**Correct**: The eSwitch is part of the NIC flow engine logic, not separate hardware. It's implemented in the same ASIC that handles packet processing.

```
❌ Thinking: Physical Port → eSwitch Hardware → ARM
✅ Reality: eSwitch is flow engine logic in NIC ASIC
```

### 3. Representors vs Netdevs Confusion

**Wrong**: "Use the SF representor in DPDK applications"

**Correct**:
- **SF Netdev** (e.g., `enp3s0f0s2`) → Bind to DPDK/DOCA applications
- **SF Representor** (e.g., `en3f0pf0sf2`) → Add to OVS bridges

```
❌ rte_eth_dev_get_port_by_name("en3f0pf0sf2", &port);  // Representor
✅ rte_eth_dev_get_port_by_name("enp3s0f0s2", &port);   // Netdev
```

### 4. Hardware Parser Programming

**Wrong**: "I can program the parser with rte_flow"

**Correct**: Only DOCA DPL (P4) can program the hardware parser for custom protocols. rte_flow uses the existing parser.

```
❌ rte_flow_create() with custom protocol
✅ DOCA DPL P4 program for custom protocol parsing
```

### 5. DPA is Not Software on ARM

**Wrong**: "DPA programs run on the ARM cores"

**Correct**: DPA is programmable hardware (dedicated cores), separate from ARM. DPA provides ~50-100 Gbps, ARM provides ~10-20 Gbps/core.

```
❌ DPA = ARM software
✅ DPA = Dedicated programmable hardware cores
```

### 6. Shared Memory Between Host and DPU

**Wrong**: "Queues are in shared memory accessible by both host and DPU"

**Correct**: ARM and Host have completely separate memory spaces. DMA is point-to-point:
- Host queues → Host DDR
- ARM queues → ARM DDR

```
❌ Shared queue memory
✅ Separate memory spaces + DMA transfers
```

### 7. TCP Sequence Number Modification

**Wrong**: "Use rte_flow actions to modify TCP seq numbers"

**Correct**: NIC flow engine cannot modify TCP seq/ack. You must use DPA or ARM for this.

```
❌ RTE_FLOW_ACTION_TYPE_SET_TCP_SEQ (doesn't exist)
✅ DPA program to modify TCP fields manually
```

### 8. Hairpin Queue Misconception

**Wrong**: "Hairpin queues are faster because they use special memory"

**Correct**: Hairpin is fast because packets never leave NIC hardware - no DMA to external memory at all.

```
❌ Hairpin = special fast memory
✅ Hairpin = packets stay in NIC, never DMA'd
```

### 9. Flow Table Capacity

**Wrong**: "I can install millions of flow rules"

**Correct**: Hardware flow tables have limited capacity (typically 10k-100k rules depending on complexity). Age out old flows or use software fallback.

```
❌ Unlimited hardware flows
✅ Limited hardware capacity, need aging/eviction
```

### 10. Packet Generation in Hardware

**Wrong**: "Create flow rule to generate SYN-ACK responses"

**Correct**: NIC flow engine cannot generate packets. Only DPA or ARM can create new packets.

```
❌ rte_flow actions to generate packets
✅ DPA or ARM to build packets from scratch
```

### 11. OVS Always Required

**Wrong**: "DOCA applications must use OVS"

**Correct**: DOCA apps with direct SF access don't need OVS. OVS is for VM networking and mixed environments.

```
❌ DOCA app → OVS → Hardware
✅ DOCA app → SF netdev → Hardware directly
```

### 12. Offload Verification

**Wrong**: "If rte_flow_create() succeeds, the rule is offloaded"

**Correct**: Rule creation success doesn't guarantee hardware offload. Always verify with counters or OVS commands.

```
❌ Assume offload after rte_flow_create()
✅ Verify with: ovs-dpctl dump-flows type=offloaded
```

### 13. RSS and Flow Director Confusion

**Wrong**: "RSS is the same as flow steering"

**Correct**:
- **RSS**: Automatic hash-based distribution across queues
- **Flow Director**: Explicit per-flow queue assignment

```
❌ RSS = manual flow steering
✅ RSS = automatic, Flow Director = manual
```

### 14. Checksum Offload Assumptions

**Wrong**: "All packet modifications auto-update checksums"

**Correct**:
- NIC flow engine: Checksums updated automatically
- DPA: Must calculate checksums manually
- ARM: Can use manual or hardware offload

```
❌ Checksums always automatic
✅ Depends on where modification happens
```

### 15. Performance Expectations

**Wrong**: "DPA should achieve line-rate 400 Gbps"

**Correct**: Performance targets:
- NIC Flow Engine: 400 Gbps (line-rate)
- DPA: 50-100 Gbps (high-rate programmable)
- ARM: 10-20 Gbps per core (flexible)

```
❌ DPA = 400 Gbps
✅ DPA = 50-100 Gbps (still very fast!)
```

## Debugging Checklist

When something doesn't work, check:

1. ✅ Using SF netdev (not representor) for DPDK?
2. ✅ Flow rule actually offloaded to hardware?
3. ✅ Trying to do unsupported operation in hardware?
4. ✅ Hugepages allocated and mounted?
5. ✅ Queues in correct memory space (host vs ARM)?
6. ✅ Hardware flow table not full?
7. ✅ Parser supports the protocol?
8. ✅ Checksum recalculation if modifying with DPA?

## Quick Fixes

| Problem | Common Cause | Solution |
|---------|-------------|----------|
| Packets not forwarded | No matching flow rule | Check `ovs-dpctl dump-flows` |
| Low performance | Not hardware-offloaded | Verify with `type=offloaded` |
| DPDK init fails | No hugepages | Allocate hugepages |
| Flow creation fails | Unsupported action | Use DPA instead |
| Packets dropped | Flow table full | Age out old flows |

## Key Takeaways

1. **Queues are buffers**, not sockets
2. **eSwitch is logic**, not hardware
3. **Representors for OVS**, netdevs for DPDK
4. **Parser programming** requires DPL/P4
5. **DPA is hardware**, not ARM software
6. **No shared memory** between host and DPU
7. **TCP seq/ack** needs DPA or ARM
8. **Hairpin bypasses memory** entirely
9. **Verify offload** explicitly
10. **Packet generation** needs DPA/ARM

## Next Steps
- Review [../01-architecture/](../01-architecture/) for architecture fundamentals
- Check [../04-development/debugging-guide.md](../04-development/debugging-guide.md) for troubleshooting
- See specific programming guides in [../02-programming/](../02-programming/)
