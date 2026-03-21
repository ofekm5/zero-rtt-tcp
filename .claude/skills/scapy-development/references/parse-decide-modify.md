# Parse → Decide → Modify

> **This pattern applies to ALL Scapy code in this project. Every packet handler must follow this structure.**

## The Pipeline

Every Scapy handler processes packets in exactly three phases:

```python
def handle_packet(pkt):
    # ── PARSE ──────────────────────────────────
    # Extract only the fields you need. Do ALL header
    # access here. Never scatter layer lookups across
    # the function.
    if not pkt.haslayer(IP):
        return
    src = pkt[IP].src
    dst = pkt[IP].dst
    proto = pkt[IP].proto

    # ── DECIDE ─────────────────────────────────
    # All classification, lookup, and policy logic
    # lives here. No packet field access, no mutation.
    # Inputs: parsed values. Output: an action.
    if src in BLOCKLIST:
        action = "drop"
    elif dst in REDIRECT_MAP:
        action = "redirect"
    else:
        action = "forward"

    # ── MODIFY ─────────────────────────────────
    # Apply the action. Rewrite headers, recalculate
    # checksums, send or drop. No new parsing here.
    if action == "drop":
        return
    if action == "redirect":
        pkt[IP].dst = REDIRECT_MAP[dst]
        del pkt[IP].chksum  # force recalc
    sendp(pkt, iface="eth0", verbose=False)
```

## The 5 Rules

1. **No parsing in Decide or Modify.** All `pkt[Layer].field` reads happen in Parse.
2. **No mutation in Parse or Decide.** All `pkt[Layer].field = x` writes happen in Modify.
3. **Decide is pure logic.** It takes parsed values as input and returns an action — nothing else.
4. **Delete checksums before send** when any field is modified (`del pkt[IP].chksum`, `del pkt[TCP].chksum`). Scapy recalculates on wire.
5. **One handler, one pipeline.** If you need branching pipelines (e.g., ARP vs IP), split at Parse and feed separate Decide/Modify chains — don't nest.

## Why This Matters — Portability Table

| When you later port to…      | Parse maps to…              | Decide maps to…         | Modify maps to…               |
|------------------------------|-----------------------------|-------------------------|-------------------------------|
| **eBPF/XDP**                 | Header pointer arithmetic   | Map lookups / if-else   | Header rewrite + XDP action   |
| **DPDK**                     | `rte_pktmbuf` accessors     | Hash/LPM table lookup   | mbuf rewrite + tx_burst       |
| **NIC hardware offload**     | Match fields (TC flower)    | Flow table hit          | Action list (set/drop/fwd)    |

Clean separation now = straightforward offload later.

## Real-World Example (from this project)

The ClientNIC pipeline follows this pattern. In `src/pipeline/dispatcher.py`:

- **Parse**: `packet.haslayer(TCP)`, `packet[Ether].src`, `packet.sniffed_on`, `packet[TCP].flags` — all header reads upfront in `Dispatcher.dispatch()`
- **Decide**: classify SYN / SYN-ACK / data, check ingress interface, apply self-sent and re-capture guards
- **Modify**: delegate to `SynHandler`, `SynAckHandler`, or `Translator` — each owns its own complete workflow (copy, rewrite ACK/SEQ, delete checksums, send via `tx.*`)

See `references/oop-pipeline-structure.md` for how the handlers and Dispatcher are structured.
