---
type: Wiki Entry
title: "Measurement Methodology Review — Load Shape and the 0-RTT Claim"
description: "How the experiments generate load and measure latency, whether that methodology supports the 0-RTT claim, and where the emulated WAN must sit."
tags: [experiments, methodology, netem]
timestamp: 2026-08-08T18:53:23+03:00
---

Source: `experiments/measurement-methodology-review.md`
See also: [[wiki/Load Generation and Think Time]], [[wiki/FCT Tail Investigation]]

# Measurement Methodology Review — Load Shape and the 0-RTT Claim

**Date:** 2026-08-04
**Scope:** how the experiments generate load and measure latency, and whether
that methodology can support the project's central claim (0-RTT eliminates one
RTT from connection establishment).
**Status:** all items implemented (A–D). Verification at the end.

Companion documents: `experiments/insights.md` (per-run findings),
`docs/capacity-model.md` (hardware ceilings).

---

## Summary of findings

1. **iperf is no longer used in the live path.** `run_core.sh` →
   `measure.sh:run_ttfb_measurement` → `experiments/utils/loadgen.py`. What
   survives is iperf-shaped *naming* (`LOAD_*`) and, until this review, the
   iperf-shaped *load pattern*.
2. **The burst load could not demonstrate the claim.** All connections were
   created in one event-loop iteration, so every flow's measured latency
   included queueing behind every other SYN. The run reported the forwarder's
   SYN service rate, not the round-trip the spoof removes.
3. **The payload size buried the signal.** 1 MB per connection with window
   scaling disabled costs ~16 RTTs of transfer; the one RTT 0-RTT saves was
   ~6% of flow completion time — below run-to-run noise.
4. **Emulated latency was on the wrong leg**, halving the observable gain (§B1).
5. **No baseline comparison existed.** The baseline stack captures no pcaps and
   never runs the analyzer, and four latency rows in both stacks read a stream
   that contains no metrics at all (§B3, §C1).

**Reframe:** with arrivals spread, 100k connections stop being a stress event
and become 100,000 independent latency samples. Scale is retained as
*statistical power* rather than as saturation, and remaining failures become
signal about the translation mechanism instead of about endpoint RAM.

---

## A. Load shape — remove the burst, keep the scale ✅ IMPLEMENTED

### A1 ✅ Arrival-rate knob (`--rate <conns/sec>`)

**File:** `experiments/utils/loadgen.py`

**Was:** every `--parallel` coroutine was created and handed to
`asyncio.gather()` in one pass, so all connections reached the wire
effectively simultaneously.

**Now:** `run_client()` takes a `rate` parameter. Connection `i` is scheduled
at `t0 + i/rate` on an **absolute** timeline rather than sleeping `1/rate`
between spawns, so per-sleep overhead cannot accumulate into drift across a
100k-connection run. When the loop falls behind, the delay goes non-positive
and the spawn happens immediately — the requested rate is a ceiling, not a
guarantee.

**Improves:** makes per-connection latency attributable to the network path
instead of to queue depth.
**Needed because:** without pacing the experiment measures the data plane's SYN
service rate, which is a scaling property, not the protocol behavior under test.

Also added: an `Arrival:` output line reporting achieved vs requested rate. A
large gap means the pacing target was unreachable and the run silently degraded
toward a burst — previously undetectable.

`--rate 0` preserves the old burst path for deliberate stress runs.

### A2 ✅ Pass the concurrency ceiling

**Files:** `experiments/utils/measure.sh`, `experiments/nodes/client.sh`

**Was:** `--concurrency-limit` existed in `loadgen.py` but was never passed by
any caller; `limit = args.concurrency_limit or args.parallel` made it a no-op.

**Now:** both callers pass it, via a new `LOAD_CONCURRENCY` knob (default 2000).

**Improves:** bounds endpoint fd/RAM pressure independently of pacing.
**Needed because:** per `insights.md`, a t3.micro holds ~20–30k sockets;
exceeding that produced connection failures that were endpoint exhaustion
misread as data-plane defects.

Used **with** A1, not instead of it: a semaphore self-clocks arrivals off
completion time, which couples arrival rate to throughput and re-contaminates
the latency measurement.

### A3 ✅ Payload default cut to one segment

**Files:** `experiments/utils/loadgen.py` (`--bytes`),
`experiments/utils/measure.sh` (`LOAD_BYTES`), `experiments/nodes/client.sh`

**Was:** 1048576 (1 MB), inherited from `iperf -n 1M`.
**Now:** 1024 (one segment).

**Improves:** makes flow completion time ≈ handshake + 1 RTT, where the saved
RTT is the dominant term rather than a rounding error.
**Needed because:** with `tcp_window_scaling=0` and 50 ms netem, one flow is
capped near 640 KB/s, so 1 MB costs ~16 RTTs of transfer. `measure.sh` already
carried a comment acknowledging this.

Raise `LOAD_BYTES` only for a deliberate throughput comparison — never for a
latency claim.

### Supporting harness changes ✅

- **Pacing floor guard** (`measure.sh:run_ttfb_measurement`): computes
  `parallel / rate × rounds` and warns when `LOAD_TIMEOUT` is below it.
  Without this, a correctly-paced run is cut off mid-round and reported as a
  client failure.
- **Burst-mode warning**: `LOAD_RATE=0` now emits an explicit warning, in both
  the orchestrated and interactive paths, that the run's latency numbers
  include SYN queueing and are not 0-RTT results.
- **Run banner** (`run_core.sh`): reports the full load shape
  (`LOAD_PARALLEL`, `LOAD_BYTES`, `LOAD_RATE`, `LOAD_CONCURRENCY`).
- **`_build_parser()`** extracted from `loadgen.py:main()` so defaults are
  unit-testable.
- **Docs**: `.claude/skills/run-experiment/references/troubleshooting.md` —
  the `LOAD_TIMEOUT / LOAD_PARALLEL` section now covers `LOAD_RATE` coupling.

### Verification

- `pytest experiments/utils/tests/` → **57 passed** (12 in `test_loadgen.py`,
  incl. 4 new pacing tests and 2 default-guard tests).
- `bash -n` clean on `measure.sh`, `run_core.sh`, `client.sh`.
- Live loopback, 500 conns × 2 ports: paced → **249 conn/s achieved over
  2.007 s**, 500/500 ok; unpaced → **295k conn/s**, 0.641 s, 500/500 ok.

### Defaults after A1–A3

| Knob | Default | Rationale |
|---|---|---|
| `LOAD_PARALLEL` | 100000 | unchanged — now sample count, not stress |
| `LOAD_PORTS` | 4 | unchanged — ephemeral port headroom |
| `LOAD_BYTES` | 1024 | one segment; FCT ≈ handshake + 1 RTT |
| `LOAD_RATE` | 2000 conn/s | 100k conns → ~50 s spawn floor per round |
| `LOAD_CONCURRENCY` | 2000 | in-flight ceiling, well under t3.micro limits |
| `LOAD_TIMEOUT` | 1800 s | must exceed the pacing floor above |

**Known asymmetry:** the `loadgen.py` CLI defaults to `--rate 0` (unpaced) so
ad-hoc invocations stay unsurprising; the harness (`measure.sh`) is what opts
into pacing. Open question whether the CLI should default to paced too.

---

## B. Make the 1-RTT saving observable ✅ IMPLEMENTED

### B1 ✅ Full emulated RTT on the Server egress; Client egress left clean

**Files:** `experiments/utils/endpoint.sh` (new, `endpoint_tune()`),
`experiments/utils/run_core.sh` (inline block replaced by the call)

**Was:** `tc qdisc add dev eth0 root netem delay 50ms` on **both** endpoints. A
root qdisc delays **egress only**, giving:

| Leg | Delay |
|---|---|
| Client → ClientNIC | 50 ms |
| ClientNIC → Client | 0 ms |
| ClientNIC ↔ ServerNIC | 0 ms |
| Server → ServerNIC | 50 ms |

Baseline `connect()` = 100 ms (full RTT), but 0-RTT `connect()` = 50 ms — the SYN
still paid the client's egress before the spoofed SYN-ACK returned instantly.
**The measured saving was half the emulated RTT.** Worse, that 50 ms sat on the
client↔its-own-NIC hop — a LAN hop in the real topology, one 0-RTT structurally
cannot remove.

**Now:** the whole `NETEM_RTT_MS` (default 100) sits on the **Server** egress;
the Client's qdisc is cleared and left clean.

    Baseline: SYN out 0 ms, SYN-ACK back 100 ms -> connect = 100 ms
    0-RTT:    SYN out 0 ms, spoofed SYN-ACK 0 ms -> connect ~ 0
    saving  = 100 ms = the full modeled RTT

Client-observed RTT is unchanged for both stacks, so the baseline is not made
easier — only the attribution is corrected.

**Improves:** measured gain equals the modeled gain instead of half of it.
**Needed because:** the old placement was a topology modeling error that
systematically under-reported a correct implementation.

Also added: **post-condition verification.** `endpoint_tune()` reads back
`tc qdisc show` on both endpoints and fails the run if the server lacks netem or
the client has it. A silently-failed `tc` previously turned the whole run into an
intra-VPC measurement where one RTT is ~1.5 ms and no benefit is observable at
all (`insights.md`, 2026-07-14) — with nothing in the output to say so.

**Note:** `insights.md` prescribes netem on the *middle* legs; DPDK/vfio-pci
ownership of those ports makes that impossible, so server-side placement is the
achievable equivalent. **Correct for `send_unlock` only** — it also guarantees
FCT cannot improve. See §E.

### B2 ✅ `send_unlock` promoted to the headline metric

**Files:** `experiments/utils/endpoint.sh` (`endpoint_latency_summary()`),
`experiments/utils/run_core.sh`, `experiments/dpdk/run_experiment.sh`,
`experiments/baseline-tcp/run_experiment.sh`

The latency block is now explicitly tiered:

```
  -- Primary: time-to-first-byte the client actually experiences --
  Send unlock   : ...
  -- Secondary (throughput-bound; not evidence about the handshake) --
  Pcap FCT      : ...
  Server gap    : ...
  -- Data-plane internal (in-app rdtsc, not client-observed) --
  clientnic TTFB (in-app) : ...
  servernic TTFB (in-app) : ...
```

**Improves:** the headline number isolates the handshake instead of blending it
with transfer time.
**Needed because:** `open_connection()` returns on the (spoofed) SYN-ACK and the
first write follows immediately, so `send_unlock` measures exactly what the
spoof buys. FCT and `server_gap` move with payload size, link speed and loss —
a change in either is not by itself evidence about the handshake.

### B3 ✅ Dead client-stdout metric rows removed

**Files:** `experiments/utils/run_core.sh`,
`experiments/baseline-tcp/run_experiment.sh`

**Was:** four rows piped `CLIENT_STDOUT` into `summarize_metric` for `ttfb` and
`fct`. `loadgen.py` emits no `metric=` lines at all, so all four printed
`no samples found` on every run since the iperf→loadgen migration.

**Now:** removed.

**Improves:** no output that reads as missing data when it is a wiring bug.
**Needed because:** a permanently-empty metric row trains readers to ignore
empty metric rows.

---

## C. Comparability with baseline ✅ IMPLEMENTED

### C1 ✅ Baseline now captures and analyzes endpoint pcaps

**File:** `experiments/baseline-tcp/run_experiment.sh`

**Was:** no tcpdump, no analyzer — the baseline produced no `send_unlock`, FCT or
`server_gap` at all, so the 0-RTT numbers had nothing to be compared against.

**Now:** the baseline calls `endpoint_capture_start` -> `endpoint_capture_stop` ->
`endpoint_analyze` -> `endpoint_latency_summary`, and its report gained an
**Endpoint Packet Analysis** section plus a **Load Parameters** table.

**Improves:** produces the other half of the comparison.
**Needed because:** the project's central claim is a *difference* between two
stacks, and only one was instrumented — the claim was unprovable in either
direction.

### C2 ✅ Both stacks share one endpoint-setup implementation

**File:** `experiments/utils/endpoint.sh` (sourced by `run_core.sh` and by
`baseline-tcp/run_experiment.sh`)

Rather than documenting that the two runs *should* match, `endpoint_tune()`,
`endpoint_capture_start/stop()`, `endpoint_analyze()` and
`endpoint_latency_summary()` are literally the same functions in both. Load
knobs already came from the single `measure.sh` source. Both reports now print
the parameter table, so a mismatch is visible on the page.

**Improves:** the two runs differ in exactly one variable — the data plane.
**Needed because:** `insights.md` (2026-07-14) records a cross-comparison
already invalidated by mismatched tooling, stream counts and transfer sizes;
two copies of setup code drift, one shared function cannot.

---

## D. Separate the scaling question out ✅ IMPLEMENTED

### D1 ✅ Capacity runs are a separate entry point

**File:** `experiments/dpdk/run_stress.sh` (new)

Sets `LOAD_RATE=0` and lifts `LOAD_CONCURRENCY` to `LOAD_PARALLEL` (so the
semaphore cannot quietly convert the burst back into a paced run), prints a
banner stating what may and may not be concluded, then execs the normal
orchestrator. `run_core.sh` emits a matching `CAPACITY RUN` warning, and the
DPDK report writer prefixes the report with a blockquote to the same effect.

**Improves:** keeps a legitimate engineering result without letting it
contaminate the protocol result.
**Needed because:** a 67% success rate caused by endpoint resource exhaustion
says nothing about whether sequence-number translation is correct.

### D2 ✅ Dead iperf code removed

Deleted `src/client-app/iperf_client.sh` and `src/server-app/iperf_server.sh`
(neither was invoked; the client script carried three `-P 100000` cases —
100k pthreads in one process). Both READMEs rewritten around `loadgen.py`, and
the stale `pkill -f 'iperf -s'` in the baseline orchestrator (which killed
nothing, since the baseline server is `loadgen.py`) now targets `loadgen.py`.
Same fix applied in `experiments/scapy/run_experiment.sh` and `run_core.sh`.

Prose describing behavior that no longer exists was corrected in `README.md`,
`CLAUDE.md`, `.claude/skills/run-experiment/SKILL.md`,
`references/test-scripts.md` and `references/troubleshooting.md` — all of which
documented `iperf -s` per port and `iperf -c -P N` fan-out.

### D3 ✅ `IPERF_*` -> `LOAD_*`

Renamed across `measure.sh`, `run_core.sh`, `nodes/client.sh`, `nodes/server.sh`,
all four orchestrators, the DPDK node scripts, both GitHub workflows, the skill
docs, `docs/capacity-model.md` and `CLAUDE.md`.

**Not renamed:** the GitHub Actions **workflow input names**
(`iperf_parallel`, `iperf_ports`, `iperf_timeout`). They are an external API
surface — `.claude/skills/deploy-infra/request.json` files and saved
workflow-dispatch habits reference them — so renaming would break callers for a
cosmetic gain. They map to the `LOAD_*` exports internally.

---

## Verification

| Check | Result |
|---|---|
| `pytest experiments/` | **66 passed** (incl. 9 new `test_endpoint_sh.py`, 12 `test_loadgen.py`) |
| `pytest src/clientnic` | **56 passed** |
| `pytest src/servernic/dpdk` | **21 passed** |
| `bash -n` on every tracked `.sh` | clean |
| Live loopback pacing check | 500 conns: paced **249 conn/s over 2.007 s**; unpaced **295k conn/s in 0.641 s**; 500/500 ok both |

`pytest experiments/ src/` in one invocation fails collection on a pre-existing
basename collision (`test_flow_table.py` and `test_pipeline.py` exist in both
`src/servernic/scapy/tests/` and `src/servernic/dpdk/tests/`). It predates this
work; run the directories separately.

**Not executed:** no live 4-VM AWS run. Everything above is verified by unit
tests, mock-transport tests and syntax checks. The netem placement change, the
baseline capture path and the capacity-run banner are asserted at the level of
"the right command is issued to the right node" — a real run is still needed to
confirm the expected ~`NETEM_RTT_MS` gap between the two stacks' `send_unlock`.

---

## E. The emulated WAN — what it is, and where the delay must sit

Added 2026-08-08, after the first valid baseline-vs-0-RTT run showed a proven
`send_unlock` win and **zero** FCT win. B1 is correct for `send_unlock` and is
the reason FCT cannot improve. Both facts follow from the same mechanism.

### E1. What "emulated WAN" means

All four VMs live in one AWS VPC — a real RTT of ~1.5 ms. 0-RTT saves exactly
one RTT, so at 1.5 ms the saving is unmeasurable noise. The experiment therefore
fakes a long-distance link by delaying packets in the kernel. That artificial
delay is the emulated WAN; `NETEM_RTT_MS=100` means "pretend these VMs are
100 ms apart."

**qdisc** (queueing discipline) is the kernel's outbound packet scheduler,
attached per interface. Every packet an application sends passes through it on
the way to the NIC. **netem** is a qdisc type that timestamps each packet, parks
it in a kernel timer queue, and releases it to the NIC `delay` later:

    loadgen/iperf -> socket -> TCP stack -> qdisc (netem: hold 100 ms) -> NIC -> wire

Nothing is looped back and the load generator has no idea the delay exists —
it is inserted one layer above the NIC by
`tc qdisc add dev eth0 root netem delay 100ms`. Three consequences that matter:

- **Egress only.** A root qdisc delays packets *leaving* that machine. Server-side
  placement delays the SYN-ACK but not the SYN. This is why placement is a
  correctness issue, not a detail.
- **Bounded queue.** Default depth is 1000 packets; overflow is a silent drop that
  looks like network loss. `endpoint_tune()` sets `limit 1000000` so netem
  emulates pure delay.
- **Delay only.** netem can also drop, reorder, duplicate and add jitter. This
  experiment uses none of them, so the emulated link is reliable and in-order.

### E2. No endpoint placement can show an FCT win

ServerNIC holds the client's first payload until the real SYN-ACK reveals the
server ISN (`src/servernic/dpdk/syn_handler.c`). FCT improves **only if
ServerNIC learns the real ISN before the client's data would otherwise have
arrived** — i.e. the `SYN → server → SYN-ACK → ServerNIC` loop must be shorter
than the `client → ServerNIC` path. Every endpoint-side placement fails that:

| netem placement | `send_unlock` gain | FCT gain | why |
|---|---|---|---|
| Server egress (current, B1) | full RTT | none | ISN learned exactly one RTT late |
| Client egress | none | none | SYN pays before ClientNIC can spoof |
| 50/50 both (pre-B1) | half | none | halves the spoof, flush still late |
| Server ingress (ifb) | full RTT | none | the flush re-pays the same ingress delay |

The condition is satisfiable only on the **ClientNIC↔ServerNIC leg**. There the
buffer wait overlaps WAN transit instead of adding to it:

    baseline:  SYN -50-> srv -50-> client (connect 100) -50-> srv -50-> client   FCT ~200
    0-RTT:     SYN -0-> spoof (unlock ~0.2); data in flight 50 ms,
               ISN known at t=50 (srv is local to ServerNIC), flush at 50.2,
               response -50-> client                                             FCT ~100

So the 2026-08-04 result — `send_unlock` −100.6 ms, FCT −0.09 ms — is a property
of the *measurement topology*, not proof that FCT is unimprovable. B1's note
("middle-leg placement is impossible, server-side is the achievable equivalent")
is true for `send_unlock` and false for FCT.

### E3. Proposed change — not yet implemented

- **Baseline stack** (`infra/baseline`, kernel-routed NIC VMs): `tc netem delay
  <RTT/2>` on each NIC VM's middle-leg interface. tc works there today.
- **DPDK stack**: the middle-leg ports are DPDK/vfio-pci owned, so tc cannot
  reach them — add a `--wan-delay-us` knob to both forwarders: a timestamped
  FIFO on `eth1` TX, drained in the existing poll loop.
- `NETEM_RTT_MS` on the endpoints goes to 0, and `endpoint_tune()`'s read-back
  assertion inverts: fail the run if an endpoint qdisc *is* present.
- Expected: `send_unlock` unchanged (~0.2 ms), FCT 200 ms -> ~100 ms.

Both stacks must model the same total RTT or the comparison is void — that is
the same trap C2 fixed for tooling.

---

## Suggested next step

Run the baseline and the DPDK experiment back to back with identical knobs and
compare the two `Send unlock` rows. That is now a single, well-defined
measurement — it was not possible before this work.
