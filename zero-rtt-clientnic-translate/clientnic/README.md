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
# Requires root (raw sockets)
sudo python -m clientnic.app.main

# Custom interfaces
sudo python -m clientnic.app.main --client-iface ens5 --server-iface ens6 --verbose
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
clientnic/
├── validate_0rtt_capture.py  # pcap analysis tool (runs on this VM post-test)
├── app/
│   ├── main.py               # Entry point, wires dependencies, starts sniffers
│   └── src/
│       ├── handlers.py       # ClientPacketHandler, ServerPacketHandler, PacketBuffer
│       ├── flow_table.py     # FlowKey, FlowEntry, FlowTable
│       ├── rewriter.py       # PacketRewriter (seq/ack rewriting + checksum recalc)
│       ├── spoofer.py        # SynAckSpoofer
│       └── logger.py         # Logging setup
└── tests/
    ├── test_flow_table.py
    ├── test_handlers.py
    └── test_spoofer.py
```

## Tests

```bash
# Unit tests (from repo root)
pytest zero-rtt-clientnic-translate/clientnic/tests/
```

Manual verification with tcpdump:
```bash
# Terminal 1: Run ClientNIC
sudo python -m clientnic.app.main

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
