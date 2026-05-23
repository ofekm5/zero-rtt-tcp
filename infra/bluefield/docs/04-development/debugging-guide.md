# Debugging Guide

## Common Issues and Solutions

### Issue 1: Packets Not Forwarded

**Symptoms**: Packets arrive but don't reach destination

**Debug Steps**:
```bash
# Check if packets arriving
tcpdump -i p0 -c 10

# Check flow rules
ovs-appctl dpctl/dump-flows

# Check hardware offload status
ovs-appctl dpctl/dump-flows type=offloaded

# Check hardware counters
ethtool -S p0 | grep -E "rx_|tx_|drop"
```

**Common Causes**:
- No matching flow rule
- Rule not offloaded to hardware
- Port representor misconfigured
- Firewall blocking traffic

### Issue 2: Low Performance

**Symptoms**: Throughput much lower than expected

**Debug Steps**:
```bash
# Check CPU usage
top -p $(pgrep dpdk-app)

# Check if hardware offload is working
ovs-appctl dpctl/dump-flows type=offloaded

# Check packet drops
ethtool -S p0 | grep drop

# Check NUMA placement
numactl --hardware
```

**Common Causes**:
- Rules not offloaded (running in software)
- NUMA mismatch (cross-socket memory access)
- Queue size too small
- No CPU core pinning

### Issue 3: High Packet Loss

**Symptoms**: Many packets dropped

**Debug Steps**:
```bash
# Check drop counters
ethtool -S p0 | grep drop

# Check queue utilization
cat /proc/net/pktgen/p0

# Check flow table capacity
mlxdump -d <device> fsdump --type FT
```

**Common Causes**:
- Flow table full
- Queue overflow
- Burst traffic exceeding capacity
- Application not polling fast enough

### Issue 4: Flow Rules Not Working

**Symptoms**: rte_flow_create() succeeds but packets not matched

**Debug Steps**:
```c
// Add counter to debug
struct rte_flow_action actions[] = {
    { .type = RTE_FLOW_ACTION_TYPE_COUNT },
    { .type = RTE_FLOW_ACTION_TYPE_PORT_ID, .conf = &port },
    { .type = RTE_FLOW_ACTION_TYPE_END }
};

// Query counter
struct rte_flow_query_count count;
rte_flow_query(port, flow, &count, &error);
printf("Hits: %lu\n", count.hits);
```

**Common Causes**:
- Pattern doesn't match (wrong MAC/IP)
- Priority conflict (lower priority rule matching first)
- Rule not offloaded (check with ovs-appctl)
- Parser not extracting expected headers

## Debugging Tools

### tcpdump

```bash
# Basic packet capture
tcpdump -i p0 -nn

# Capture specific protocol
tcpdump -i p0 tcp port 80

# Save to file
tcpdump -i p0 -w capture.pcap

# Read from file
tcpdump -r capture.pcap
```

### ethtool

```bash
# Show statistics
ethtool -S p0

# Show NIC settings
ethtool p0

# Change ring sizes
ethtool -G p0 rx 4096 tx 4096
```

### mlxdump

```bash
# Dump flow tables
mlxdump -d /dev/mst/mt41686_pciconf0 fsdump --type FT

# Dump specific table
mlxdump -d /dev/mst/mt41686_pciconf0 fsdump --type FT --gvmi=0
```

## Logging and Tracing

### DPDK Logging

```c
// Enable debug logs
rte_log_set_level(RTE_LOGTYPE_USER1, RTE_LOG_DEBUG);

// Log messages
RTE_LOG(INFO, USER1, "Received %u packets\n", nb_rx);
```

### DOCA Logging

```bash
# Set log level
export DOCA_LOG_LEVEL=debug

# Enable specific component
export DOCA_LOG_COMPONENT=DOCA_FLOW:debug
```

### OVS Logging

```bash
# Enable debug logging
ovs-appctl vlog/set dpif_netlink_offload:dbg
ovs-appctl vlog/set dpif:dbg

# View logs
journalctl -u openvswitch -f
```

## Performance Profiling

### perf

```bash
# Profile DPDK application
perf record -g ./dpdk-app
perf report

# Check cache misses
perf stat -e cache-misses ./dpdk-app
```

### DPA Profiling

```c
__dpa_global__ void profiled_function(void) {
    uint64_t start = dpa_get_cycles();
    
    // Function to profile
    process_packet(pkt);
    
    uint64_t end = dpa_get_cycles();
    dpa_printf("Cycles: %lu\n", end - start);
}
```

## Common Error Messages

### "Flow rule creation failed: Not supported"

**Cause**: Attempting unsupported action
**Solution**: Simplify rule or use DPA

### "Port not found"

**Cause**: Incorrect port representor
**Solution**: Verify with `ip link show`

### "No space left"

**Cause**: Flow table full
**Solution**: Age out old flows, increase capacity

### "Resource temporarily unavailable"

**Cause**: Queue full or busy
**Solution**: Increase queue size, add backpressure

## Key Debugging Commands

```bash
# Everything about interfaces
ip link show
ip addr show
ethtool -S p0

# Flow rules
ovs-appctl dpctl/dump-flows
ovs-appctl dpctl/dump-flows type=offloaded

# Hardware status
mlxdump -d <device> fsdump --type FT

# System resources
top
mpstat -P ALL 1
numactl --hardware

# Packet capture
tcpdump -i p0 -nn
```
