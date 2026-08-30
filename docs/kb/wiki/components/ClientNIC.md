---
type: Wiki Entry
title: "ClientNIC"
description: "Core 0-RTT TCP middleware. Intercepts SYN packets from the client, immediately sends a spoofed SYN-ACK, and concurrently forwards the real SYN to the server...."
tags: [component, clientnic]
timestamp: 2026-07-09T09:05:48+03:00
---

Source: `src/clientnic/README.md`

# ClientNIC

Core 0-RTT TCP middleware. Intercepts SYN packets from the client, immediately sends a spoofed SYN-ACK, and concurrently forwards the real SYN to the server. Once the real SYN-ACK arrives, it calculates a sequence number delta and rewrites all subsequent packets in both directions — transparent to both client and server.

## Role in the Chain

```
Client VM  <-->  ClientNIC VM  <-->  ServerNIC VM  <-->  Server VM
           eth0               eth1
```

- **eth0**: Connected to Client VM
- **eth1**: Connected to ServerNIC VM

## Internal Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  ClientNIC VM                                               │
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │ sniffer     │───▶│ flow_table  │───▶│ rewriter    │     │
│  │             │    │             │    │             │     │
│  │ sniff()     │    │ track state │    │ send()      │     │
│  │ on eth0/1   │    │ seq deltas  │    │ on eth0/1   │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

## How It Works

1. **SYN from client** → send spoofed SYN-ACK immediately (0-RTT) + forward real SYN to server
2. **Real SYN-ACK from server** → drop it (client already got the spoofed one), record real ISN, compute `seq_delta = spoofed_server_isn - real_server_isn`
3. **Client→Server packets** → rewrite ACK by subtracting delta
4. **Server→Client packets** → rewrite SEQ by adding delta

## Usage

```bash
# Requires root (raw sockets). Deprecated — feasibility PoC only, superseded by dpdk-forwarder/ in the live path.
sudo python3 src/clientnic/scapy/main.py

# Custom interfaces
sudo python3 src/clientnic/scapy/main.py --client-iface ens5 --server-iface ens6 --verbose
```

## Requirements

- Python 3.8+
- Scapy (`pip install scapy`)
- Root privileges (raw sockets via AF_PACKET)
- Linux

## Key Design Decisions

**Immediate SYN-ACK response** — The spoofed SYN-ACK is sent as soon as the SYN arrives, before the real server has responded. This is what saves the 1-RTT.

**Flow state tracking** — Each connection is tracked in a flow table by 4-tuple with its `seq_delta`, allowing transparent rewriting of all subsequent packets without the endpoints noticing.

**Buffering strategy** — Client data packets (ACK, PSH-ACK) may arrive before the real SYN-ACK has been received and the delta computed. These are buffered per-flow and flushed once the delta is known.

**Checksum recalculation** — After modifying SEQ/ACK numbers, IP and TCP checksums must be updated. This is done by deleting the checksum fields (`del pkt[IP].chksum` / `del pkt[TCP].chksum`), which reverts them to Scapy's auto-compute mode. On the next `send()`, Scapy serializes the full modified packet and computes fresh checksums:
- IP checksum: over the IP header only
- TCP checksum: over the TCP pseudo-header (src IP, dst IP, protocol, TCP length) + TCP header + payload

## Module Structure

```
src/clientnic/
├── validate_0rtt_capture.py  # pcap analysis tool (runs on this VM post-test)
├── scapy/                    # Python/Scapy implementation (deprecated — feasibility PoC only)
│   ├── main.py               # Entry point, sniffers on eth0/eth1
│   ├── src/
│   │   ├── pipeline.py       # Parse → classify → dispatch
│   │   └── utils/
│   │       ├── flow_table.py         # FlowKey, FlowEntry, FlowTable
│   │       ├── packet_processor.py   # SYN spoof + delta computation
│   │       ├── translator.py         # Seq/ack rewriting + checksum recalc
│   │       └── logger.py             # Logging setup
│   └── tests/
└── dpdk-forwarder/           # C/DPDK forwarder: spoof + stamp V + transparent forward (live implementation)
```

## Tests

```bash
# Scapy unit tests (deprecated component, from repo root)
pytest src/clientnic/scapy/tests/
```

### DPDK Tests

Two separate test levels exist for the DPDK implementation (`src/clientnic/dpdk-forwarder/`):

**Smoke tests** (`src/clientnic/dpdk-forwarder/tests/run_dpdk_tests.sh`) — validate the binary using virtual PMDs, no hardware required:
- Binary validation (ELF format + DPDK library linkage)
- EAL init with null PMD
- Ring PMD device creation
- Graceful no-device handling
- Port enumeration

Run manually on the ClientNIC VM:
```bash
cd ~/zero-rtt-tcp/src/clientnic/dpdk-forwarder
meson setup builddir && ninja -C builddir
sudo ./tests/run_dpdk_tests.sh builddir/clientnic-dpdk-forwarder
```

**Integration test** (`experiments/dpdk/run_experiment.sh`) — end-to-end 4-VM test validating actual 0-RTT behavior: starts Server → ServerNIC → ClientNIC → Client via SSM node scripts, then runs `validate_0rtt_capture.py` and writes a report to `experiments/dpdk/reports/`.

Manual verification with tcpdump:
```bash
# Terminal 1: Run ClientNIC
sudo python3 src/clientnic/scapy/main.py

# Terminal 2: Watch eth0
sudo tcpdump -i eth0 tcp -nn

# Terminal 3: Send SYN
sudo hping3 -S -p 80 <dest_ip>
```

Expected: SYN-ACK appears on eth0 before the real server responds.

Key scenarios to verify:
- Spoofed SYN-ACK has a different ISN from the real server's SYN-ACK
- Delta is correctly calculated and non-zero
- Buffered client packets are flushed and forwarded after delta is known
- Checksums are valid on all rewritten packets
- Multiple concurrent connections are handled independently
