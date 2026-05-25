Tech Improvements

## [URGENT] RUNS Lab Connectivity {#runs-lab-connectivity}
- turn connection to runs lab more seamless — streamline VPN setup, Proxmox access, SSM commands
- Improve lab onboarding documentation and automation

## [URGENT] ServerNIC Forwarding Stability {#servernic-forwarding-stability}
- identify stable forwarding paths for consistent packet forwarding across 3-subnet topology
- Validate end-to-end packet flow under various network conditions
- Ensure no packet loss in ServerNIC translation

## Architecture & Implementation

- ISN passing from ClientNIC to ServerNIC (piggybacked in-between or compressed into SYN)
  - **T8 — SYN ack-num field** ✅ DONE — implemented in `clientnic/dpdk-forwarder/` + `servernic/dpdk/` (recommended for current single-ClientNIC/single-ServerNIC AWS VPC topology)

    **What:** ClientNIC overwrites bytes 8–11 (the ack-num field) of the forwarded SYN with `V` (the spoofed server ISN). ServerNIC reads `V` at SYN-time, optionally zeros the field before forwarding to Server.

    **Why it works:** RFC 9293 §3.10.7.2 — when ACK flag is clear, a compliant endpoint in LISTEN state does not read `ack_seq`. Linux `tcp_v4_rcv` → LISTEN path confirms this. The field is ignored input at the Server, not consumed input like `seq` (`C_isn`). This is the key distinction from Technique 1 (which cannot be used c→s because `seq` on a SYN carries `C_isn` which the server consumes).

    **Wire format — forwarded SYN (ClientNIC → ServerNIC → Server):**
    ```
    Before (client's real SYN):         After (ClientNIC rewrite):
      seq   = C_isn                        seq   = C_isn       (unchanged)
      ack   = 0                            ack   = V           (spoofed ISN)
      flags = SYN                          flags = SYN
                                           TCP checksum recomputed
    ```
    ServerNIC reads `pkt[TCP].ack` → `V`, then optionally `pkt[TCP].ack = 0` before forwarding to Server. ServerNIC uses `V` to compute the seq/ack translation delta once the real SYN-ACK arrives.

    **Implementation steps:**
    1. **ClientNIC `handlers.py`** — in the SYN forwarding path, after generating `spoofed_server_isn`, set `forwarded_pkt[TCP].ack = spoofed_server_isn`; delete IP+TCP checksums before `sendp()`. Apply on **every** forwarded SYN for the flow (not just the first), because the kernel retransmits SYNs with `ack=0`.
    2. **ServerNIC `forwarder.py`** — on eth1 ingress, detect SYN packets; extract `V = pkt[TCP].ack`; record `(4-tuple → V)` in a pending-flow table; zero the ack field and recompute checksum before forwarding to Server. On receipt of the real SYN-ACK, compute `delta = V - real_server_isn` and begin seq/ack translation.
    3. **Flow table state** — ServerNIC flow entry: `{spoofed_isn: V, real_server_isn: None, delta: None, state: PENDING|ACTIVE}`.
    4. **Probe verification** — before relying on T8 in any new deployment, run: send a SYN from ClientNIC with `ack = 0xDEADBEEF`; tcpdump on ServerNIC ingress; confirm bytes 8–11 equal `0xDEADBEEF` unchanged. If a normalizer zeros the field → fall back to T3.

    **Risk surface:**
    | Risk | Severity in demo AWS VPC | Mitigation |
    |---|---|---|
    | TCP normalizer (Cisco ASA, Palo Alto, F5) zeros ack on SYN | Low — no normalizer in pure VPC path | Probe pcap check before relying on it |
    | Anomaly IDS flags non-zero ack on SYN | Low — GuardDuty uses flow logs, not header bytes | Whitelist if needed |
    | AWS ENA / SRD modifies the field | Effectively zero — ENA is L2/L3 | None required |
    | `iptables conntrack` on Server drops/alters | Zero — conntrack ignores ack on SYN | None required |
    | SYN retransmit: kernel sends `ack=0`; ClientNIC must re-apply `V` | Always present | Match on 4-tuple for all SYNs, not just first |

    **T8 vs. T3 for this topology:**
    - T8: single 32-bit field overwrite, no Data Offset bump, no option-stripping risk. Lower complexity.
    - T3: 8-byte experimental option + Data Offset bump + NOP/EOL padding, killed by option-stripping middleboxes, survives TCP normalizers. Safer if deployment ever crosses third-party security appliances.
    - **Pick T8 for the current demo; fall back to T3 if probe pcap shows the field is being rewritten.**
- Shift sequence number translation responsibility between sides
- BlueField-3 architecture: eSwitch for translation, DPA for connection setup and ISN generation, ARM core for DPDK setup
- RSS-based flow sharding
- Buffer ingress packets before handshake completes
- Explore using Corundum: https://github.com/corundum/corundum
- QUIC-style Connection ID for fast routing — widen the ISN-passing channel (T3 or T6 from `generated-isn-compression-options.md`; T8's 4 bytes are too narrow) to carry a structured CID `{version, backend_id, tenant_id, flow_nonce, auth_tag}` instead of just `V`. Enables: stateless ServerNIC routing by CID lookup, multi-backend fan-out via CID-encoded backend hint, connection survival across client NAT rebind.
  - Only worth implementing when fan-out > 1 (multiple ServerNICs or backend pools) or multi-tenant routing becomes a requirement. For the current single-ClientNIC / single-ServerNIC topology, plain `V` via T3 or T8 is sufficient.