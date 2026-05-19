# ISN Compression Techniques — Comparison

Side-by-side comparison of the 7 techniques from `generated-isn-compression-options.md` for passing a 32-bit value `V` (the spoofed server ISN) between middleboxes in the 0-RTT TCP path.

## 1. Identity — what each technique is

| # | Technique | Direction | How to implement (one-liner) |
|---|---|---|---|
| 1 | ISN field (SYN-ACK seq) | s→c | On egress SYN-ACK: `pkt[TCP].seq = V`; del IP+TCP checksums; maintain seq/ack delta NAT for rest of flow |
| 2 | SYN payload (TFO-style) | c→s | Append 4-byte `V` after TCP options, set IP total length, advance `SND.NXT += 4`; add stateful fallback for bare-SYN retransmit |
| 3 | Experimental TCP option (Kind 253/254) | c→s | Append `(Kind=253, Len=8, ExID=magic, V)` to SYN options, bump Data Offset, pad to 4-byte boundary with NOP/EOL |
| 4 | Timestamp TSval | Either | Overwrite bytes 2–5 of existing TS option (Kind=8, Len=10) with `V`; requires `tcp_timestamps=0` on both endpoints |
| 5 | SrcPort + ISN split | c→s | Pack hi-16 of `V` into SrcPort, lo-16 into upper half of ISN; ensure your RSS/ECMP steering logic owns the resulting hash |
| 6 | Sideband UDP control packet | Side-channel | Send separate UDP datagram `[magic, 4-tuple, V, ...]` from ClientNIC to ServerNIC alongside the forwarded SYN; pin RX queue to defeat race |
| 8 | **SYN ack-num field** | **c→s** | **On forwarded SYN: `pkt[TCP].ack = V`; del IP+TCP checksums; ServerNIC reads bytes 8–11 at SYN-time, optionally zeros before forwarding to Server** |

## 2. Where `V` lives on the wire

| # | Location | Bytes consumed | Data Offset bump? |
|---|---|---|---|
| 1 | SYN-ACK bytes 4–7 (overwrites `S_real`) | 4 | No |
| 2 | Payload after options in SYN | 4+ (advances `SND.NXT`) | No |
| 3 | SYN options area, 8-byte option | 8 | **Yes** |
| 4 | TS option bytes 2–5 in SYN | 4 (within 10-byte option) | No |
| 5 | SrcPort hi-16 + ISN hi-16 in SYN | 4 across 2 fields | No |
| 6 | Separate UDP datagram | Unlimited | N/A |
| 8 | **SYN bytes 8–11 (ack-num field)** | **4** | **No** |

## 3. Compatibility & robustness

| # | Race-free | Survives option-stripping middlebox | Survives ENA RSS | Survives TCP normalizer | Disturbs endpoint state |
|---|---|---|---|---|---|
| 1 | Yes | N/A (no options) | Yes | Yes | Forces seq/ack NAT on owner |
| 2 | N/A | Yes | Yes | Mostly | Moves `SND.NXT` forward |
| 3 | Yes | **No** | Yes | Yes | None |
| 4 | Yes | Mostly | Yes | Yes | **Breaks PAWS + RTT estimation** |
| 5 | Yes | Yes | **No (changes 5-tuple hash)** | Yes | Reduces SrcPort entropy |
| 6 | **No (RSS race)** | Yes | No | Yes | None |
| 8 | **Yes** | **Yes** | **Yes** | **Possibly no** | **None** |

## 4. State, timing, buffering

| # | When `V` is readable | Per-flow state at reader | Buffering needed |
|---|---|---|---|
| 1 | At SYN-ACK time | Flow table, delta | Until real SYN-ACK |
| 2 | At SYN time | Flow table + TFO fallback | Yes (TFO retransmit) |
| 3 | At SYN time | Flow table | Minimal |
| 4 | At SYN time | Flow table; PAWS suppression | Minimal |
| 5 | At SYN time | Flow table; steering ownership | Minimal |
| 6 | When control pkt arrives (racy) | Pending-flow table | SYNs without matching control entry |
| 8 | **At SYN time** | **Flow table** | **Minimal** |

## 5. Failure modes

| # | Primary failure mode | Mitigation |
|---|---|---|
| 1 | 32-bit `V` collision within MSL on same 4-tuple | High-entropy `V` |
| 2 | Path drops SYN-with-data; RFC 7413 forces bare-SYN retransmit | Stateful fallback path |
| 3 | Middlebox strips unknown TCP options | Use only inside controlled fabric |
| 4 | PAWS rejects packets; RTT estimation corrupted | `tcp_timestamps=0` on both endpoints |
| 5 | RSS re-hashes to wrong RX queue / backend | Own the steering logic |
| 6 | Control pkt arrives after SYN due to RSS race | Pin RX queue, or buffer SYNs at reader |
| 8 | **TCP normalizer (Cisco ASA / Palo Alto / F5) zeros the SYN ack-num** | **Verify with probe pcap on the path; fall back to T3 if path rewrites the field** |

## 6. Decision quick-reference

| Constraint | Pick |
|---|---|
| Encoding `V` for the real server to consume | **1** (SYN-ACK seq rewrite) |
| Moving NAT to ServerNIC, pure AWS VPC (no normalizers) | **8** (SYN ack-num) |
| Moving NAT to ServerNIC, path may include TCP normalizer | **3** (experimental option) |
| Need to carry richer metadata than `V` | **6** (sideband UDP) |
| You own RSS/ECMP steering, want zero option footprint | **5** (SrcPort split) |
| Endpoints have timestamps enabled (Linux default) | Avoid **4** |
| Crossing the open internet | Avoid **2, 3, 5, 8** |

## 7. T8 vs. T3 — head-to-head

Both give SYN-time `V` on the c→s direction. Same 4-byte width. Differ only in failure mode.

| | T3 (experimental option) | T8 (SYN ack-num) |
|---|---|---|
| Header surgery | New 8-byte option + Data Offset bump + NOP/EOL padding | Single 32-bit field overwrite |
| Killed by | Option-stripping middlebox | TCP normalizer that zeros ack on SYN |
| Likely in AWS VPC path | No (ENA doesn't strip options) | No (no normalizer in pure VPC path) |
| Likely on open internet | Yes (option strippers exist) | Yes (security appliances normalize TCP) |
| Implementation complexity | Build option tuple, recompute Data Offset | One field assignment |

**Conclusion**: inside the demo's AWS VPC fabric, T8 is the lower-complexity choice; T3 is the safer choice if the deployment ever has to traverse third-party security appliances.

## 8. Key takeaways

- **T1 does not fit c→s SYN encoding** — overwriting `C_isn` forces double-NAT. **T8 fits** because the SYN's ack field is ignored input at compliant endpoints, not consumed input like seq.
- **Moving the NAT to ServerNIC is state relocation, not reduction** — total per-flow bookkeeping is roughly unchanged across T3/T6/T8.
- **T3 and T8 are functional twins** for the c→s SYN handoff at SYN-time. Pick by failure mode: T3 dies on option-strippers, T8 dies on TCP normalizers.
- **32-bit width is enough for ISN**, but too narrow for richer metadata (use T5 or T6).
