# Option 1 Implementation - FIXED for Hardware Fast-Path

## What Was Wrong

The original code used `DOCA_FLOW_FWD_RSS` for non-SYN packets, which would send them to multiple RX queues on the SAME port. This doesn't work for bump-in-the-wire!

```c
// ❌ WRONG (original):
fwd_miss.type = DOCA_FLOW_FWD_RSS;  // Sends to RSS queues, NOT to opposite port
```

## What's Fixed

Now uses `DOCA_FLOW_FWD_PORT` to forward non-SYN packets to the opposite port **in hardware**:

```c
// ✅ CORRECT (fixed):
fwd_miss.type = DOCA_FLOW_FWD_PORT;
fwd_miss.port_id = opposite_port_id;  // Hardware forwards to opposite port!
```

**Key file: `src/doca_flow_handler.c` line 117-118**

## Architecture - Option 1 (No OVS, Hardware Hairpin)

```
                    ┌─────────────────────────────────┐
                    │   BlueField-3 eSwitch (Hardware)│
                    │                                 │
Host VM             │    Port A (pf0hpf)              │        Port B (p0)           Tofino
  │                 │         │                       │           │                    │
  │    TCP SYN      │         ▼                       │           │                    │
  ├────────────────►│───► Queue 0 (ARM cores)        │           │                    │
  │                 │         │                       │           │                    │
  │                 │    [syn_punt app]               │           │                    │
  │                 │         │                       │           │                    │
  │                 │         └───────────────────────┼───────────┼───────────────────►│
  │                 │                                 │           │                    │
  │                 │                                 │           │                    │
  │  TCP non-SYN    │                                 │           │                    │
  ├────────────────►│──────────[HARDWARE FORWARD]────┼───────────┼───────────────────►│
  │                 │         (NO ARM CORES!)         │           │                    │
  │                 │                                 │           │                    │
  │                 │                                 │      TCP non-SYN               │
  │                 │         (HARDWARE FORWARD)      │           │                    │
  │◄────────────────┼──────────────────────────────────┼───────────┼────────────────────┤
  │                 │         (NO ARM CORES!)         │           │                    │
  │                 │                                 │           │                    │
  │   TCP SYN       │                            Queue 0 (ARM)    │                    │
  │◄────────────────┼──────────────────────────────┼──────◄──────┼────────────────────┤
  │                 │                          [syn_punt app]     │                    │
  │                 │                                 │           │                    │
                    └─────────────────────────────────┘
```

### Packet Flows

#### Flow 1: SYN Packet (Host → Tofino)
```
1. Host VM sends SYN packet → pf0hpf (Port A)
2. eSwitch matches SYN flag → Punts to Queue 0 (ARM cores)
3. syn_punt app receives on Queue 0:
   - Parses packet
   - Prints to stdout
   - Forwards via rte_eth_tx_burst(port_b)
4. Packet exits p0 (Port B) → Tofino
```

**Latency**: ~10-50 µs (software processing)

#### Flow 2: Non-SYN Packet (Host → Tofino)
```
1. Host VM sends non-SYN packet → pf0hpf (Port A)
2. eSwitch miss (no SYN) → HARDWARE FORWARD to Port B
3. ⚡ Packet NEVER touches ARM cores! ⚡
4. Packet exits p0 (Port B) → Tofino
```

**Latency**: ~1 µs (pure hardware forwarding)

#### Flow 3: Reverse Direction (Tofino → Host)
Same logic applies in reverse:
- SYN from p0 → Queue 0 → ARM → pf0hpf
- Non-SYN from p0 → Hardware forward → pf0hpf

## Key Code Changes

### 1. `src/doca_flow_handler.c` (✅ FIXED)

**Critical function: `create_hairpin_pipe()`**

```c
/* Non-SYN packets: Forward to opposite port in HARDWARE */
fwd_miss.type = DOCA_FLOW_FWD_PORT;  // ← THIS IS THE KEY!
fwd_miss.port_id = opposite_port_id;
```

Creates two pipes:
- **Pipe A** (on pf0hpf): SYN → Queue 0, Miss → Forward to p0 (hardware)
- **Pipe B** (on p0): SYN → Queue 0, Miss → Forward to pf0hpf (hardware)

### 2. `src/utils.h` (✅ UPDATED)

Now supports two ports:
```c
struct syn_punt_config {
    uint16_t port_a_id;  // pf0hpf
    uint16_t port_b_id;  // p0
    ...
};

struct doca_flow_ctx {
    struct doca_flow_port *port_a;
    struct doca_flow_port *port_b;
    struct doca_flow_pipe *pipe_a;
    struct doca_flow_pipe *pipe_b;
    ...
};
```

### 3. Remaining Files to Update

**You need to update these files** (I'll provide code snippets below):

- `src/dpdk_init.{c,h}` - Initialize both ports
- `src/packet_processor.c` - Read from both ports' queue 0
- `src/main.c` - Pass two port IDs

## Complete Initialization Sequence

```
1. rte_eal_init()
2. dpdk_port_init(port_a_id)  // Initialize pf0hpf
3. dpdk_port_init(port_b_id)  // Initialize p0
4. doca_flow_init_module()
5. doca_flow_port_start_module(ctx, port_a_id, port_b_id)
6. create_syn_punt_pipe(ctx, port_a_id, port_b_id)  // Creates hairpin pipes
7. add_syn_punt_entry(ctx)  // Commits to hardware
8. packet_processor_run(ctx)  // Poll queue 0 on both ports
```

## Testing Commands

### Find Your Port IDs
```bash
# Method 1: List with application
sudo ./build/syn_punt -l 0-1 -a 03:00.0 -- --list

# Method 2: Use DPDK testpmd
dpdk-testpmd -l 0-1 -a 03:00.0 -- --list

# Expected output:
#   Port 0: pf0hpf (representor)
#   Port 1: p0 (physical)
```

### Run Application
```bash
# Bind to BOTH ports
sudo ./build/syn_punt \
    -l 0-1 \
    -a 03:00.0 \
    -- \
    --port-a 0 \
    --port-b 1
```

### Test from Host VM
```bash
# Send SYN packets (should be printed by app)
hping3 -S -p 80 <tofino_ip> -c 10

# Send non-SYN packets (should be SILENT - fast-forwarded)
hping3 -A -p 80 <tofino_ip> -c 1000

# Check application output
# Expected:
#   10 SYN packets printed
#   0 non-SYN packets printed
#   Statistics: Total=1010, SYN=10
```

## Verify Fast-Path Works

```bash
# On DPU - Monitor eSwitch statistics
ethtool -S p0 | grep hw

# Should show hardware forwarded packets for non-SYN
# ARM CPU usage should be LOW for non-SYN traffic
```

## Performance Expectations

| Packet Type | Path | Latency | Throughput | CPU Usage |
|-------------|------|---------|------------|-----------|
| **SYN** | Software (ARM) | ~10-50 µs | ~1M pps/core | High |
| **Non-SYN** | Hardware (eSwitch) | ~1 µs | Line rate (25 Gbps) | **ZERO** |

## Critical Success Criteria

✅ **Non-SYN packets MUST NOT appear in application output**
✅ **CPU usage should be LOW when sending non-SYN traffic**
✅ **Non-SYN throughput should be line-rate (hardware)**
✅ **SYN packets should be printed with full details**

## No OVS Required!

**Option 1 does NOT need OVS bridges!** The hairpin forwarding happens entirely in the eSwitch hardware:

```
pf0hpf ←[eSwitch hardware]→ p0
          ↑
    DOCA Flow rules
    (programmed once at startup)
```

The application just needs:
1. Bind to both ports via DPDK
2. Create DOCA Flow hairpin pipes
3. Poll queue 0 for SYN packets

**That's it!** No kernel, no OVS, pure hardware fast-path for non-SYN packets.

## Summary

**What makes Option 1 work correctly:**

1. **Two ports**: Application binds to both pf0hpf and p0
2. **DOCA_FLOW_FWD_PORT**: Non-SYN packets forwarded to opposite port in hardware
3. **Queue 0 punt**: Only SYN packets reach ARM cores
4. **Hairpin pipes**: One pipe per port, each forwarding to the other
5. **No OVS**: Hardware forwarding via eSwitch, no kernel involvement

**Result:** ⚡ Line-rate forwarding for non-SYN packets with ZERO ARM core involvement! ⚡
