## Why

The current ClientNIC DPDK implementation uses a hybrid I/O model: eth1 (server-facing) uses DPDK ENA PMD for kernel-bypass performance, while eth0 (client-facing) falls back to AF_PACKET raw sockets due to AWS restricting the primary ENI from being unbound from the kernel driver. On bare-metal on-prem hardware, this restriction does not exist — both interfaces can be bound to vfio-pci, and a single NIC with two VLAN-tagged queue pairs can replace two separate NICs entirely.

## What Changes

- **eth0 I/O backend**: Replace AF_PACKET raw socket (`socket(AF_PACKET, SOCK_RAW, ...)`) with a second DPDK port (or queue pair on a single NIC), using `rte_eth_rx_burst` / `rte_eth_tx_burst`
- **Main poll loop**: Replace the `eth0_recv` (blocking/non-blocking recvfrom) path with a DPDK rx burst call, matching the existing eth1 poll pattern
- **iptables RST suppression**: Remove `install_iptables()` call — with full kernel bypass the kernel never sees the packets; RST drops move into the pipeline in software
- **ARP handling**: Add ARP request/reply processing for both interfaces in the pipeline — required when the kernel no longer manages either interface
- **Single-NIC two-queue (optional)**: Support VLAN trunking on a single physical port — client traffic on VLAN A, server traffic on VLAN B — using DPDK VLAN filtering per queue pair
- `pipeline_feed_eth0` raw `uint8_t*` buffer signature is **intentionally preserved** for now

## Capabilities

### New Capabilities
- `full-dpdk-io`: Both eth0 and eth1 use DPDK PMD for kernel-bypass I/O — unified mbuf-based receive/transmit on both interfaces
- `arp-handler`: In-pipeline ARP responder for both interfaces, replacing kernel ARP when NICs are fully owned by DPDK
- `single-nic-vlan`: Optional single-NIC mode using VLAN-tagged queue pairs to separate client and server traffic on one physical port

### Modified Capabilities
<!-- No existing spec-level behavioral changes — sequence number translation, flow table, and pipeline routing logic are unchanged -->

## Impact

- **`src/clientnic/dpdk/io.c`**: `eth0_init/recv/send` rewritten from AF_PACKET to DPDK port init; `eth0_io` struct gains `port_id` and `mbuf_pool` fields
- **`src/clientnic/dpdk/io.h`**: `eth0_io` struct updated to match `eth1_io` shape
- **`src/clientnic/dpdk/main.c`**: Poll loop updated; `install_iptables()` removed; EAL init gains second port; ARP handler wired in
- **`src/clientnic/dpdk/pipeline.c`**: ARP packets routed to new handler before TCP processing; RST drop rule added
- No changes to `flow_table.c`, `translator.c`, `packet_processor.c`, `checksum.c`, or `pipeline.h`
- **Infrastructure**: On-prem servers need both NICs bound to vfio-pci before launch; hugepages and DPDK install unchanged
