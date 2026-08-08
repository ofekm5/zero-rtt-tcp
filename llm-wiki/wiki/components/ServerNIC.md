---
type: Wiki Entry
title: "ServerNIC"
description: "In the live DPDK implementation (see dpdk/) ServerNIC is the sole stateful translator."
tags: [component, servernic]
timestamp: 2026-07-09T09:05:48+03:00
---

Source: `src/servernic/README.md`

# ServerNIC

In the live DPDK implementation (see `dpdk/`) ServerNIC is the **sole stateful translator**.
This document describes the legacy Scapy implementation (`scapy/`) — a stateless packet
forwarder that sits between ClientNIC and the Server VM, used only to demonstrate feasibility
of the idea and no longer needed in the live path.

## Role in the Chain

```
Client VM  -->  ClientNIC VM  -->  ServerNIC VM  -->  Server VM
                             eth0               eth1
```

- Packets arriving on `eth0` (from ClientNIC) are forwarded to `eth1` (Server)
- Packets arriving on `eth1` (from Server) are forwarded to `eth0` (ClientNIC)

ServerNIC is **completely stateless** — it performs no sequence number rewriting. All 0-RTT logic lives in ClientNIC.

## Usage

```bash
# Requires root (raw sockets). Deprecated — feasibility PoC only.
sudo python3 src/servernic/scapy/main.py --client-iface eth0 --server-iface eth1

# Custom interfaces
sudo python3 src/servernic/scapy/main.py --client-iface ens5 --server-iface ens6 --verbose
```

## Options

| Flag | Default | Description |
|---|---|---|
| `--client-iface` | `eth0` | Interface facing ClientNIC |
| `--server-iface` | `eth1` | Interface facing Server |
| `--verbose` | off | Enable DEBUG logging |

## Requirements

- Python 3.8+
- Scapy (`pip install scapy`)
- Root privileges (raw sockets via AF_PACKET)
- Linux

## Design

### Stateless operation

ServerNIC maintains no connection state and does no packet modification. Routing is purely based on which interface a packet arrived on. This keeps it simple and fast, and ensures all 0-RTT complexity stays in ClientNIC.

### No checksum recalculation

Packets are forwarded as-is. By contrast, ClientNIC must recalculate checksums after every SEQ/ACK rewrite — it does so by deleting the checksum fields (`del pkt[IP].chksum` / `del pkt[TCP].chksum`), which puts them back into Scapy's auto-compute mode so fresh checksums are calculated on the next `send()`.

### Self-sent packet filtering

`sniff()` on AF_PACKET captures both incoming and outgoing frames. ServerNIC filters out packets it sent itself (by matching the source MAC against its own interface MACs) to prevent a re-capture loop.

### Transparent forwarding

From the server's perspective, packets appear to come directly from the client (after ClientNIC's SEQ/ACK rewriting). ServerNIC adds no additional transformation.

## Why ServerNIC Exists

- **Network isolation**: Separates ClientNIC's manipulation logic from the server, preventing accidental interference.
- **Realistic topology**: Simulates multi-hop packet traversal as would occur in a real network.
- **Modularity**: Keeps 0-RTT logic contained in ClientNIC, making it easier to test and debug independently.
- **Extension point**: Provides a clean insertion point for future server-side monitoring or optimizations.

## Module Structure

```
src/servernic/
├── scapy/            # Python/Scapy implementation (deprecated — feasibility PoC only)
│   ├── main.py        # Entry point, sniffs on both interfaces
│   ├── src/
│   │   ├── pipeline.py    # Forwarding logic
│   │   └── utils/
│   │       └── logger.py  # Logging setup
│   └── tests/
└── dpdk/              # C/DPDK sole translator (live implementation — see dpdk/README.md)
```

## Tests

```bash
# From repo root
pytest src/servernic/scapy/tests/
```
