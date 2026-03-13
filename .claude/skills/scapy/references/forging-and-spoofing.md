# Forging & Spoofing Packets

> Phase: **Modify** — constructing response packets to inject into the network

## Source/Destination Swap Pattern

When forging a reply to a received packet, swap all src/dst fields across all layers:

```python
# ── PARSE ── (extract from incoming SYN)
client_mac = pkt[Ether].src
server_mac = pkt[Ether].dst
client_ip = pkt[IP].src
server_ip = pkt[IP].dst
client_port = pkt[TCP].sport
server_port = pkt[TCP].dport
client_seq = pkt[TCP].seq

# ── MODIFY ── (build spoofed SYN-ACK)
syn_ack = (
    Ether(src=server_mac, dst=client_mac)        # swap MACs
    / IP(src=server_ip, dst=client_ip)            # swap IPs
    / TCP(sport=server_port, dport=client_port,   # swap ports
          seq=spoofed_isn,
          ack=client_seq + 1,                     # ⚠️ wraparound warning
          flags="SA")
)
```

This is implemented in `spoofer.py:SynAckSpoofer.create_syn_ack()`.

## ISN Generation

Generate a random Initial Sequence Number for spoofed SYN-ACKs:

```python
import random

def generate_random_isn() -> int:
    return random.randint(0, 0xFFFFFFFF)
```

The ISN must differ from the real server's ISN — this is what creates the non-zero delta that proves 0-RTT is working.

## SYN-ACK ACK Field: Wraparound Warning

The ACK in a SYN-ACK must be `client_seq + 1`. Near the 32-bit boundary this wraps:

```python
ack = (client_seq + 1) & 0xFFFFFFFF   # ✅ safe
ack = client_seq + 1                    # ⚠️ may exceed 32-bit range
```

**Note**: Scapy does NOT auto-wrap sequence numbers. The current `spoofer.py` does not apply the mask — it works because Scapy truncates to 32 bits when serializing to wire, but explicit masking is safer.

## Use `sendp()` for Spoofed Replies (Same Subnet)

Spoofed replies include a crafted Ethernet header with swapped MACs. Use `sendp()` (L2) to preserve the Ethernet layer:

```python
sendp(syn_ack, iface="eth0", verbose=False)   # ✅ sends with our Ether header
send(syn_ack, iface="eth0", verbose=False)     # ❌ kernel overwrites Ether header
```

**Exception**: For forwarded packets going cross-subnet, use `send(pkt[IP], ...)` instead — see `sending.md`.

## Forging vs Forwarding

| Operation | Function | Ether Header | Use Case |
|-----------|----------|--------------|----------|
| **Forge reply** | `sendp()` | You build it (swapped MACs) | Spoofed SYN-ACK to client |
| **Forward packet** | `send(pkt[IP], ...)` | Kernel builds it via ARP | Forwarding SYN to server, data packets |
