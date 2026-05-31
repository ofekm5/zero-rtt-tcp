## Why

Today the ClientNIC owns the entire 0-RTT state machine: it spoofs the SYN-ACK, learns the real server ISN from the real SYN-ACK that transits back through it, computes the seq delta, buffers client data, and rewrites seq/ack in **both** directions. The ServerNIC is a dumb forwarder. This concentrates all per-flow state and per-packet rewriting on the node closest to the client, which is the opposite of where we want it for the target BlueField/SmartNIC architecture (connection setup near the client, translation near the server).

T8 (`todos/tech-improvements.md`) gives us a clean way to move translation to the ServerNIC: the spoofed server ISN `V` can be carried to the ServerNIC inside the **ack-num field (bytes 8–11) of the forwarded SYN**. Per RFC 9293 §3.10.7.2 a listening endpoint ignores `ack_seq` when the ACK flag is clear, so the field is free real estate on a SYN and the Server never sees it (the ServerNIC zeros it before forwarding). This lets the ServerNIC compute the delta itself and become the sole translator.

## What Changes

- The existing ClientNIC DPDK implementation (`clientnic/dpdk/`) is **preserved unchanged** as the full-owner reference and rollback target. The T8 behavior lands in a **new parallel variant folder, `clientnic/dpdk-forwarder/`**, created by copying `clientnic/dpdk/` and then modifying it. Nothing in `clientnic/dpdk/` is overwritten.
- In the `dpdk-forwarder` variant the ClientNIC does **not** translate seq/ack. It spoofs the SYN-ACK to the client, stamps `V` into the forwarded SYN's ack-num field, and otherwise forwards every packet unchanged in both directions.
- The variant's flow table is slimmed to a lightweight per-flow record of `{client_mac, spoofed_server_isn, state}` — enough to re-stamp `V` on kernel SYN retransmits and to address server→client frames to the right client MAC. Delta tracking and the packet buffer are absent.
- In the variant the real SYN-ACK is **not** processed by the ClientNIC — it is dropped by the ServerNIC (which now needs the real ISN). The ClientNIC never sees it.
- A new **ServerNIC DPDK data plane** is built from scratch (`servernic/dpdk/` is currently WIP/README-only). It becomes the stateful translator:
  - On the forwarded SYN: read `V` from ack-num, zero the ack field, recompute the TCP checksum, record a PENDING flow keyed by the 4-tuple, forward the SYN to the Server.
  - On the real SYN-ACK from the Server: compute `delta = (V − real_server_isn) & 0xFFFFFFFF`, mark the flow ACTIVE, flush buffered client→server packets, and **drop** the SYN-ACK.
  - Client→server packets: subtract delta from ACK (buffer if delta unknown). Server→client packets: add delta to SEQ. Recompute checksums after every rewrite.
- A **probe-verification acceptance gate**: before relying on T8, send a SYN from the ClientNIC with `ack=0xDEADBEEF`, capture on ServerNIC ingress, and confirm bytes 8–11 arrive unchanged across the AWS VPC path (proves no middlebox normalizes the ack field).
- Scope is **DPDK only**. The Scapy stack is untouched by this change.

## Capabilities

### New Capabilities
- `isn-ack-num-channel`: The wire contract for carrying `V` in the forwarded SYN's ack-num field — exactly what the ClientNIC writes, what the ServerNIC reads/zeroes, retransmit handling, and the probe-verification gate that proves the AWS VPC path preserves the field.
- `servernic-dpdk-data-plane`: ServerNIC EAL init, dual-interface I/O (DPDK port toward ClientNIC, AF_PACKET toward Server, mirroring the ClientNIC split), busy-poll loop, and startup iptables/RST suppression.
- `servernic-flow-table-c`: ServerNIC stateful flow table — `{spoofed_isn(V), real_server_isn, seq_delta, state: PENDING|ACTIVE, server_mac}` plus per-flow packet buffering awaiting delta.
- `servernic-packet-pipeline-c`: ServerNIC parse/validate and ingress+flags-based routing (SYN, real SYN-ACK, c→s data, s→c data).
- `servernic-syn-handler-c`: ServerNIC SYN ingress (extract `V`, zero ack, checksum, create PENDING flow, forward) and real SYN-ACK handling (delta compute, flush, drop).
- `servernic-seq-translator-c`: ServerNIC bidirectional seq/ack rewriting with 32-bit wraparound, checksum recompute, and buffering when delta is unknown.
- `clientnic-forwarder-syn-spoof`: `dpdk-forwarder` SYN interception — spoofed SYN-ACK construction, random `V`, stamping `V` into the forwarded SYN's ack-num on **every** forwarded SYN (incl. retransmits), and the absence of any real-SYN-ACK processing.
- `clientnic-forwarder-flow-table`: `dpdk-forwarder` slim flow table — entry holds only `{spoofed_server_isn(V), state, client_mac}`; no `seq_delta`, `delta_valid`, or packet buffer.
- `clientnic-forwarder-pipeline`: `dpdk-forwarder` routing — eth0+SYN→spoof+forward; eth0 non-SYN→transparent c→s forward; eth1 any→transparent s→c forward (no SYN-ACK special case).
- `clientnic-forwarder-transparent-fwd`: `dpdk-forwarder` bidirectional transparent forwarding (Ethernet rewrite only, no seq/ack change, no data-path checksum recompute).

### Modified Capabilities
<!-- None. The existing ClientNIC capabilities (syn-ack-spoofer-c, seq-translator-c, flow-table-c, packet-pipeline-c, dpdk-data-plane) remain valid for the preserved clientnic/dpdk/ implementation and are intentionally left unchanged. The dpdk-forwarder variant introduces its own capabilities above. -->
- _none — existing ClientNIC specs are preserved alongside `clientnic/dpdk/`._

## Impact

- **Code (ClientNIC, new variant — `clientnic/dpdk/` untouched):** new folder `clientnic/dpdk-forwarder/`, seeded by copying `clientnic/dpdk/` then modifying `packet_processor.c/h` (stamp `V`, drop SYN-ACK handler), `translator.c/h` → transparent forward, `flow_table.c/h` (slim entry), `pipeline.c/h` (routing), `main.c`, `meson.build`. Reuses the existing `dpdk-data-plane` behavior (EAL/AF_PACKET/busy-poll/iptables) verbatim.
- **Code (ServerNIC, new):** `servernic/dpdk/` — new `main.c`, `io.c/h`, `pipeline.c/h`, `flow_table.c/h`, `syn_handler.c/h` (or `packet_processor.c/h`), `translator.c/h`, `checksum.c/h`, `log.c/h`, `meson.build`.
- **Infra:** `infra/dpdk/` ClientNIC user data builds the `dpdk-forwarder` variant (or selects which ClientNIC binary to run); ServerNIC user data builds/runs the new ServerNIC DPDK binary. Confirm a secondary ENI is bound to vfio-pci on the ServerNIC.
- **Experiments:** `experiments/zero-rtt-dpdk/run_experiment.sh` updated to launch the `dpdk-forwarder` ClientNIC + the ServerNIC DPDK binary; capture/validation expectations move (real SYN-ACK now dropped at ServerNIC, not ClientNIC).
- **Docs:** new `clientnic/dpdk-forwarder/README.md` explaining the variant and how it differs from `clientnic/dpdk/`; update `clientnic/dpdk/README.md` to point at the variant; `servernic/dpdk/README.md`; and `CLAUDE.md` (module structure + architecture: document that two ClientNIC DPDK variants coexist and the translation-shift design).
- **No change** to Client/Server apps (transparency preserved), to the Scapy stack, or to the existing `clientnic/dpdk/` code and its specs.
