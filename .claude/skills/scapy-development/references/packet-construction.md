# Packet Construction

> Phase: **Modify** (building packets to send) or test setup (building packets for assertions)

## The `/` Operator

Stack layers with `/`. Order matters — outermost first:

```python
from scapy.all import Ether, IP, TCP, UDP, Raw

# TCP SYN with Ethernet header
pkt = Ether()/IP(dst="10.0.0.1")/TCP(dport=80, flags="S")

# UDP with payload
pkt = Ether()/IP(dst="10.0.0.1")/UDP(dport=53)/Raw(load=b"data")

# TCP SYN-ACK (spoofed response)
syn_ack = (
    Ether(src=server_mac, dst=client_mac)
    / IP(src=server_ip, dst=client_ip)
    / TCP(sport=server_port, dport=client_port,
          seq=spoofed_isn, ack=client_seq + 1, flags="SA")
)
```

## `haslayer()` Guard

**ALWAYS check before accessing a layer** — prevents `IndexError` on unexpected packets:

```python
# ── PARSE ──
if not pkt.haslayer(TCP):
    return

# Now safe to access
seq = pkt[TCP].seq
```

Use `haslayer()` (method), not `in` operator for consistency, though both work:
```python
if TCP in pkt:          # ✅ works
if pkt.haslayer(TCP):   # ✅ also works — this project's convention
```

## Field Access Cheat Sheet

| Field | Access | Notes |
|-------|--------|-------|
| Source IP | `pkt[IP].src` | String: `"10.0.0.1"` |
| Dest IP | `pkt[IP].dst` | String |
| Source port | `pkt[TCP].sport` | Integer |
| Dest port | `pkt[TCP].dport` | Integer |
| TCP flags | `pkt[TCP].flags` | String: `"S"`, `"SA"`, `"A"`, `"FA"`, `"R"` |
| Individual flag | `pkt[TCP].flags.S` | Boolean |
| Sequence number | `pkt[TCP].seq` | Integer (32-bit) |
| ACK number | `pkt[TCP].ack` | Integer (32-bit) |
| Payload bytes | `pkt[Raw].load` | `bytes` object |
| Raw packet bytes | `bytes(pkt)` | Full packet as bytes |
| Source MAC | `pkt[Ether].src` | String: `"aa:bb:cc:dd:ee:ff"` |
| Dest MAC | `pkt[Ether].dst` | String |
| Sniffed interface | `pkt.sniffed_on` | Set by `sniff()` — e.g., `"eth0"` |

## TCP Flag Shortcuts

| Flag string | Meaning |
|-------------|---------|
| `"S"` | SYN |
| `"SA"` | SYN-ACK |
| `"A"` | ACK |
| `"PA"` | PSH-ACK (data) |
| `"FA"` | FIN-ACK |
| `"R"` | RST |
| `"RA"` | RST-ACK |

Check individual flags in the Parse phase:
```python
is_syn = tcp.flags.S and not tcp.flags.A
is_syn_ack = tcp.flags.S and tcp.flags.A
```

## Auto-Calculated Fields

Scapy automatically calculates these when sending — do NOT set them manually unless you have a reason:
- `IP.chksum` — IP header checksum
- `TCP.chksum` — TCP checksum (includes pseudo-header)
- `IP.len` — total IP length
- `IP.id` — IP identification

To force recalculation after modifying fields: `del pkt[IP].chksum`
