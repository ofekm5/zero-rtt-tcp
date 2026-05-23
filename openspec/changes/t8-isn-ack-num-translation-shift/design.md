## Context

The DPDK ClientNIC (`clientnic/dpdk/`) is complete and owns the full 0-RTT state machine:
spoof SYN-ACK on eth0, forward SYN on eth1, learn the real server ISN from the real SYN-ACK
that transits back on eth1, compute `seq_delta`, buffer client data until the delta is known,
and rewrite seq/ack on every subsequent packet in both directions. The DPDK ServerNIC is
**not implemented** — `servernic/dpdk/` is a README marking it WIP; the only ServerNIC code is
the Scapy stateless forwarder (`servernic/scapy/`).

T8 moves the translation responsibility to the ServerNIC. The enabling mechanism is the
**SYN ack-num channel**: the spoofed server ISN `V` is written into bytes 8–11 (the ack-num
field) of the SYN that the ClientNIC forwards. A LISTEN-state endpoint ignores `ack_seq` when
the ACK flag is clear (RFC 9293 §3.10.7.2; confirmed in the Linux `tcp_v4_rcv` → LISTEN path),
so the field is unused on a SYN and the Server never consumes it. The ServerNIC reads `V`,
zeros the field, and forwards a normal-looking SYN to the Server.

Constraints inherited from the existing DPDK stack:
- Single-threaded busy-poll, no locks (one lcore polls both interfaces).
- One interface is a DPDK port (ENA PMD, vfio-pci); the peer-facing interface is an AF_PACKET
  raw socket. Kernel RST suppression + FORWARD drops via iptables at startup.
- All seq/ack arithmetic uses 32-bit wraparound (`& 0xFFFFFFFF`).
- 4-tuple flow keys in network byte order; open-addressing hash table, linear probing.

## Goals / Non-Goals

**Goals:**
- A new ClientNIC variant (`clientnic/dpdk-forwarder/`) becomes spoof-SYN-ACK + transparent
  forwarder; it carries `V` to the ServerNIC via the SYN ack-num field and holds only minimal
  per-flow state. The existing `clientnic/dpdk/` full-owner implementation is preserved unchanged.
- ServerNIC becomes the sole stateful translator: extracts `V`, computes the delta, drops the
  real SYN-ACK, buffers pre-delta client data, and rewrites seq/ack both directions.
- Build a DPDK ServerNIC that mirrors the ClientNIC's structure and code conventions so the two
  nodes are maintainable as a pair.
- Prove on the real AWS VPC path that the ack-num field survives end to end (probe gate).

**Non-Goals:**
- No changes to the Scapy stack (ClientNIC or ServerNIC).
- No changes to the unmodified Client/Server applications.
- No T3/TCP-option fallback implementation here — only documented as the contingency if the
  probe fails (see Risks).
- No multi-backend / Connection-ID widening (that is the separate QUIC-CID todo).
- No TCP options handling (timestamps, window scaling, SACK) beyond what already exists.

## Decisions

### D1 — Carry `V` in the SYN ack-num field (T8), not a TCP option (T3)
For the current single-ClientNIC/single-ServerNIC AWS VPC topology, T8 is a single 32-bit field
overwrite with no Data Offset change and no option-stripping exposure. T3 (experimental option)
survives TCP normalizers but is killed by option-stripping middleboxes and adds header-length
complexity. There is no normalizer in the pure VPC path. **Chosen: T8, with T3 as a documented
fallback gated on the probe result.**

### D2 — ServerNIC is the translator; ClientNIC is transparent post-spoof
Once `V` is on the wire, the ServerNIC has everything it needs (`V` from the SYN, `real_isn`
from the SYN-ACK) to own the delta and all rewriting. Keeping any translation on the ClientNIC
would duplicate state and defeat the purpose. **The real SYN-ACK is therefore dropped at the
ServerNIC** (it must read `real_isn` from it first), and never reaches the ClientNIC.
*Alternative considered:* keep the ClientNIC translating and use `V` only as groundwork —
rejected; it does not move state off the client-side node, which is the whole point.

### D3 — ClientNIC retains a minimal flow table
The ClientNIC still needs per-flow state for two reasons: (a) the kernel retransmits the SYN
with `ack=0`, so on every forwarded SYN for a known flow the ClientNIC must re-stamp the same
`V` it chose for that flow; (b) server→client frames must be addressed to the original client
MAC. Entry shrinks to `{client_mac, spoofed_server_isn, state}` — `seq_delta`, `delta_valid`,
and the packet buffer are deleted.
*Alternative considered:* make the ClientNIC fully stateless and derive `V` from a keyed hash of
the 4-tuple so retransmits reproduce it without storage. Rejected as premature; it complicates
ISN generation and randomness for marginal benefit at this scale.

### D4 — ServerNIC zeros the ack field before forwarding the SYN to the Server
Even though the Server ignores ack on a SYN, zeroing keeps the Server's view RFC-clean and avoids
any downstream conntrack/IDS surprise. This requires a TCP checksum recompute on the SYN at the
ServerNIC. Cost is one checksum per connection setup — negligible.
*Alternative considered:* leave `V` in place (no recompute). Rejected per the chosen design
preference for a clean Server-facing wire; the cost is trivial.

### D4b — ClientNIC T8 variant lives in a new parallel folder, not in `clientnic/dpdk/`
The working `clientnic/dpdk/` (full-owner: spoof + translate) is **preserved unchanged** as the
reference implementation and rollback target. The T8 behavior is implemented in a new sibling
folder **`clientnic/dpdk-forwarder/`**, seeded by copying `clientnic/dpdk/` and then modifying it.
This keeps both data-plane designs buildable side by side, makes the diff between "full owner" and
"forwarder" auditable, and lets the experiment orchestrator choose which ClientNIC binary to run.
Consequently the existing ClientNIC capabilities (`syn-ack-spoofer-c`, `seq-translator-c`,
`flow-table-c`, `packet-pipeline-c`, `dpdk-data-plane`) are **not modified** — they continue to
describe `clientnic/dpdk/`. The variant gets its own new capabilities
(`clientnic-forwarder-*`). The variant reuses the `dpdk-data-plane` behavior (EAL, AF_PACKET,
busy-poll, iptables) verbatim by copying that code; no new data-plane spec is introduced for it.
*Alternative considered:* refactor `clientnic/dpdk/` in place and mark the existing specs MODIFIED.
Rejected per the requirement to preserve the existing implementation.

### D5 — ServerNIC mirrors the ClientNIC module decomposition
New files: `main.c`, `io.c/h` (DPDK port toward ClientNIC + AF_PACKET toward Server),
`pipeline.c/h`, `flow_table.c/h`, `syn_handler.c/h`, `translator.c/h`, `checksum.c/h`,
`log.c/h`, `meson.build`. This keeps the two nodes symmetric and lets us reuse the checksum/log
patterns and the parse→decide→modify pipeline shape verbatim.

### D6 — ServerNIC interface roles
The ServerNIC faces ClientNIC on one NIC and Server on the other. Mirroring the ClientNIC, the
**ClientNIC-facing interface is the DPDK port** (where the forwarded SYN/data arrive and where
translated server→client frames are sent back), and the **Server-facing interface is AF_PACKET**.
This matches the infra note that one secondary ENI is bound to vfio-pci. Final pin of which
physical ENI maps to which role is an infra/orchestration detail (see Open Questions).

### D7 — ServerNIC flow state machine
`PENDING` on SYN (have `V`, awaiting `real_isn`) → `ACTIVE` on real SYN-ACK (delta known).
While PENDING, client→server packets (including the client's ACK of the spoofed SYN-ACK) are
buffered; on transition to ACTIVE the buffer is flushed with ACKs rewritten. `ft_set_delta` is
idempotent for duplicate/retransmitted SYN-ACKs. This is the same buffering contract that exists
on the ClientNIC today, relocated to the ServerNIC.

### D8 — Probe verification as an explicit acceptance gate
Before trusting T8, emit a SYN from the ClientNIC with `ack=0xDEADBEEF`, capture on ServerNIC
ingress (tcpdump or the DPDK `--server-pcap` writer), and assert bytes 8–11 == `0xDEADBEEF`.
This is a one-time path validation; if it fails, fall back to T3 (out of scope to implement).

## Risks / Trade-offs

- **A TCP normalizer/middlebox rewrites ack on the forwarded SYN** → The probe gate (D8) catches
  this before we rely on T8; documented T3 fallback exists. Severity in pure VPC: low.
- **Real SYN-ACK now dropped at the ServerNIC, not the ClientNIC** → If the ServerNIC fails to
  drop it (e.g., wrong flow lookup), the client receives a *second*, untranslated SYN-ACK and the
  connection breaks. Mitigation: ServerNIC drops on the SYN-ACK path unconditionally once the
  flow is matched; warn-and-drop on unknown flow. Covered by integration tests.
- **Race: client ACK / first data arrives at ServerNIC before the real SYN-ACK** → buffering in
  the PENDING state (D7) handles this; buffer overflow drops with a warning (bounded at 64).
- **ClientNIC SYN retransmit with `ack=0` not re-stamped** → connection would carry a zero `V`
  to the ServerNIC and the delta would be wrong. Mitigation: re-stamp `V` on *every* forwarded
  SYN for a known flow (D3), not just the first.
- **Building a brand-new DPDK node (ServerNIC) adds deploy/build surface** → mirror the proven
  ClientNIC meson/build and infra user-data; reuse checksum/log/io patterns to limit novelty.
- **Two independent ISN/delta owners during rollout** → none: this is an internal data-plane
  contract with no on-the-wire compatibility requirement; deploy ClientNIC + ServerNIC together.

## Migration Plan

1. Land ServerNIC DPDK build + infra (binary present, ENI bound) without cutover.
2. Run the probe gate (D8) on the deployed path; confirm ack-num survives.
3. Deploy refactored ClientNIC (stamps `V`, stops translating) and ServerNIC translator together
   — they are a matched pair; do not run mixed (old ClientNIC translating + new ServerNIC
   translating would double-translate).
4. Run `experiments/zero-rtt-dpdk/run_experiment.sh`; validate 0-RTT establishment, data
   correctness, and that exactly one (spoofed) SYN-ACK reaches the client.
5. Rollback: run the preserved `clientnic/dpdk/` binary (full owner) and the Scapy/stateless
   ServerNIC. Because `clientnic/dpdk/` is never overwritten, rollback is a binary/orchestration
   selection, not a code revert; the change is isolated to the new `clientnic/dpdk-forwarder/`
   and `servernic/dpdk/` binaries plus infra user-data.

## Open Questions

- **ENI-to-role mapping on the ServerNIC**: which secondary ENI is bound to vfio-pci (DPDK port)
  vs. used as the AF_PACKET kernel interface, and the gateway MAC(s) for each egress. To be
  pinned during infra work.
- **Does the ServerNIC need RST suppression toward the Server** the same way the ClientNIC does
  toward the client? Likely yes for the Server-facing AF_PACKET interface; confirm during bring-up.
- **Capture mechanism for the probe gate** on the ServerNIC: reuse a `--server-pcap`-style DPDK
  writer or rely on tcpdump on the kernel interface. Decide during ServerNIC IO implementation.
