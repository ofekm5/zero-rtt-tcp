---
name: scapy
description: "Network packet manipulation with Scapy. Use when constructing, sniffing, modifying, or sending raw network packets. Triggers: packet building, BPF filtering, sendp vs send, checksum recalculation, AF_PACKET, kernel RST suppression, iptables rules, pcap analysis, sequence number rewriting, spoofed replies, sniff callbacks, AsyncSniffer, flow tables, unit testing Scapy code."
---

# Scapy Packet Manipulation

## Core Architecture

All Scapy code in this project follows the **Parse → Decide → Modify** pipeline.
**Always read `references/parse-decide-modify.md` first** — it is the shared foundation for every reference file below.

## Core Principles

- **AF_PACKET sockets receive copies** — the kernel still processes the original packet (RSTs, forwarding, etc.)
- **Delete checksums after any modification**: `del pkt[IP].chksum; del pkt[TCP].chksum`
- **32-bit wraparound on all sequence number arithmetic**: `& 0xFFFFFFFF`
- **`send()` vs `sendp()`**: use `send()` (L3) for cross-subnet forwarding, `sendp()` (L2) for same-subnet spoofed replies

## Canonical Imports

```python
from scapy.layers.l2 import Ether, get_if_hwaddr
from scapy.layers.inet import IP, TCP
from scapy.sendrecv import send, sendp, sniff, AsyncSniffer
from scapy.all import rdpcap, wrpcap, raw, Raw
```

## Reference Index

| File | Topic | Consult when… |
|------|-------|---------------|
| `references/parse-decide-modify.md` | Core architectural pattern | **Always** — read alongside any other reference |
| `references/sending.md` | `sendp()` vs `send()`, cross-subnet bug | Sending packets, choosing L2 vs L3, forwarding |
| `references/kernel-integration.md` | AF_PACKET, RST suppression, re-capture loop | Kernel interference, iptables rules, packet loops |
| `references/seq-rewriting-and-checksums.md` | Delta math, copy-before-modify, checksums | Rewriting seq/ack numbers, checksum issues |
| `references/packet-construction.md` | `/` operator, flags, field access | Building packets, accessing header fields |
| `references/sniffing.md` | `sniff()` params, BPF, multi-interface, async | Capturing packets, filter setup, threading |
| `references/forging-and-spoofing.md` | Src/dst swap, ISN generation, spoofed replies | Forging responses, SYN-ACK spoofing |
| `references/pcap-analysis.md` | rdpcap/wrpcap, timestamps, manual checksums | Analyzing captures, offline validation |
| `references/unit-testing.md` | Real packets in tests, mock patterns, tx/get_if_hwaddr patching | Writing or fixing Scapy tests |
| `references/oop-pipeline-structure.md` | Dispatcher, Handler-per-packet-type, tx.py, multi-iface sniff, self-sent/re-capture guards | Structuring a middlebox as OOP classes |
