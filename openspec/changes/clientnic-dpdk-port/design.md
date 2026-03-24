## Context

The ClientNIC Scapy app (`clientnic/scapy/`) implements the 0-RTT TCP middleware using Python/Scapy over AF_PACKET raw sockets. It works correctly but adds per-packet Python interpreter overhead. The DPDK infrastructure is already provisioned on c5n.large instances: DPDK 23.11 built from source, hugepages (512×2MB), vfio-pci no-IOMMU mode, and eth1 bound to the ENA PMD.

**Critical constraint**: eth0 must remain kernel-managed for SSM session access. Only eth1 is DPDK-bound.

## Goals / Non-Goals

**Goals:**
- Port the full 0-RTT pipeline to C/DPDK with identical wire-level behavior
- Use DPDK kernel-bypass (ENA PMD) for the server-facing eth1 interface
- Maintain the same Parse → Decide → Modify → Send architecture
- Produce a single binary buildable with `meson setup build && ninja -C build`
- Pass existing integration tests (`validate_0rtt_capture.py`) without modification

**Non-Goals:**
- Multi-core / multi-queue scaling (single-core poll loop is sufficient for POC)
- TCP options handling (timestamps, SACK, window scaling) — same limitation as Scapy version
- Replacing the Scapy version (it stays as reference)
- Modifying ServerNIC, Client, or Server apps
- Hardware offload (checksum offload, TSO) — compute in software for correctness visibility

## Decisions

### 1. Hybrid I/O: AF_PACKET for eth0, DPDK ENA PMD for eth1

**Choice**: Use a non-blocking `AF_PACKET SOCK_RAW` socket in C for eth0, and `rte_eth_rx/tx_burst()` for eth1.

**Alternatives considered:**
- *KNI (Kernel NIC Interface)*: Removed in DPDK 23.11 — not available
- *AF_PACKET PMD*: DPDK can wrap kernel interfaces via AF_PACKET PMD, but adds EAL complexity for a low-volume path
- *TAP PMD*: Requires a tap device and bridging — unnecessary complexity

**Rationale**: eth0 handles low-volume control traffic (SYN, spoofed SYN-ACK, translated data). Raw socket overhead is negligible. This keeps SSM management completely untouched and avoids any DPDK interaction with the kernel NIC.

### 2. Single-threaded busy-poll loop

**Choice**: One `for(;;)` loop alternating between `recvfrom()` (eth0, non-blocking) and `rte_eth_rx_burst()` (eth1).

**Rationale**: Mirrors the Scapy single-threaded model. c5n.large has 2 vCPUs — one for the poll loop, one for kernel/SSM. No synchronization needed, no locks on the flow table hot path.

### 3. Simple open-addressing hash table for flow table

**Choice**: Fixed-size (1024-slot) open-addressing hash table with linear probing. XOR-fold 4-tuple for hash.

**Alternatives considered:**
- *rte_hash*: Full-featured DPDK hash library, but adds API surface for no benefit at POC scale
- *Dynamic hash map*: Unnecessary — POC tests <10 concurrent flows

**Rationale**: Minimal code, zero external dependencies beyond stdlib. Easy to unit test in isolation.

### 4. Gateway MAC via CLI argument

**Choice**: The middle subnet gateway MAC is passed as `--gw-mac=AA:BB:CC:DD:EE:FF` on the command line.

**Alternatives considered:**
- *ARP over DPDK*: Send ARP request on eth1, parse reply — adds ~50 lines of protocol handling
- *Read /proc/net/arp*: eth1 is already unbound from kernel before app starts — no entry

**Rationale**: The startup script can resolve the gateway MAC via `arp -n` or `ip neigh` before DPDK binding. Simplest approach for a POC.

### 5. L2 sends on eth0 with cached client MAC

**Choice**: Cache the client's MAC address from the incoming SYN in the flow entry. All eth0 sends (spoofed SYN-ACK, translated s2c data) use `sendto()` on the AF_PACKET socket with explicit Ethernet headers.

**Rationale**: Avoids needing a separate L3 raw socket. The client MAC is always available from the first SYN packet. Equivalent to Scapy's `sendp()` behavior.

### 6. Module structure mirrors Scapy layout

**Choice**: 1:1 file mapping from Python to C modules.

| Scapy | DPDK (C) |
|-------|----------|
| `main.py` | `main.c` |
| `src/pipeline.py` | `pipeline.c/h` |
| `src/utils/flow_table.py` | `flow_table.c/h` |
| `src/utils/packet_processor.py` | `packet_processor.c/h` |
| `src/utils/translator.py` | `translator.c/h` |
| `src/utils/logger.py` | `log.c/h` |
| — | `io.c/h` (new: I/O abstraction) |
| — | `checksum.c/h` (new: explicit checksum helpers) |

**Rationale**: Developers familiar with the Scapy version can navigate the C code immediately. Same mental model, same function responsibilities.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| AF_PACKET raw socket may drop packets under high eth0 load | Acceptable for POC — eth0 is low-volume (connection setup only). Production would use AF_PACKET PMD or move both NICs to DPDK. |
| ENA PMD TX descriptor cleanup | Set `tx_free_thresh` in TX queue config. ENA requires explicit cleanup thresholds. |
| SYN forwarding requires mbuf allocation + copy | Allocate from mempool, copy raw eth0 buffer into mbuf, rewrite Ether header. One allocation per SYN — negligible. |
| Spoofed SYN-ACK has no TCP options (MSS, window scale, timestamps) | Same limitation as Scapy version. Clients may fall back to defaults (MSS 536). Acceptable for POC. |
| Gateway MAC changes if infrastructure redeployed | Startup script re-resolves MAC each time. Could add periodic ARP refresh in future. |
| No flow table cleanup / timeout | POC runs short-lived tests. Production would need a timer-based eviction. |
