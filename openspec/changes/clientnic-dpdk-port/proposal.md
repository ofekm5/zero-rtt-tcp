## Why

The ClientNIC 0-RTT middleware currently runs on Scapy (Python/AF_PACKET), which incurs per-packet Python overhead and kernel-to-userspace copies on every receive/send. Porting the data plane to DPDK (C) enables kernel-bypass on the server-facing eth1 interface, dramatically reducing latency and increasing throughput — critical for demonstrating that 0-RTT gains aren't negated by middleware overhead. The DPDK infrastructure (c5n.large, hugepages, vfio-pci, ENA PMD) is already provisioned and waiting.

## What Changes

- **New C application** in `clientnic/dpdk/` implementing the full 0-RTT pipeline (parse → decide → modify → send)
- **Hybrid I/O model**: AF_PACKET raw socket for eth0 (kernel, client-facing) + DPDK ENA PMD for eth1 (server-facing)
- **Same wire-level behavior**: spoofed SYN-ACK, flow table, seq/ack translation, checksum recalculation — identical to Scapy version
- **Meson build system** linking against the DPDK 23.11 installation at `/usr/local`
- **No changes** to Scapy version, ServerNIC, Client, or Server apps
- **No changes** to integration test tooling (`validate_0rtt_capture.py`, `run_experiment.sh`) — wire behavior is identical

## Capabilities

### New Capabilities
- `dpdk-data-plane`: DPDK-based packet I/O using ENA PMD for eth1 (rx_burst/tx_burst) with AF_PACKET fallback for kernel-managed eth0
- `flow-table-c`: C hash-table implementation of the flow table (4-tuple keying, seq delta tracking, per-flow packet buffering)
- `packet-pipeline-c`: C implementation of the parse → decide → modify → send pipeline with zero-copy packet manipulation via direct header pointer access
- `syn-ack-spoofer-c`: C implementation of spoofed SYN-ACK construction and SYN interception
- `seq-translator-c`: C implementation of bidirectional seq/ack rewriting with 32-bit wraparound and DPDK checksum helpers

### Modified Capabilities
<!-- No existing specs to modify -->

## Impact

- **New code**: ~9 C source files + meson.build in `clientnic/dpdk/`
- **Dependencies**: DPDK 23.11 (already installed on VMs), meson/ninja (standard DPDK build tools)
- **Infrastructure**: No changes — c5n.large with vfio-pci eth1 binding already provisioned in `infra/dpdk/`
- **Integration tests**: Swap `python3 main.py` → `sudo ./clientnic-dpdk -l 0 -- --port=8080 --gw-mac=<MAC>` in experiment scripts
- **Existing Scapy app**: Unchanged, remains as reference implementation
