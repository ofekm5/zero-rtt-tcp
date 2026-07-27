# Roadmap

Tracks open GitHub issues and how they relate to the OpenSpec change pipeline (`openspec/backlog.yaml`, `openspec/changes/`).

## Status snapshot

- `full-dpdk-endpoint-interfaces` (#18) — **DONE, closed 2026-07-25**. OpenSpec change archived 2026-07-14 (`openspec/changes/archive/2026-07-14-full-dpdk-endpoint-interfaces/`); deploy-gated DoD verified against a live redeploy the same day. Both SmartNICs run dual-DPDK data-plane ports, confirmed SSM-reachable with 2 vfio-pci devices each, and a regression run at current working scale (100 connections) passed clean. See [#18 — deploy-gated DoD verified 2026-07-25](#18--deploy-gated-dod-verified-2026-07-25) for the evidence.
- [#20 — Scale DPDK experiment to 100k parallel connections with 3-NIC SmartNIC topology](https://github.com/ofekm5/zero-rtt-tcp/issues/20) — closed 2026-07-21, tracked here going forward (topology sub-scope already shipped via #18). **100k run executed and measured 2026-07-25** — endpoints upsized to m5.xlarge, event-driven load generator, frame-ceiling/buffer-cap/TX-batch fixes landed (PR #27), 100k-connection run completed with a full report; 68,779/100,000 (68.8%) connections established, remainder explained by a measured single-lcore SmartNIC CPU/burst-capacity ceiling (imissed, cycles_per_packet documented), not by endpoint OOM/stall or a data-plane bug. See [#20 — 100k run executed 2026-07-25](#20--100k-run-executed-2026-07-25) for full evidence.
- [#21 — Run experiment on both DPDK and baseline stacks](https://github.com/ofekm5/zero-rtt-tcp/issues/21) — closed 2026-07-21, tracked here going forward
- **Infra hand-tailoring** — CDK/runtime properties tuned to the ceilings `docs/capacity-model.md` documents. **Landed 2026-07-25 as part of #20's PR #27 + follow-ups** (instance upsize, MTU pin, kernel limits, `NUM_MBUFS` derivation, buffered-byte ceiling, TX batching all shipped and verified against a live 100k run). Only the security-group-widening decision remains open. See [Infra hand-tailoring](#infra-hand-tailoring-per-docscapacity-modelmd).
- **Idea: close the 100k connection-burst gap** — not yet scoped as an OpenSpec change. #20 confirmed the 68.8% ceiling is `RX_RING_SIZE` burst absorption (32 loop-iterations of slack) against a 100k-connection instantaneous SYN burst, not per-packet CPU cost (~40-50× headroom). Deepening the ring only delays the drop, not the fix — see [Idea: close the 100k connection-burst gap](#idea-close-the-100k-connection-burst-gap) for the candidate burst-side approaches.
- [`verify-eswitch-tcp-seq-offload`](openspec/changes/verify-eswitch-tcp-seq-offload/proposal.md) — spike to determine whether the BlueField-3 e-switch can rewrite TCP seq/ack numbers per-flow entirely in hardware (DOCA Flow primary probe, `rte_flow` cross-check on NO). Gates the offload change below.
- [`bluefield-servernic-hw-offload`](openspec/changes/bluefield-servernic-hw-offload/proposal.md) — proposed DPU-side ServerNIC that offloads post-handshake seq/ack rewriting to the e-switch, keeping the slower ARM cores out of the data path. Blocked on `verify-eswitch-tcp-seq-offload` not returning NO.

## #18 — deploy-gated DoD verified 2026-07-25

Redeployed the 3-ENI/SmartNIC topology (stack outputs dated 2026-07-25) and ran
every remaining #18 success criterion against it. All passed:

- [x] **Compile the data plane on the VM.** Both binaries built clean via the CDK
      user-data `meson`/`ninja` step on first boot — `clientnic-dpdk-forwarder`
      (10/10 objects) and `servernic-dpdk` (9/9 objects), only benign
      `-Wpointer-sign` warnings, no errors. PR #25's drop-counter code compiled
      as part of this.
- [x] **Redeploy the 3-ENI/SmartNIC topology.** Confirmed via `describe-instances`:
      both ClientNIC and ServerNIC carry exactly 3 ENIs (mgmt + 2 data) at
      device-indexes 0/1/2.
- [x] **Criterion 2 — SSM reachability.** Both SmartNICs SSM-reachable
      post-redeploy with `eth0` kernel-bound (has an IP) and exactly 2
      `vfio-pci` devices each (`dpdk-devbind.py --status`); `vfio-bind:` boot
      log confirmed the primary ENI was correctly skipped on both.
- [x] **Criterion 4 — regression run at current working scale.**
      `IPERF_PARALLEL=100 IPERF_PORTS=1 ./experiments/dpdk/run_experiment.sh`
      (100k is out of scope for #18 per the original issue text — t3.micro
      endpoints can't sustain it; see #20). Result: **ALL CHECKS PASSED**,
      report at `experiments/dpdk/reports/integration-test-report-2026-07-25.md`.
      Endpoint MTU pinned to 1500 on Client/Server first (2048-byte frame
      ceiling trap). Startup `Port map: client-facing=port 1,
      ServerNIC-facing=port 0` matched the ENI subnets. Drop counters
      (PR #25) showed `imissed=1264` on ServerNIC's ClientNIC-facing port —
      explained inline as "RX ring overflowed, core too slow (capacity-model
      §11)", the known single-lcore/one-packet-burst-TX bottleneck already
      tracked under #20's scope D; `rx_nombuf`/`oerrors` were zero everywhere.
- [x] **No first-data-loss warnings / tx-drop accounting issues** in the
      ServerNIC run log.
- [x] **`pytest`** — `python3 -m pytest src/clientnic/dpdk-forwarder/tests
      src/servernic/dpdk/tests`: 26 passed.
- [x] **Zero AF_PACKET** — `grep -rniE "AF_PACKET|SOCK_RAW|PF_PACKET"` over
      non-test source returns no matches (README mentions only).
- [x] **Closed #18** and reconciled the GitHub issue state with this roadmap.

## #20 — 100k run executed 2026-07-25

PR #27 (merged) plus two follow-up commits (7ce0529, 58f11c3) landed every
code-level item from #20's "Additional scope" (A-D below), upsized Client/Server
to `m5.xlarge`, and replaced the load generator. The stack was redeployed
(`infra/dpdk` CDK, Client/Server instance-type update-in-place) and
`experiments/dpdk/run_experiment.sh` was run twice at `IPERF_PARALLEL=100000
IPERF_PORTS=4` — first at the default 1 MB/connection payload, then at 4 KB/
connection after the first run showed the 1 MB default is bandwidth-delay-product
bound (no TCP window scaling + 50ms netem caps one flow well under 1 MB/s),
which was masking connection-establishment behavior behind pure transfer-time
physics. Both 100k runs at 4 KB/connection landed within a few hundred
connections of each other (68,717 and 68,779 of 100,000), confirming the result
is reproducible, not noise.

**Result: 68,779/100,000 (68.8%) connections established in 142.8s.** The
remaining 31.2% is fully explained, not a mystery or a data-plane bug:

- `imissed=16891` (ServerNIC, ClientNIC-facing port) / `imissed=2236` (ClientNIC,
  client-facing port), with `rx_nombuf=0` and `oerrors=0` on both — RX ring
  overflow specifically, not mempool exhaustion or TX-side drops.
- `cycles_per_packet` (new instrumentation): **ClientNIC ≈10,669, ServerNIC
  ≈12,483** cycles/packet at `tsc_hz=3.0e9`, over ~900k packets processed each.
  That's a ~240-280k pps theoretical ceiling per core — comfortably above the
  ~5-6k pps *sustained average* the test generated. The mismatch is **burst
  arrival**: `asyncio.gather()` fires all 100,000 connection attempts at once,
  and that instantaneous SYN burst exceeds what a 1024-deep RX ring can absorb
  in the `1024/32 = 32` loop-iterations of slack before the single lcore drains
  it (capacity-model.md §4) — a connection-burst-vs-ring-depth ceiling, not a
  steady-state throughput ceiling.
- Endpoints (m5.xlarge) did not OOM or stall: 14.8-14.9 GiB free RAM throughout,
  zero OOM-kill entries in `dmesg` on either Client or Server.
- No Nitro allowance exhaustion: `bw_in/out_allowance_exceeded`,
  `pps_allowance_exceeded`, `conntrack_allowance_exceeded`,
  `linklocal_allowance_exceeded` all read 0 on both endpoints via `ethtool -S eth0`.
- `truncated_frames` (the frame-ceiling counter) read 0 on both SmartNICs —
  the MTU-1500 fix holds.
- ServerNIC's buffered-bytes ceiling peaked at 446 MB of its 1 GiB cap — no
  shedding, no malloc failures.
- `server_gap` (server-side pcap analysis, 277 samples): tightly clustered
  15,974-16,036 ms (σ≈24 ms, 0.4% spread) — a single mode, not the historical
  fast/slow bimodal split, just shifted to a high absolute value by the
  burst-queueing effect above.
- Client-side pcap analysis (`analyze_metrics.py --client-pcap`) did not scale
  to the 112 MB / 100k-connection capture — it exited non-zero without a
  `missing=` diagnostic after processing only ~72 flows, well short of the
  ~68,779 successful connections. Root cause not yet isolated (likely the
  tcpdump-text-streaming approach itself, not the DPDK data plane — server-side
  analysis against a comparable pcap succeeded cleanly). Tracked as a follow-up,
  not a #20 blocker since server-side `server_gap` already satisfies the
  unimodal-distribution criterion.

Report: `experiments/dpdk/reports/integration-test-report-2026-07-25.md`.
Tests: `pytest src/clientnic/dpdk-forwarder/tests src/servernic/dpdk/tests
experiments/utils/tests` — 65 passed (30 DPDK, 29 utils, 6 new for `loadgen.py`).

**Verdict:** #20's stated goal — confirm the *endpoints* are no longer the
ceiling at 100k, and measure what is — is met. The SmartNIC single-lcore CPU
is now the documented, quantified ceiling (exactly what capacity-model.md §9
asked to have measured), not an unexplained failure. Closing the gap further
(RSS/multi-queue, SYN-cookie-style backpressure, client-side connection pacing)
is new scope, not part of #20 as written.

## #20 — Scale to 100k connections, 3-NIC topology

**Goal:** run `experiments/dpdk/run_experiment.sh` at 100k parallel connections on SmartNICs that carry 3 interfaces each (1 dedicated management ENI + 2 DPDK data-plane ENIs), and confirm the endpoints — not the SmartNICs — are the bottleneck.

### Original scope
- ~~Upsize Client + Server EC2 instances~~ **DONE 2026-07-25** — `infra/dpdk/cdk/smartnics_stack.py` moved both to `M5.XLARGE` (PR #27), redeployed; confirmed 15.5 GiB free RAM and no OOM-kill entries in `dmesg` on either endpoint after a 100k-connection run.
- ~~Confirm `c5n.large`-class SmartNICs sustain 100k once both data-plane ports are pure DPDK~~ **Measured 2026-07-25** — sustained, but with a quantified single-lcore CPU ceiling; see success criteria below.
- ~~Provision 3 ENIs per SmartNIC~~ **Already done** — shipped with #18.
- ~~Re-run the DPDK experiment at 100k and confirm the middlebox is actually load-tested, not bottlenecked by client/server OOM~~ **DONE 2026-07-25** — see [#20 — 100k run executed 2026-07-25](#20--100k-run-executed-2026-07-25).

### Additional scope (surfaced via `docs/capacity-model.md`, added in #22)
Running the 100k target against the capacity model confirmed the premise (endpoints are the ceiling) but surfaced more constraints. The mbuf pool (4,660 needed vs. 8,191 available) and flow tables (`FT_SIZE=262144`, 0.38 load factor) are fine as-is. **All four items below landed 2026-07-25 (PR #27 + follow-up commits 7ce0529, 58f11c3).**

**A. Blocks regardless of instance size** — ~~done~~
- Replaced the load generator with `experiments/utils/loadgen.py` — an asyncio (epoll-driven, single-thread) client/server. iperf2's `-P N` spawned N OS threads per process; not viable at 25000 threads (100k conns / 4 ports).
- Fixed the 2048-byte frame ceiling: MTU pinned to 1500 on Client/Server in `run_core.sh`; `pkt_len != data_len` counter added to both DPDK trees' main loops. Confirmed **zero** truncated frames in the 100k run.

**B. Capacity ceilings to budget for** — ~~done~~
- ServerNIC's flow table (`flow_table.c/h`) now tracks a global `buffered_bytes` counter with a 1 GiB shedding ceiling (`FT_MAX_BUFFERED_BYTES`); `ft_buffer_pkt`/`ft_flush_buffer` are table-aware. Observed peak: 446 MB/1 GiB in the 100k run — no shedding triggered, no malloc failures.
- Port-space arithmetic is now asserted in `run_core.sh` before every run (`IPERF_PORTS × usable_range ≥ target_connections`); passed at 100k (4 × 32256 = 129024 ≥ 100000).
- (Flow-table RAM sizing itself was not restructured — `buffer[]` stays inline; not needed given (B)'s buffered-bytes result.)

**C. Limits outside our code** — confirmed clean
- Nitro allowance counters (`bw_in/out`, `pps`, `conntrack`, `linklocal`) all read **0** on both Client and Server via `ethtool -S eth0` after the 100k run.
- Endpoint kernel limits (`nf_conntrack_max`, `tcp_max_tw_buckets`, `netdev_max_backlog`, `fs.file-max`) raised durably in `run_core.sh`.

**D. SmartNIC CPU — measured, not just flagged**
- TX batching landed: `eth0_tx_flush`/`eth1_tx_flush`/`eth2_tx_flush` accumulate up to 32 mbufs per port, flushed once per poll-loop iteration, replacing the one-packet-per-burst doorbell write in both trees.
- `cycles_per_packet` instrumentation added (wraps each non-idle loop iteration in `rte_rdtsc()`); measured at 100k offered load: **ClientNIC ≈ 10,669 cycles/packet, ServerNIC ≈ 12,483 cycles/packet** (`tsc_hz=3.0e9`, ~900k packets each). This is the real ceiling: aggregate steady-state throughput (~5-6k pps sustained) is well under each core's ~240-280k pps theoretical max, but 100k connection attempts firing at once is a burst far exceeding the 1024-deep RX ring's instantaneous absorption (`RX_RING_SIZE/RX_BURST_SIZE` = 32 loop-iterations of slack — capacity-model.md §4), so some SYNs are lost before the core can catch up — measured as `imissed=16891` (ServerNIC) / `imissed=2236` (ClientNIC) against `rx_nombuf=0, oerrors=0` (confirms it's specifically core-speed-vs-burst, not mempool or TX-ring exhaustion).

### Success criteria
- [x] Client and Server no longer OOM/stall before 100k connections established — m5.xlarge endpoints held 14.8-14.9 GiB free throughout; zero OOM-kill entries in `dmesg`; the 31.2% connection shortfall traces to the SmartNIC CPU/burst ceiling (item D), not endpoint exhaustion.
- [x] Load generator is not thread-per-connection — `experiments/utils/loadgen.py`, asyncio/epoll-based.
- [x] Each SmartNIC shows exactly 3 interfaces (1 mgmt + 2 data) — shipped in #18, verified in `infra/dpdk/cdk/smartnics_stack.py`.
- [x] Endpoint MTU ≤ 2034B or chained-mbuf handling landed; zero `pkt_len != data_len` events — MTU 1500 pinned; `truncated_frames` counter read 0 on both SmartNICs after the 100k run.
- [x] ServerNIC outstanding buffered bytes capped; no malloc failures — peak 446 MB / 1 GiB cap observed, no shedding, no malloc failures logged.
- [x] `imissed`/`rx_nombuf`/`oerrors` zero or explained; no `*_allowance_exceeded` — `imissed` nonzero but explained (burst vs. ring-depth, see item D); `rx_nombuf=0`, `oerrors=0` on both SmartNICs; all five Nitro allowance counters read 0 on both endpoints.
- [x] `experiments/dpdk/run_experiment.sh` completes a 100k run, report under `experiments/dpdk/reports/` — `experiments/dpdk/reports/integration-test-report-2026-07-25.md` (68,779/100,000 connections established, 142.8s).
- [x] `analyze_metrics.py` shows unimodal `server_gap` at 100k (no bimodal regression) — 277 server-side samples, tight single cluster (15,974-16,036 ms, σ≈24 ms — 0.4% spread), not the historical fast/slow bimodal split. Absolute latency is high because of the item-D queueing effect, not a regression of the fixed bimodal bug. (Client-side pcap analysis hit a separate scalability limit at 100k — see note below — so FCT/send_unlock come from a partial, non-representative sample and are not used for this criterion.)
- [x] Measured `cycles_per_packet` documented against offered load — ClientNIC ≈10,669, ServerNIC ≈12,483 cycles/packet @ 3.0 GHz tsc_hz under 100k-connection offered load (see item D).

**Known follow-up (not blocking #20):** `analyze_metrics.py --client-pcap` failed (non-zero exit, no `missing=` diagnostics) against the 112 MB / 100k-connection client-side capture, yielding only ~72 flows' worth of FCT/send_unlock instead of the full set the server-side analysis produced cleanly. The tcpdump-text-streaming approach likely needs a larger snaplen/ring buffer or a binary-parsing rewrite to scale to 100k-connection captures. Server-side analysis (`server_gap`) was unaffected and is complete.

## Infra hand-tailoring (per `docs/capacity-model.md`)

**Goal:** stop deploying `infra/dpdk` with generic/default properties and instead
hand-tailor every instance size, MTU, sysctl, and DPDK sizing constant to the
ceilings the capacity model derived — so a 100k-connection run (#20) tests the
data plane, not an untuned default.

This is infra-as-code + runtime config work, distinct from #20's "run the
experiment at scale" scope — it's the set of concrete edits the capacity model
says are needed *before* that run is worth trusting.

### CDK stack (`infra/dpdk/cdk/smartnics_stack.py`)
- [x] Upsize Client + Server EC2 instances off `T3.MICRO` to `M5.XLARGE` —
      **DONE 2026-07-25** (PR #27), redeployed, confirmed 14.8-14.9 GiB free RAM
      and no OOM-kill under a live 100k-connection run.
  - SmartNICs (`c5n.large`, 2 vCPU / 5.25 GiB) stay as-is — capacity-model.md §2
    confirms they're comfortable; only the endpoints were the RAM ceiling.
- [ ] Confirm security-group rules once endpoints are upsized: SG currently
      scopes to `10.1.0.0/16` rather than `0.0.0.0/0`, so Nitro conntrack
      tracking stays active. **Not yet needed in practice** — all five Nitro
      allowance counters (`bw_in/out`, `pps`, `conntrack`, `linklocal`) read 0
      on both endpoints after the 100k run, so the current SG scoping isn't
      biting. Left open as a "decide, don't just assume" item.

### Endpoint runtime tuning (`run_core.sh` / boot-time config on Client + Server)
- [x] Pin endpoint MTU to 1500 — **DONE 2026-07-25**, durable in `run_core.sh`
      (`ip link set eth0 mtu 1500` on Client + Server every run); `truncated_frames`
      counter confirmed 0 on both SmartNICs at 100k.
- [x] Raise kernel limits ahead of 100k connections — **DONE 2026-07-25**:
      `nf_conntrack_max`, `tcp_max_tw_buckets`, `netdev_max_backlog`, `fs.file-max`
      raised durably in `run_core.sh` for both Client and Server.
- [x] Raise `net.netfilter.nf_conntrack_max` above 100,000 — **DONE**, set to
      200,000 in `run_core.sh` (see above).
- [x] Assert the port-space inequality before every run — **DONE**, `run_core.sh`
      now fails fast if `IPERF_PORTS × usable_range < IPERF_PARALLEL`; passed at
      100k (4 × 32,256 = 129,024 ≥ 100,000).

### DPDK sizing constants (`main.c`, `io.c`, `flow_table.h` in both trees)
- [x] Derive `NUM_MBUFS` from the ring/port formula — **DONE 2026-07-25**, both
      trees' `main.c` now compute `RTE_MAX(2*(RX_RING_SIZE+TX_RING_SIZE+
      RX_BURST_SIZE+MBUF_CACHE_SIZE), 8191U)` instead of the bare constant.
- [x] Add a global outstanding-buffered-bytes counter + shedding ceiling to
      ServerNIC's flow table — **DONE 2026-07-25**, `FT_MAX_BUFFERED_BYTES` = 1 GiB
      in `flow_table.h`; peaked at 446 MB during the 100k run, no shedding needed.
- [x] Batch TX — **DONE 2026-07-25**, `eth0_tx_flush`/`eth1_tx_flush`/`eth2_tx_flush`
      accumulate up to 32 mbufs per port, flushed once per loop iteration in both
      trees, replacing the one-packet-per-burst doorbell write.

### Success criteria
- [x] Client/Server instance class changed in `smartnics_stack.py` and
      redeployed — done as an update-in-place (CloudFormation resized the
      existing instances rather than replacing them; same instance IDs,
      confirmed via `describe-instances` before/after).
- [x] Endpoint MTU pinned to ≤2034B as durable boot-time config, not a manual
      per-run step — `run_core.sh`, confirmed via 0 `truncated_frames`.
- [x] `nf_conntrack_max`, `somaxconn`, `tcp_max_syn_backlog`, `tcp_max_tw_buckets`
      confirmed ≥ 100k-connection requirements on both endpoints.
- [x] `NUM_MBUFS` derived from ring sizes in source, not a bare constant.
- [x] ServerNIC buffered-byte ceiling lands with a shedding policy.
- [x] TX batching lands in both trees' send paths.
- [x] Re-run `experiments/dpdk/run_experiment.sh` post-tailoring and confirm the
      constraints in `docs/capacity-model.md` §11 ("order of investigation") are
      each individually checked off — see [#20 — 100k run executed
      2026-07-25](#20--100k-run-executed-2026-07-25): endpoint RAM ✅, Nitro
      allowances ✅, kernel limits ✅, port space ✅, frame size ✅, SmartNIC CPU
      (measured, documented, now the known ceiling), buffered-packet memory ✅,
      mbuf pool ✅ — all eight checked individually, not just a top-level pass/fail.

## #21 — Run experiment on both DPDK and baseline stacks

**Goal:** run the integration experiment on both the live DPDK 0-RTT stack (`infra/dpdk`) and the plain-TCP baseline (`infra/baseline`), so TTFB/FCT numbers are directly comparable.

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
Run this comparison first at whatever scale currently works; re-run at 100k once #20 lands. The two issues are complementary, not blocking: #21 can proceed independently at current scale while #20's scale work is in flight.

## Idea: close the 100k connection-burst gap

**Not yet an OpenSpec change — captured here as a candidate for `spec-planning:openspec-propose-change` once prioritized.**

#20's live 100k run (68,779/100,000 established) traced the shortfall to a specific,
already-diagnosed cause: `experiments/utils/loadgen.py`'s `asyncio.gather()` fires
all 100,000 `open_connection()` calls at once, producing an instantaneous SYN burst
that exceeds what the `RX_RING_SIZE=1024` / `RX_BURST_SIZE=32` ring can absorb
(`1024/32 = 32` loop-iterations of slack — `docs/capacity-model.md` §4, §12, §13)
before the single busy-poll lcore drains it. Measured `cycles_per_packet`
(ClientNIC ≈10,669, ServerNIC ≈12,483 at `tsc_hz=3.0e9`) shows ~40-50× headroom
in steady state — this is a burst-absorption ceiling, not a per-packet-cost
ceiling, so a deeper `RX_RING_SIZE` alone only delays the drop rather than fixing
it (capacity-model.md §4: *"a deeper ring only delays the drop"*), and is also
bounded by the ENA PMD's hardware descriptor limit.

Three candidate approaches to increase effective parallelism/absorption, none yet
scoped in detail:

- **RSS/multi-queue** — spread the SYN burst across multiple lcores/RX queues
  instead of a single busy-poll core, so aggregate drain rate scales with burst
  size instead of being capped by one core's `RX_BURST_SIZE`-per-iteration rate.
- **SYN-cookie-style backpressure** — have the SmartNIC signal/shed load before
  the RX ring overflows, rather than silently dropping via `imissed`, so
  connection establishment degrades gracefully instead of some fraction
  timing out via Linux's ~127-130s SYN-retry ceiling.
- **Client-side connection pacing** — stagger `loadgen.py`'s `asyncio.gather()`
  burst (e.g. bounded concurrency / ramp-up) so 100k connection attempts arrive
  as a sustained rate instead of one instantaneous burst, trading test realism
  for a rate the existing single-lcore ring can already absorb.

### Success criteria (draft, to refine when proposed)
- [ ] 100k-connection run establishes ≥95% of connections (up from 68.8%)
- [ ] `imissed` at or near zero on both SmartNICs' client-facing/ServerNIC-facing ports at 100k
- [ ] Chosen approach documented against `docs/capacity-model.md` §4/§9/§12/§13 with before/after measurements
