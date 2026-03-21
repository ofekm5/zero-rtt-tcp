# Sequence Number Rewriting & Checksums

> Phases: **Parse** (read seq/ack), **Decide** (look up delta), **Modify** (rewrite + checksum delete)

## Copy Before Modify

**Always copy the IP layer before modifying.** Mutating the sniffed packet in-place can corrupt Scapy's internal state:

```python
pkt = packet[IP].copy()       # ✅ safe — work on a copy
pkt[TCP].ack = new_ack        # modify the copy
send(pkt, iface=egress, verbose=False)
```

## Common Mistake: Rewriting the Wrong Field

**WARNING**: It's easy to accidentally rewrite SEQ when you should rewrite ACK (or vice versa). This causes the server to RST every packet.

Only **one field per direction** needs rewriting — the one that references the spoofed/real ISN:
- Client→Server: the client's **ACK** references the spoofed ISN → rewrite ACK
- Server→Client: the server's **SEQ** references the real ISN → rewrite SEQ
- Client's **SEQ** and server's **ACK** track the client's ISN, which was never spoofed → **do NOT rewrite**

**Concrete example** (delta=200, client_ISN=100, spoofed_server_ISN=500, real_server_ISN=300):
```
Client sends:      SEQ=101, ACK=501
Buggy rewrite:     SEQ=301, ACK=501  ← server expects SEQ=101 → RST
Correct rewrite:   SEQ=101, ACK=301  ← matches server expectations ✓
```

## Direction Rules

### Client → Server: Rewrite ACK (subtract delta)

The client ACKs relative to `spoofed_server_ISN`. The server expects ACKs relative to `real_server_ISN`.

```python
# delta = spoofed_ISN - real_ISN
pkt[TCP].ack = (pkt[TCP].ack - delta) & 0xFFFFFFFF
```

### Server → Client: Rewrite SEQ (add delta)

The server sends SEQ relative to `real_server_ISN`. The client expects SEQ relative to `spoofed_server_ISN`.

```python
# delta = spoofed_ISN - real_ISN
pkt[TCP].seq = (pkt[TCP].seq + delta) & 0xFFFFFFFF
```

### Memory Aid

| Direction | Field | Operation | Why |
|-----------|-------|-----------|-----|
| Client → Server | ACK | **subtract** delta | Translate client's ACK back to server's space |
| Server → Client | SEQ | **add** delta | Translate server's SEQ into client's space |

## 32-Bit Wraparound

TCP sequence numbers are unsigned 32-bit integers. **All arithmetic MUST use `& 0xFFFFFFFF`**:

```python
new_seq = (old_seq + delta) & 0xFFFFFFFF    # ✅ wraps correctly
new_ack = (old_ack - delta) & 0xFFFFFFFF    # ✅ wraps correctly

new_seq = old_seq + delta                    # ❌ Python int grows unbounded
```

## Checksum Deletion

After modifying **any** IP or TCP field, delete both checksums. Scapy recalculates on send:

```python
del pkt[IP].chksum
del pkt[TCP].chksum
```

**Both checksums must be deleted** even if you only modified a TCP field, because the TCP checksum includes a pseudo-header with IP fields, and Scapy's recalculation depends on both being cleared.

## Complete Rewrite Pattern (from `rewriter.py`)

```python
def rewrite_client_to_server(self, packet, delta, iface):
    # PARSE: extract IP layer copy
    pkt = packet[IP].copy()

    # MODIFY: rewrite ACK, clear checksums, send
    pkt[TCP].ack = (pkt[TCP].ack - delta) & 0xFFFFFFFF
    del pkt[IP].chksum
    del pkt[TCP].chksum
    send(pkt, iface=iface, verbose=False)
```
