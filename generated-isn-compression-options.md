This is a legitimate middlebox engineering question — the same techniques used in production L4 load balancers, QUIC-LB, and SYN-cookie implementations. Here's the requested packet-level detail.

## Reference: TCP header (20 bytes + options)

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|          Source Port          |       Destination Port        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    Sequence Number (ISN)                      |  <-- Technique 1: 32 bits
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                Acknowledgment Number (=0 in SYN)              |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
| Data  |Rsvd |N|C|E|U|A|P|R|S|F|            Window             |
| Offset|     | |W|C|R|C|S|S|Y|I|                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|           Checksum            |        Urgent Pointer         |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    Options (0–40 bytes)                       |  <-- Techniques 3,4
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    Payload (Technique 2)                      |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

## Technique 1 — ISN field (server-side, in SYN-ACK)

Byte offset 4–7 of TCP header. SmartNIC writes its 32-bit value `V` as the SYN-ACK sequence number.

Before (origin server's real SYN-ACK):
```
seq = S_real      (server's own ISN)
ack = C_isn + 1
flags = SYN|ACK
```
After (SmartNIC rewrite on egress toward client):
```
seq = V           (your 32-bit value, replaces bytes 4-7)
ack = C_isn + 1
flags = SYN|ACK
TCP checksum recomputed (BF3 hardware)
```
Recovery: client's next packet carries `ack = V + 1` at byte offset 8–11. SmartNIC reads it, subtracts 1, recovers `V` statelessly. **Required fixup:** for all subsequent client→server packets, translate `ack` field `V+1 → S_real+1` (`delta = S_real − V`); for server→client, `seq += delta`. This is the seq/ack NAT.

## Technique 2 — SYN payload (TFO-style)

Append after the options. Set IP total length and respect Data Offset.

```
[IP hdr][TCP hdr + opts][4-byte value V]
                         ^ payload begins at Data Offset*4
```
TCP must mark the bytes as data: `SND.NXT += 4`. The receiving middlebox/server then sees `seq` advance by 4. RFC 7413 mandate: if the SYN-with-data is dropped, the retransmit MUST be a bare SYN with no data — so you need a stateful fallback path. Practically fragile across the open internet; fine inside a controlled fabric.

## Technique 3 — TCP option, experimental kind (RFC 6994)

Append a 8-byte option in the options area:

```
+--------+--------+--------+--------+--------+--------+--------+--------+
| Kind   | Length | ExID (2 bytes)  |   Your 32-bit value V (4 bytes)   |
| =253   | =8     | 0xF989 (magic)  |                                   |
+--------+--------+--------+--------+--------+--------+--------+--------+
```
- Kind 253 or 254 (experimental, RFC 6994)
- Length = 8 (kind+len+exid+value)
- ExID = a 16-bit magic you pick to disambiguate
- Pad options to 4-byte boundary with NOP (0x01) / EOL (0x00); bump Data Offset accordingly

This is the load-balancer pattern from the patent literature: embedding decoded TCP option information into a TCP option field that has a reserved type, identified by kind number 252. Survives most paths; option-stripping middleboxes are the failure mode.

## Technique 4 — Timestamp option (TSval)

Standard timestamp option, value field overwritten:

```
+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+
| Kind=8 | Len=10 |        TSval (4 bytes) = V        |        TSecr (4 bytes)           |
+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+
```
TSval is bytes 2–5 of the option. Caveat: breaks PAWS and RTT estimation if either real stack uses timestamps; arbitrary value is statistically conspicuous.

## Technique 5 — Source port + ISN split

```
Source Port (bytes 0-1): high 16 bits of V
ISN         (bytes 4-7): low 16 bits of V in upper half, real entropy in lower
```
Middlebox-transparent but the source port feeds 5-tuple ECMP hashing — Maglev distributes L4 traffic using a 5-tuple hash of source/destination IP, protocol, and source/destination ports — so it changes backend selection. Only viable if your steering logic owns that hash.

## What QUIC does (the model)

QUIC puts this in an explicit **Connection ID** field rather than scavenging TCP header space. QUIC-LB provides a standardized means of securely encoding routing information in the server's connection IDs so a load balancer can route packets with migrated addresses correctly; concretely MsQuic encodes a fixed 4-byte value into the Server ID portion, which the load balancer uses to look up and route packets to the appropriate server. Your ISN-reflection scheme is the TCP analogue of exactly this.

## Summary table

| # | Field | Offset | Bits | Client mod needed | Middlebox-safe | Fixup required |
|---|-------|--------|------|-------------------|----------------|----------------|
| 1 | ISN (SYN-ACK) | TCP 4–7 | 32 | No | Yes | seq/ack NAT |
| 2 | SYN payload | after opts | any | Stack support | Weak | SND.NXT, fallback |
| 3 | Option K253/254 | opts area | 32 | No | Mostly | Data Offset bump |
| 4 | Timestamp TSval | opts area | 32 | No | Yes | Breaks PAWS |
| 5 | SrcPort+ISN | TCP 0–1,4–7 | 16+16 | No | Yes | ECMP coupling |

For a BF3/DPDK middlebox in a controlled path, **Technique 1** is cleanest — exact 32-bit fit, fixed offset for a cheap P4 parse, no client changes, stateless recovery from the return-path ack, with the seq/ack translation being the only (line-rate) cost.

Want the P4/DPL parser snippet for the ISN extract + the seq/ack delta-translation table next?