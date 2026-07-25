## Context

The T8 data plane splits 0-RTT across two middleboxes: ClientNIC spoofs the SYN-ACK and stamps a value `V` into the SYN's ack-num field; ServerNIC is the sole stateful translator, deriving `delta = spoofed_isn - real_isn` and rewriting every subsequent packet. Today both run as x86 DPDK binaries.

Moving ServerNIC to the BlueField-3 is only worthwhile if the rewrite stops being software. Live inspection of `bluefield-runs3-dpu` establishes the constraints:

- e-switch in `switchdev`, card in `EMBEDDED_CPU` mode, DOCA 3.0.0058, DPDK under `/opt/mellanox/dpdk`
- 8× Cortex-A78AE, 15 GB — fewer and slower cores than the x86 SmartNICs they would replace
- `pf0hpf` is the **only** data path: `p0` has no carrier and the card has no `p1`

That last constraint is what makes this a single-port design. `ens16f0np0` on the x86 host VM and `pf0hpf` on the ARM are two ends of one link, so the return leg goes back out the port the packet arrived on.

## Goals / Non-Goals

**Goals:**

- Post-handshake packets are matched, rewritten, and returned entirely by the e-switch.
- The ARM control plane sees SYN, SYN-ACK, FIN, and RST — and nothing else.
- Hardware rule count tracks live connections, so long-running operation does not exhaust rule capacity.
- The existing x86 ServerNIC keeps working, unmodified.

**Non-Goals:**

- ClientNIC changes, lab deployment plumbing, DOCA Flow, dual-BlueField topologies, `p0` cabling, and load testing — all enumerated in `proposal.md` Non-Goals.
- Eliminating software buffering of pre-delta packets. A hardware rule cannot cover packets that arrive before the rule can exist.

## Decisions

### D1 — The delta is known only at SYN-ACK, so the rule is installed then

The flow's lifecycle has three phases, and the hardware rule can only exist for the third:

| Phase | Trigger | Who handles packets |
|---|---|---|
| Pre-delta | SYN seen, real SYN-ACK not yet arrived | ARM software, buffering |
| Rule install | Real SYN-ACK arrives, `delta` computed | ARM software, one-time |
| Steady state | Rule live | e-switch hardware |

Packets that arrive during phase 1 are buffered and rewritten in software once, at the moment of flush. This is unavoidable — the delta does not exist yet — and it is also bounded, because the window is one RTT to the server. Attempting to avoid it would require guessing the server's ISN.

### D2 — Two rules per flow, one per direction

The T8 translation is asymmetric: client→server packets need `ACK -= delta`, server→client packets need `SEQ += delta`. These are different fields and different operations, so a single rule cannot express both. Each flow installs a rule pair keyed on the reversed 5-tuple, and teardown removes both.

This makes SC2's "one hardware rule set per flow" concretely two rules, and SC5's leak check a count that must return to its baseline.

### D3 — Teardown is driven by FIN/RST punt, with rule count as the observable

Hardware rules do not expire on their own. If teardown depended on a software timer or on observing the connection close in the data path, it would not work here — the data path is hardware and reports nothing per-packet. So FIN and RST must remain punted to the ARM specifically to drive rule removal, even though they carry no translation work the hardware could not do.

`flow list 0` returning to its pre-run count is therefore not a nice-to-have check; it is the only external evidence that teardown works, which is why it is SC5 rather than a design note.

### D4 — Sibling target, shared modules by reference

`src/servernic/bluefield/` is its own meson target. `flow_table.c`, `syn_handler.c`, and `checksum.c` are referenced from `src/servernic/dpdk/` rather than copied, because they encode the T8 protocol contract — V extraction, delta arithmetic with 32-bit wraparound — that must not diverge between the two deployments. `io.c`, `offload.c`, and `pipeline.c` are new, because the port model and the dispatch set are genuinely different.

`translator.c` is deliberately **not** reused. Its per-packet rewrite is what the hardware replaces; carrying it over would invite the software path to quietly stay alive.

### D5 — The exception path must be observable, or SC3 is unmeasurable

SC3 asserts data packets never reach an ARM core. Proving a negative requires the software side to count what it receives, broken down by classification. The application therefore maintains a counter of packets received that were **not** SYN/SYN-ACK/FIN/RST; that counter staying at zero while rule counters climb is the measurement. Without this instrumentation the criterion could only be argued, not measured.

## Alternatives Considered

### A. Rule installed at SYN-ACK, two rules per flow, FIN/RST-driven teardown — **recommended**

The control plane punts handshake packets, computes the delta when the real SYN-ACK arrives, installs a directional rule pair, and removes it when the connection closes.

*Tradeoffs*: Matches the T8 state machine exactly — the delta genuinely does not exist before SYN-ACK, so nothing is lost by waiting. Rule count is bounded by live connections and externally observable. Costs: two rules per flow doubles hardware rule consumption versus a hypothetical single-rule design, and a dropped FIN leaks a rule pair until something else reclaims it.

*Verdict*: **Recommended** — it is the only option whose rule lifetime is tied to something the hardware path can actually signal.

### B. Wildcard rule installed at SYN, refined after SYN-ACK

Install a coarse rule at SYN time to capture the flow immediately, then replace it with the exact-delta rule once SYN-ACK arrives.

*Tradeoffs*: Would shrink the software buffering window, since packets would hit hardware sooner. But the rule installed at SYN cannot apply a correct delta — the delta is unknown — so it could only punt or drop, which is what the default path already does. It adds an install/replace cycle per flow for no behavioural gain.

*Verdict*: **Rejected** — it optimises a window that cannot be optimised, because the missing input is the server's ISN, not the rule.

### C. Timer-based rule expiry instead of FIN/RST teardown

Age rules out after an idle period rather than punting FIN and RST.

*Tradeoffs*: Removes FIN/RST from the exception path entirely, so the ARM sees strictly less traffic, and it is robust against dropped FINs. But rules would outlive their connections by the timeout, inflating rule count under connection churn — precisely the regime the 100k-connection goal targets. It also requires per-rule age queries against hardware to find expiry candidates, which is polling work the ARM would do continuously.

*Verdict*: **On the shelf** — a reasonable robustness addition *alongside* FIN/RST teardown to reclaim leaked rules, but wrong as the primary mechanism because rule count would no longer track live connections.

## Risks / Trade-offs

- **The spike returns NO** → this change is invalidated, not reduced. It is recorded as a blocking dependency in `proposal.md` rather than a risk to mitigate, because no mitigation exists.
- **The spike returns PARTIAL (return leg fails)** → the egress action changes from returning out `pf0hpf` to forwarding to a Scalable Function representor. `offload.c` is the only affected module; the control plane, flow table, and teardown logic are unchanged. This is why the egress target is a single point in the rule composition rather than spread through the code.
- **Dropped FIN leaks a rule pair** → rule count drifts upward under lossy conditions. Mitigated by making rule count externally observable (SC5) so the leak is detectable, with Alternative C available as a follow-up reclaim mechanism if measurement shows it matters.
- **Hardware rule capacity is exhausted at scale** → not measured by this change, and out of scope. Recorded here because the two-rules-per-flow decision in D2 halves whatever the ceiling turns out to be, and the 100k-connection goal will meet it.
- **Shared modules diverge between the two targets** → `flow_table.c` / `syn_handler.c` / `checksum.c` are referenced, not copied, so a T8 protocol fix lands once. The cost is that a change to those modules must build for both targets.
- **SC3 cannot be measured without instrumentation** → addressed by D5. Without the software classification counter the criterion would be unfalsifiable, which is a worse failure than it being hard to satisfy.

## Migration Plan

Additive — nothing is replaced. `src/servernic/dpdk/` and its AWS deployment continue to work throughout, and the new target is built and run only on the DPU.

**Rollback**: stop the DPU binary; the x86 path is unaffected because it was never modified. Hardware rules installed by a killed process are removed by flushing the port's flow rules, which the restore path from the companion spike already exercises.

## Open Questions

- **Does `rte_flow` on this DOCA build express both directions' rewrites as a symmetric rule pair, or does the ack-num modification require different action syntax than seq-num?** The spike proves one direction; the second is assumed symmetric and must be confirmed during implementation.
- **What is the hardware rule capacity on this BF-3, and is it per-port or global?** Not needed for correctness, needed before any scale claim.
- **Should buffered pre-delta packets be flushed through software rewrite, or re-injected after the rule is live so hardware rewrites them?** The former is simpler and matches the existing x86 implementation; the latter would remove `checksum.c` from the hot path entirely. Deferred to implementation, as it does not change any success criterion.
