---
type: Raw Source
title: "0-RTT Telemetry Review — does the measurement prove the claim?"
description: "Published artifact reviewing the 2026-08-04 baseline-vs-DPDK run pair: what the telemetry change bought, what the iperf→loadgen migration cost, and what remains open."
resource: https://claude.ai/code/artifact/882a2717-0bee-4c21-ba06-23f50921341a
tags: [experiments, measurement, artifact]
timestamp: 2026-08-08T18:53:12+03:00
---

Verbatim capture of the artifact's content. Do not edit — corrections belong in
[[wiki/Measurement Methodology]].

Run pair: 2026-08-04, baseline vs DPDK. Load: 2000 conns / 500 per sec / 4 ports
/ 1 KB. Emulated RTT: 100 ms (server egress). Result: 2000/2000 OK on both stacks.

## 01 — The verdict

**Proven — −100.6 ms.** Mean `send_unlock`: 100.835 ms → 0.226 ms. The client's
application stops blocking a full emulated RTT earlier, across 2000 flows, p99
0.42 ms. The mechanism does exactly what it was designed to do.

**Not what you'd hope — −0.09 ms.** Mean flow completion time: 201.636 ms →
201.546 ms. 0-RTT doesn't *remove* the round trip — it relocates the wait from
the client app to the ServerNIC, which holds client data until the real SYN-ACK
reveals the ISN.

**Unexplained — +323 ms.** Worst-case FCT: 213 ms baseline → 537 ms 0-RTT, while
p99 stayed *tighter* than baseline. Confined to ≤20 of 2000 flows. Cause not
established — blocking for any 100k-scale run.

> So: yes, the solution improves a real, measurable thing — and the honest
> headline is **"0-RTT eliminates one RTT of application blocking time"**, not
> "connections complete a round-trip sooner." Both are now measured; only the
> first is true.

## 02 — Where the round trip went

Both stacks complete at ~201.5 ms. The difference is *who* waits: baseline blocks
the client's `connect()`; 0-RTT returns immediately and parks the first segments
in the ServerNIC's PENDING flow entry until the real SYN-ACK arrives
(`src/servernic/dpdk/syn_handler.c`). That distinction is invisible unless
`send_unlock` and `fct` are reported separately — which is precisely what the
telemetry change bought.

Timeline: baseline blocks in `connect()` for 100 ms, receives the real SYN-ACK
and first payload at 100 ms, completes at 201.6 ms. 0-RTT sends SYN, spoofed
SYN-ACK and first payload at 0.23 ms, holds data at the ServerNIC awaiting the
real ISN for 100 ms, then completes at 201.5 ms. "This 100 ms moved out of the
application — it did not disappear from the network."

## 03 — What changed in the telemetry, and why it was necessary

**Load shape (`loadgen.py`, `measure.sh`) — arrivals are paced, not burst.** All
`--parallel` connections used to be handed to one `asyncio.gather()`, so every
flow's latency included queueing behind every other SYN. Connection *i* now
launches at `t0 + i/rate` on an absolute timeline, with an `Arrival:` line
reporting achieved vs requested rate. *Why:* the burst run reported the
forwarder's SYN service rate — a scaling property — not the round trip the spoof
removes. 100k connections become 100,000 independent latency samples instead of
one stress event.

**Payload (`LOAD_BYTES`, 1 MB → 1 KB) — one segment per flow.** With window
scaling off and netem in place, 1 MB costs roughly 16 RTTs of transfer. FCT is
now ≈ handshake + 1 RTT. *Why:* the one RTT that 0-RTT saves was ~6% of flow
completion time — under run-to-run noise. The signal existed; the payload buried
it.

**Emulated RTT (`endpoint.sh`, `NETEM_RTT_MS`) — full delay on server egress;
client egress left clean.** Previously 50 ms of `netem` sat on *both* endpoints.
A root qdisc delays egress only, so the SYN paid the client's own 50 ms before
the spoofed SYN-ACK could return — halving the observable gain, on a LAN hop
0-RTT structurally cannot remove. The whole 100 ms now sits on server egress, and
the qdisc is *read back* on both nodes, failing the run on mismatch. *Why:* two
compounding faults. The placement systematically under-reported a correct
implementation — and `tc` was never installed at all, so every command was
swallowed by `2>/dev/null || true`. Every run in this repo's history labelled
"50 ms netem" actually measured the ~1.5 ms intra-VPC RTT, where no benefit is
observable in principle.

**Reporting (`run_core.sh`, `endpoint.sh`) — `send_unlock` promoted; four dead
rows deleted.** The latency block is tiered — Primary (client-observed
`send_unlock`), Secondary (throughput-bound FCT and `server_gap`), Data-plane
internal (in-app rdtsc). Four rows that piped client stdout into the summarizer
for `ttfb`/`fct` were removed: `loadgen.py` emits no `metric=` lines, so they had
printed *no samples found* on every run since the migration. *Why:* a
permanently-empty metric row trains readers to ignore empty metric rows — which
is exactly how the in-app TTFB gap survived four reports.

**Comparability (`baseline-tcp`, shared `endpoint.sh`) — the baseline is
instrumented, by the same code.** The baseline stack captured no pcaps and never
ran the analyzer, so it produced no `send_unlock`, FCT or `server_gap` to compare
against. It now runs the identical `endpoint_capture_start/stop → analyze →
latency_summary` functions, and both reports print a Load Parameters table.
*Why:* the central claim is a *difference between two stacks*, and only one was
instrumented — the claim was unprovable in either direction.

**Isolation (`run_stress.sh`) — capacity runs are a separate entry point.**
`LOAD_RATE=0` plus an unclamped concurrency ceiling, behind a banner stating what
may and may not be concluded, echoed as a `CAPACITY RUN` warning in the report.
*Why:* a 67% success rate caused by endpoint RAM exhaustion says nothing about
whether sequence-number translation is correct.

## 04 — Do the metrics actually work?

| Signal | State | Evidence |
|---|---|---|
| `send_unlock` | Working | 2000 samples per stack, p99 within 0.2 ms of mean on the 0-RTT side. Saving of 100.61 ms against a modelled 100 ms RTT — the numbers agree with the model. |
| `fct` (pcap) | Working | Full distribution on both stacks. It's the metric that exposed the relocation-not-removal result, so it's earning its place even though it shows no win. |
| `server_gap` | Working | Mean 0.818 → 0.359 ms, max 12.358 → 0.756 ms. Confirms the server's own response latency isn't the source of the FCT tail. |
| clientnic / servernic TTFB | Dark | Both still report *no samples found*; the harness suspects the deployed binary predates the rdtsc instrumentation. This is the only view that can localize latency *inside* the data plane. |
| client stdout ttfb/fct | Removed | Correctly deleted rather than fixed — `loadgen.py` never emitted them. Nothing is lost, but no client-side *application*-level TTFB exists now; the claim rests entirely on pcap-derived timing. |
| NIC logs (grep counts) | Truncated | Both NIC logs hit the 24 KB SSM cap (24,355 bytes), so every count the harness reports covers an arbitrary prefix — under 100 of 2000 flows. It actively obstructed the FCT-tail diagnosis, and the stack has since been terminated. |

## 05 — What the iperf migration cost

The move to `loadgen.py` was the right call for a latency claim — asyncio gives
per-connection timestamps and true paced arrivals that iperf cannot. These are
the real downsides:

1. **Throughput is no longer measured at all.** The 1 KB default makes every flow
   a latency probe. The 2026-07-14 finding — per-flow throughput through the
   0-RTT path running ~100× below the kernel baseline — is currently
   unmeasurable with default knobs, and that is arguably the most serious open
   question about the design. "0-RTT that costs 100× throughput is not a win"
   still stands unresolved.
2. **The measuring instrument is now homegrown.** iperf's numbers were
   third-party and independently reproducible; `loadgen.py` self-reports its own
   timings from a Python event loop. Under high arrival rates, GIL contention and
   scheduler delay land inside the measured interval — the achieved-rate line
   catches gross degradation, but not a few ms of per-sample inflation.
3. **Historical comparability is broken.** Every pre-migration report used iperf2
   or iperf3. Nothing before 2026-08-04 can be compared against anything after
   it — and since `tc` was never installed either, the entire prior corpus
   measured a different network as well as a different tool. Treat 2026-08-04 as
   sample #1, not as a continuation.
4. **One 1 KB write never exercises congestion control.** Flows now complete
   inside one RTT-plus-handshake, so retransmit behavior, window growth and
   sustained-rate translation are untested by the default profile. A data-plane
   regression that only appears mid-stream would not show up — which may be
   relevant to the 537 ms tail.
5. **iperf-shaped naming survives the code.** `LOAD_*` knobs are internally
   consistent, but the GitHub Actions inputs are still `iperf_parallel` /
   `iperf_ports` / `iperf_timeout` (deliberately, as an external API surface),
   and `analyze_metrics.py --iperf-csv` is dead code carrying 6 live tests.
6. **The pacing target is a ceiling, not a guarantee.** When the loop falls
   behind, the delay goes non-positive and connections spawn immediately — a
   paced run degrades toward a burst run silently. The single `Arrival:` line is
   the only thing standing between that and a latency number contaminated by
   queueing.

## 06 — Every metric in the comparison, in brief

**`send_unlock`** (primary) — 100.835 → 0.226 ms mean, −100.61 ms. Time from the
client's SYN leaving the wire to its first payload byte leaving the wire — i.e.
how long the application sat inside `connect()` before it could send. *Reads as:*
the direct, isolated measure of what the spoofed SYN-ACK buys. It is the only
metric that proves 0-RTT works, and the first one to collapse toward
`server_gap` if a data-plane change ever breaks the spoof.

**`fct` — mean / p50 / p99** (secondary) — 201.636 → 201.546 ms, −0.09 ms. Flow
completion time from the endpoint pcaps: first SYN to last packet of the flow. At
p99 the 0-RTT stack is actually *tighter* than baseline (201.638 vs 202.833 ms).
*Reads as:* the honest ceiling on the claim. The RTT is relocated to the
ServerNIC's buffer-and-flush path, not removed from the network.

**`fct` — max** (open) — 213.254 → 536.628 ms, +323 ms. The worst flow in each
run. Baseline sits 10 ms above its own p99; the 0-RTT stack sits 335 ms above its
own p99, so the regression is confined to ≤20 of 2000 flows. *Reads as:*
unexplained. Ruled out: the handshake and the server's response, since both
0-RTT tails beat baseline. Working hypothesis is one lost segment paying a 200 ms
`TCP_RTO_MIN` plus a ~100 ms retransmit trip (≈300 ms vs 335 ms observed) —
arithmetic that fits and nothing that proves it. At 100k scale this 1% becomes
1000 flows and would dominate the aggregate.

**`server_gap`** (secondary) — 0.818 → 0.359 ms mean, max 12.358 → 0.756. Delay
between the server receiving a request and emitting its response, measured at the
server-side pcap. *Reads as:* a control variable. Both tails improved under
0-RTT, which is how the FCT tail was localized to the segment between "first
payload leaves" and "flow completes" rather than to server-side load.

**clientnic / servernic TTFB (in-app)** — no samples. rdtsc-based timing taken
inside each forwarder. *Reads as:* nothing, currently. Restoring it is what would
let you say *where* the 335 ms tail accrues instead of inferring it.

**arrival rate · connections OK** (validity gate) — 2000/2000 both stacks. *Reads
as:* not a result — the precondition for the others being readable.

## 07 — What would make the claim airtight

- **blocking** — Resolve the FCT tail before any 100k run. Three concrete steps:
  `grep -c` on the node instead of cat-ing a 24 KB prefix, capture `nstat`
  retransmission counters (one number kills or confirms the RTO theory), and use
  `--detail-out` to name the slow flows and pull just those 4-tuples from the pcaps.
- **high** — Restore in-app NIC TTFB. Without it, nothing can attribute latency
  to the data plane rather than the network.
- **high** — Run one deliberate throughput comparison — same tool, stream count
  and transfer size on both stacks — so the 100× question from 2026-07-14 gets an
  answer rather than an absence.
- **high** — Fix NIC-log retrieval past the 24 KB SSM cap, or every count in
  every report stays scoped to an arbitrary prefix.
- **design** — Decide whether FCT is improvable at all. Forwarding client data
  before the real ISN is known is a change to the T8 translation scheme, not a
  tuning exercise — spec it before more measurement work.
- **scale** — Run both stacks at full scale (`LOAD_PARALLEL=100000`,
  `LOAD_RATE=2000`). Only the 2000-connection smoke exists.

Sources cited by the artifact: `experiments/measurement-methodology-review.md`
(A–D, all implemented), `experiments/insights.md` (entries 2026-08-04),
`baseline-report-2026-08-04-200506.md` and the matching DPDK run,
`open-sessions.txt`.
