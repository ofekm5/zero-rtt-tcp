# Plan: Restructure Scapy Skill into Modular Reference Collection

## Context

The existing `.claude/skills/scapy/SKILL.md` is a single flat ~140-line document. It covers everything superficially, making it poor at injecting the deep, use-case-specific knowledge Claude needs when writing Scapy code for this project. The user wants it broken into modular, detailed, use-case-specific context.

**Decision: One skill with `references/` directory — not multiple skills, not an MCP server.**

- **Not MCP**: Scapy runs on remote Linux VMs over SSM. Claude's job is to *write* Scapy code, not *execute* it. MCP provides tool-based runtime interaction — wrong fit.
- **Not multiple skills**: Multiple skills create trigger ambiguity ("fix packet forwarding" spans sending + kernel + checksums simultaneously). Skills can't cross-reference each other.
- **References pattern**: Matches the existing `zero-rtt-integration-tester/` model. SKILL.md is the routing index; Claude reads only the relevant reference file(s) for the task.

---

## File Structure

```
.claude/skills/scapy/
├── SKILL.md                              # Rewrite: slim routing doc (~80 lines)
└── references/
    ├── packet-construction.md
    ├── sniffing.md
    ├── sending.md
    ├── seq-rewriting-and-checksums.md
    ├── forging-and-spoofing.md
    ├── kernel-integration.md
    ├── pcap-analysis.md
    └── unit-testing.md
```

---

## SKILL.md (rewrite)

Replace current flat doc with a slim routing document:

- **Frontmatter**: Expand description with trigger phrases: packet construction, BPF filter, checksum, sendp vs send, AF_PACKET, iptables, pcap, seq rewriting, spoofing, forging, unit test
- **Core principles** (4 bullets, no code):
  - AF_PACKET receives copies — kernel still processes originals
  - Checksums: delete both IP+TCP checksums before `send()` to auto-recalculate
  - 32-bit wraparound: all SEQ/ACK arithmetic must `& 0xFFFFFFFF`
  - `send()` vs `sendp()`: L3 vs L2 — this is the most common pitfall
- **Canonical imports** (code block used throughout this project)
- **Reference index table**: maps each file to topic + "consult when..." trigger

---

## Reference Files (content sources)

All content is drawn from actual project code + documented bugs, not Scapy docs.

### `references/sending.md` ⭐ Highest value
- `sendp()` (L2) vs `send()` (L3) decision matrix
- **Bug lesson**: `sendp()` preserves original MACs → silently dropped cross-subnet (real bug from integration testing)
- **Critical pitfall**: `send(iface=...)` is **silently ignored** at L3 — kernel routing table decides; must add OS routes with `ip route replace`
- Decision matrix table: scenario → which API → why

### `references/kernel-integration.md` ⭐ Second highest value
- AF_PACKET architecture: copies not originals
- Kernel RST suppression: `iptables -A OUTPUT -p tcp --tcp-flags RST RST -j DROP`
- **Packet re-capture loop** (commit `d6cf344`): sniff captures own sent packets → infinite loop. Fix: `get_if_hwaddr()` at startup, skip packets where `packet[Ether].src` matches own MAC
- **Kernel forwarding race** (2026-03-07 bug): `ip_forward=1` completes handshake before Python runs. Fix: `iptables -A FORWARD -p tcp --dport 8080 -j DROP`
- Summary table of all required iptables rules

### `references/seq-rewriting-and-checksums.md`
- `packet[IP].copy()` before modification
- Which field to rewrite in which direction (commit `23cb04a` bug):
  - Client→Server: rewrite **ACK** (subtract delta)
  - Server→Client: rewrite **SEQ** (add delta)
- `& 0xFFFFFFFF` 32-bit wraparound on all arithmetic
- Checksum deletion: `del pkt[IP].chksum; del pkt[TCP].chksum` — BOTH required
- Scapy field states: set / deleted (auto-compute on wire) / auto

### `references/packet-construction.md`
- `/` operator layer stacking
- Flag shortcuts: `"S"`, `"SA"`, `"A"`, `"PA"`, `"FA"`, `"R"` + individual access `tcp.flags.S`
- `packet.haslayer(Layer)` guard pattern (always before `packet[Layer]`)
- Field access cheat sheet: `[IP].src/dst`, `[TCP].sport/dport/seq/ack/flags`, `[Ether].src/dst`
- `packet.show()` for debugging

### `references/sniffing.md`
- `sniff(iface, prn, filter, store=False)` — all parameters
- BPF filter syntax + **gotcha**: must exclude `169.254.169.254` (AWS metadata traffic floods callback → spoofed SYN-ACK arrives late)
- Multi-interface: `sniff(iface=["eth0", "eth1"])` + `packet.sniffed_on`
- `AsyncSniffer` for non-blocking
- Threading pattern: `Thread(daemon=True)` for second sniffer, main thread blocks on first

### `references/forging-and-spoofing.md`
- Swap all src/dst: `Ether(src=orig_dst, dst=orig_src)/IP(src=orig_dst, dst=orig_src)/TCP(sport=orig_dport, ...)`
- ISN generation: `random.randint(0, 0xFFFFFFFF)`
- SYN-ACK `ack = syn[TCP].seq + 1` — **warning**: Scapy doesn't auto-wrap; if seq=`0xFFFFFFFF`, ack becomes `0x100000000`. Apply `& 0xFFFFFFFF`.
- Use `sendp()` for spoofed replies (same interface, you control MACs exactly)

### `references/pcap-analysis.md`
- `rdpcap(path)` / `wrpcap(path, packets)`
- `float(pkt.time)` for timestamps
- `raw(pkt[IP])` / `raw(pkt[TCP])` for raw bytes
- Manual TCP checksum: pseudo-header (`src_ip + dst_ip + 0x06 + tcp_length`) + TCP with chksum zeroed → `scapy.utils.checksum()`
- Reference to `zero-rtt-clientnic-translate/clientnic/validate_0rtt_capture.py` as worked example

### `references/unit-testing.md`
- Construct real Scapy packets (not dicts/mocks) for accurate layer behavior
- `@patch("mymodule.src.forwarder.send")` → `mock_send.assert_called_once_with(pkt[IP], iface=..., verbose=False)`
- `pkt.sniffed_on = "eth0"` — directly settable on Scapy packets
- `@patch("mymodule.get_if_hwaddr", return_value="aa:bb:cc:dd:ee:ff")`

---

## Implementation Steps

1. Create `.claude/skills/scapy/references/` directory
2. Rewrite `.claude/skills/scapy/SKILL.md`
3. Create all 8 reference files (independent, any order)
   - Priority order: sending → kernel-integration → seq-rewriting → rest

---

## Verification

- Open a new Claude Code session and ask a Scapy question (e.g., "how do I forward a packet to another subnet?") — confirm skill triggers and Claude reads `references/sending.md`
- Ask about packet re-capture — confirm Claude reads `references/kernel-integration.md`
- Ask about rewriting TCP sequence numbers — confirm Claude reads `references/seq-rewriting-and-checksums.md`
