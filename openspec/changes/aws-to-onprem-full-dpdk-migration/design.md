## Context

The ClientNIC DPDK implementation uses a hybrid I/O model forced by AWS constraints: eth1 (server-facing, secondary ENI) uses DPDK ENA PMD for kernel-bypass, while eth0 (client-facing, primary ENI) uses AF_PACKET because AWS prevents unbinding the primary ENI from the kernel driver. The I/O layer is already well-abstracted behind `eth0_io` / `eth1_io` structs in `io.h`, and the pipeline, flow table, translator, and packet processor are all I/O-agnostic. On bare-metal on-prem hardware both NICs can be bound to vfio-pci, and a single NIC with VLAN-trunked queue pairs can serve both directions.

## Goals / Non-Goals

**Goals:**
- Replace AF_PACKET on eth0 with a DPDK PMD port (full kernel bypass on both interfaces)
- Handle ARP in-pipeline for both interfaces (kernel no longer manages either NIC)
- Support an optional single-NIC / two-queue-pair mode using VLAN trunking
- Remove the `install_iptables()` RST suppression dependency
- Preserve the `pipeline_feed_eth0(uint8_t*, uint16_t)` signature unchanged

**Non-Goals:**
- Changing pipeline logic, flow table, translator, or packet processor
- Multi-lcore / RSS scaling (single-core poll loop is sufficient for the demo)
- Production hardening (jumbo frames, multi-segment mbufs, NUMA-per-flow pinning)
- Changing the servernic implementation

## Decisions

### D1: `eth0_io` struct gains DPDK fields; AF_PACKET fields removed
`eth0_io` will be restructured to mirror `eth1_io` (port_id + mbuf_pool + mac + gw_mac). `eth0_recv` will call `rte_eth_rx_burst`; `eth0_send` will allocate an mbuf and call `rte_eth_tx_burst`. The raw `uint8_t*` API surface (`eth0_recv` returns bytes into a caller buffer, `eth0_send` takes a flat buffer) is preserved so `pipeline_feed_eth0` needs no changes.

**Alternative considered**: Unify `eth0_io` and `eth1_io` into a single `dpdk_port_io` struct. Rejected — unnecessary abstraction for a two-port demo; keeping separate structs preserves the naming clarity of "client-facing" vs "server-facing".

### D2: ARP handled in `pipeline.c` before TCP dispatch
Both `pipeline_feed_eth0` and `pipeline_feed_eth1` will check ethertype before the existing TCP path: if ARP, call `arp_handle()` which constructs and sends a reply in-place. ARP logic lives in a new `arp.c` / `arp.h`.

**Alternative considered**: Handle ARP inside `io.c` recv path. Rejected — io.c should remain a thin I/O shim; ARP is application-level packet handling and belongs in the pipeline layer.

### D3: RST suppression moved to pipeline software drop
In `pipeline_feed_eth0`, after the SYN check, add a flag check: if TCP RST flag set, drop silently. This replaces the `iptables -A OUTPUT -p tcp --tcp-flags RST RST -j DROP` rule.

**Alternative considered**: Keep iptables even on bare metal as a safety net. Rejected — with full DPDK the kernel never sees these packets, so iptables has no effect. The rule is dead code and should be removed cleanly.

### D4: Single-NIC VLAN mode as a compile-time / runtime flag
When `--single-nic` is passed, both "eth0" and "eth1" map to DPDK port 0, queue 0 and queue 1 respectively. DPDK VLAN filtering steers client-tagged frames to queue 0 and server-tagged frames to queue 1. The `eth0_io` and `eth1_io` structs remain separate; only `port_id` differs (or is the same with different queue indices).

**Alternative considered**: Always use two ports, ignore single-NIC. Rejected — this is the primary on-prem performance target and should be a supported mode.

## Risks / Trade-offs

- **ARP race at startup**: If a packet arrives before the ARP table is warm, the first frame(s) to an unknown MAC will be dropped. → Mitigation: send gratuitous ARP on both interfaces at init, and/or pre-populate neighbor MACs via CLI args (as `--gw-mac` already does for eth1).
- **VLAN config mismatch**: Single-NIC mode requires the upstream switch to be configured for 802.1Q trunking on that port. Wrong VLAN IDs = silent traffic loss. → Mitigation: log the configured VLANs at startup; add a CLI validation step in the README.
- **mbuf exhaustion under eth0 TX**: `eth0_send` will need to allocate mbufs from the shared pool. Under heavy spoofed SYN-ACK traffic this could exhaust the pool. → Mitigation: size `MBUF_POOL_SIZE` appropriately; add a pool exhaustion log warning.
- **`pipeline_feed_eth0` still takes `uint8_t*`**: The DPDK mbuf received on eth0 must be linearized into a stack buffer before calling the pipeline. This is a memcpy per packet on the eth0 path. Acceptable for now; the hot path (data forwarding) mostly hits eth1.

## Migration Plan

1. Bind both NICs to vfio-pci before launching (`dpdk-devbind.py --bind vfio-pci <PCI-addr>`)
2. Remove iptables rules from server startup scripts (no longer needed)
3. Launch with updated CLI: `--client-port <DPDK port id>` in addition to existing `--port` / `--gw-mac`
4. For single-NIC mode: configure switch VLAN trunk, pass `--single-nic --client-vlan <id> --server-vlan <id>`

**Rollback**: The Scapy implementation in `clientnic/scapy/` is unaffected and remains a working fallback.

## Open Questions

- Should `eth0_send` allocate mbufs from the same shared pool as eth1, or a dedicated eth0 TX pool? (Separate pool avoids cross-interface starvation but adds config complexity.)
- For single-NIC VLAN mode, should VLAN stripping be enabled in DPDK (frames arrive without VLAN header) or should the pipeline strip/insert tags explicitly? DPDK hardware offload is cleaner but less portable across NIC models.
