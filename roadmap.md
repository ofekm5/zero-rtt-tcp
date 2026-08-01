# Roadmap

Open work only. Completed items are recorded in their reports, PRs, and
`openspec/changes/archive/` — see [Done ledger](#done-ledger) for pointers.

## Status snapshot

| Item | State |
| --- | --- |
| [#21 — DPDK vs. baseline comparison](#21--run-experiment-on-both-dpdk-and-baseline-stacks) | Open — not started |
| [Client-side pcap analysis at 100k](#client-side-pcap-analysis-doesnt-scale-to-100k) | Open — root cause not isolated |
| [Idea: close the 100k connection-burst gap](#idea-close-the-100k-connection-burst-gap) | Idea — not yet an OpenSpec change |
| [`verify-eswitch-tcp-seq-offload`](openspec/changes/verify-eswitch-tcp-seq-offload/proposal.md) | Proposed — spike not yet run |
| [`bluefield-servernic-hw-offload`](openspec/changes/bluefield-servernic-hw-offload/proposal.md) | Proposed — blocked on the spike |
| [BlueField lab deployment change](#gap-bluefield-lab-deployment-change-not-yet-proposed) | Gap — no proposal exists yet |

## #21 — Run experiment on both DPDK and baseline stacks

**Goal:** run the integration experiment on both the live DPDK 0-RTT stack
(`infra/dpdk`) and the plain-TCP baseline (`infra/baseline`), so TTFB/FCT numbers
are directly comparable.

### Scope
- `experiments/dpdk/run_experiment.sh` — live DPDK 0-RTT data plane
- `experiments/baseline-tcp/run_experiment.sh` — plain-TCP baseline (kernel-routed NIC VMs)
- Deploy each stack, run end-to-end, collect both reports.

### Success criteria
- [ ] `experiments/dpdk/run_experiment.sh` completes, report under `experiments/dpdk/reports/`
- [ ] `experiments/baseline-tcp/run_experiment.sh` completes, report under `experiments/baseline-tcp/reports/`
- [ ] Both reports cover the same connection load for a fair comparison
- [ ] TTFB/FCT delta documented (expected ~1-RTT / 50-200ms improvement per `CLAUDE.md`)

### Sequencing note
Run the comparison at whatever scale currently works (100 connections passes
clean); a 100k re-run only becomes meaningful once the burst-gap idea below is
scoped and landed.

## Client-side pcap analysis doesn't scale to 100k

Carried over from #20 as a known follow-up, not a blocker.

`analyze_metrics.py --client-pcap` failed against the 112 MB / 100k-connection
client-side capture — non-zero exit, no `missing=` diagnostic, only ~72 flows
processed instead of the ~68,779 successful connections. Server-side analysis
(`server_gap`) against a comparable pcap succeeded cleanly, so the fault is
likely the tcpdump-text-streaming approach itself, not the DPDK data plane.

- [ ] Isolate the root cause (snaplen / ring buffer / text-streaming parse)
- [ ] Decide between a larger snaplen+ring buffer and a binary-parsing rewrite
- [ ] Re-run client-side analysis on a 100k capture and get a full flow set

## Infra hand-tailoring — closed

Everything from this stream landed 2026-07-25 (see the Done ledger). The last
open item — security-group scoping — is **decided: leave the SG as-is**
(`10.1.0.0/16`).

The item was never a security question; it was a Nitro-conntrack performance
one. AWS stops tracking connections only when a rule is wide open in both
directions, so the narrow scope keeps every connection in the conntrack table,
and at 100k that could in principle hit the per-instance allowance. It doesn't:
`conntrack_allowance_exceeded` (and the other four counters) read 0 on both
endpoints after the 100k run. Widening buys nothing measurable and weakens
isolation on a lab that only ever talks to its own VMs.

Re-open only if a future run reports `conntrack_allowance_exceeded > 0` in
`ethtool -S eth0`.

## Idea: close the 100k connection-burst gap

**Not yet an OpenSpec change — candidate for `spec-planning:openspec-propose-change`
once prioritized.**

#20's live 100k run established 68,779/100,000. The shortfall is diagnosed:
`experiments/utils/loadgen.py`'s `asyncio.gather()` fires all 100,000
`open_connection()` calls at once, producing an instantaneous SYN burst beyond
what the `RX_RING_SIZE=1024` / `RX_BURST_SIZE=32` ring absorbs (`1024/32 = 32`
loop-iterations of slack — `docs/capacity-model.md` §4, §12, §13) before the
single busy-poll lcore drains it. Measured `cycles_per_packet` (ClientNIC
≈10,669, ServerNIC ≈12,483 at `tsc_hz=3.0e9`) shows ~40-50× steady-state
headroom, so this is burst absorption, not per-packet cost — a deeper
`RX_RING_SIZE` alone only delays the drop (capacity-model.md §4) and is bounded
by the ENA PMD's hardware descriptor limit anyway.

Three candidate approaches, none scoped in detail:

- **RSS/multi-queue** — spread the SYN burst across multiple lcores/RX queues so
  aggregate drain rate scales with burst size instead of being capped by one
  core's `RX_BURST_SIZE`-per-iteration rate.
- **SYN-cookie-style backpressure** — signal/shed load before the RX ring
  overflows rather than dropping silently via `imissed`, so establishment
  degrades gracefully instead of timing out via Linux's ~127-130s SYN-retry
  ceiling.
- **Client-side connection pacing** — stagger the `asyncio.gather()` burst
  (bounded concurrency / ramp-up) so attempts arrive as a sustained rate,
  trading test realism for a rate the existing single lcore can absorb.

### Success criteria (draft, to refine when proposed)
- [ ] 100k-connection run establishes ≥95% of connections (up from 68.8%)
- [ ] `imissed` at or near zero on both SmartNICs' data-plane ports at 100k
- [ ] Chosen approach documented against `docs/capacity-model.md` §4/§9/§12/§13
      with before/after measurements

## BlueField-3 track

### `verify-eswitch-tcp-seq-offload` — spike, not yet run

Determines whether the BlueField-3 e-switch can match a TCP flow, rewrite
seq/ack by a per-flow constant, and hairpin the packet back out `pf0hpf` —
entirely in hardware. DOCA Flow is the primary probe; an `rte_flow`/`testpmd`
cross-check fires **only on a NO**. Gates the offload change below: a confirmed
NO invalidates it rather than shrinking it.

Next actions: build and offline-transport the DOCA Flow probe container, stand
up `experiments/bluefield/` (does not exist yet), run the probe on
`bluefield-runs3-dpu` (`10.13.36.16`) with traffic from `10.13.37.10`, record the
YES/NO/PARTIAL verdict, restore `pf0hpf` to `ovsbr1`. Full criteria in the
[proposal](openspec/changes/verify-eswitch-tcp-seq-offload/proposal.md).

### `bluefield-servernic-hw-offload` — blocked on the spike

DPU-side ServerNIC that offloads post-handshake seq/ack rewriting to the
e-switch, keeping the ARM cores out of the data path (handshake only). New
`src/servernic/bluefield/` target reusing `flow_table.c`, `syn_handler.c`,
`checksum.c`; offload API stays behind a backend boundary until the spike
resolves it. Criteria in the
[proposal](openspec/changes/bluefield-servernic-hw-offload/proposal.md).

### Gap: BlueField lab deployment change (not yet proposed)

Both BlueField proposals explicitly push this out of scope and assume it exists
as a separate change — but no proposal has been written. It covers:

- [ ] `run_core.sh`'s AWS assumptions (`ec2-user`, `/usr/local/bin/meson`,
      `aws ec2 describe-instances`) made lab-portable
- [ ] Endpoint VM provisioning in the RUNS lab (client, server, ClientNIC)
- [ ] Lab DNS (or a documented decision to keep working around it offline)

`bluefield-servernic-hw-offload`'s Success Criterion 4 (end-to-end TCP through
the DPU) is not observable until this lands.

## Done ledger

Evidence lives in the linked artifacts, not here.

- **#18 — full-DPDK endpoint interfaces** — closed 2026-07-25. Change archived at
  `openspec/changes/archive/2026-07-14-full-dpdk-endpoint-interfaces/`; both
  SmartNICs run dual-DPDK data-plane ports (3 ENIs each), zero AF_PACKET in
  non-test source, 100-connection regression clean
  (`experiments/dpdk/reports/integration-test-report-2026-07-25.md`).
- **#20 — 100k-connection scale run** — closed 2026-07-21, executed 2026-07-25.
  68,779/100,000 established in 142.8s; shortfall attributed to a measured
  single-lcore burst-absorption ceiling, not endpoint OOM or a data-plane bug.
  Endpoints upsized to `m5.xlarge`, `loadgen.py` (asyncio) replaced iperf's
  thread-per-connection model, MTU/frame-ceiling, buffered-byte cap, TX batching,
  and `cycles_per_packet` instrumentation all landed (PR #27 + 7ce0529, 58f11c3).
  Report: `experiments/dpdk/reports/integration-test-report-2026-07-25.md`.
- **Infra hand-tailoring** — landed 2026-07-25 alongside #20: instance upsize,
  MTU pin, kernel limits (`nf_conntrack_max`, `tcp_max_tw_buckets`,
  `netdev_max_backlog`, `fs.file-max`), port-space assertion, `NUM_MBUFS`
  derivation, `FT_MAX_BUFFERED_BYTES` shedding ceiling, TX batching. All eight
  `docs/capacity-model.md` §11 constraints individually checked. The
  security-group scoping question is [closed](#infra-hand-tailoring--closed) —
  no change needed.
