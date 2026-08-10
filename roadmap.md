# Roadmap

Open work only. Completed items are recorded in their reports, PRs, and
`openspec/changes/archive/` — see [Done ledger](#done-ledger) for pointers.

## Status snapshot

| Item | State |
| --- | --- |
| [Measurement flaws (F3–F16)](#measurement-flaws) | Open — F2 resolved 2026-08-08, nothing blocking |
| [#21 — DPDK vs. baseline comparison](#21--run-experiment-on-both-dpdk-and-baseline-stacks) | Open — not started |
| [Client-side pcap analysis at 100k](#client-side-pcap-analysis-doesnt-scale-to-100k) | Open — root cause not isolated |
| [Idea: close the 100k connection-burst gap](#idea-close-the-100k-connection-burst-gap) | Idea — not yet an OpenSpec change |
| [Demo A — BlueField reflector, no NIC VMs](#demo-a--bluefield-reflector-no-nic-vms) | Sketch — not scoped |
| [Demo B — all-VM 4-chain on Proxmox](#demo-b--all-vm-4-chain-on-proxmox) | Sketch — not scoped |
| [Demo C — BlueField as ClientNIC, ServerNIC stays a VM](#demo-c--bluefield-as-clientnic-servernic-stays-a-vm) | Sketch — not scoped |
| [Human-readable experiment output](#human-readable-experiment-output) | Idea — not scoped |
| [Multi-round send in the load generator](#multi-round-send-in-the-load-generator) | Idea — not scoped |
| [DDoS resistance](#ddos-resistance) | Idea — threat model not written |
| [AWS cross-region deployment](#aws-cross-region-deployment) | Idea — not scoped |
| [`verify-eswitch-tcp-seq-offload`](openspec/changes/verify-eswitch-tcp-seq-offload/proposal.md) | In progress — DPU left mutated, restore first |
| [`bluefield-servernic-hw-offload`](openspec/changes/bluefield-servernic-hw-offload/proposal.md) | Proposed — blocked on the spike |
| [BlueField lab deployment change](#gap-bluefield-lab-deployment-change-not-yet-proposed) | Gap — no proposal exists yet |

## Measurement flaws

Classified 2026-08-08 from the first valid baseline-vs-0-RTT run pair
(2026-08-04, 2000 conns). Background and derivations:
`experiments/measurement-methodology-review.md` (§E for the emulated WAN),
`experiments/insights.md` (2026-08-04 entries).

F1 (the FCT tail) was removed 2026-08-08: at PoC scale, 20 of 2000 flows that
complete late — with 2000/2000 succeeding and p99 better than baseline — does not
undermine the demonstration. It is now a single `nstat` check carried in a
handoff document, not a roadmap gate. See the closing note below.

| # | Flaw | Class | Severity |
| --- | --- | --- | --- |
| ~~F2~~ | ~~netem on Server egress makes any FCT gain structurally unmeasurable~~ | Methodology | **Resolved 2026-08-08** |
| F3 | NIC logs truncated at the 24 KB SSM cap — reported counts cover <100 of 2000 flows | Observability | High |
| F4 | ClientNIC/ServerNIC in-app rdtsc TTFB dark (`no samples found`) | Observability | High |
| F5 | No application-level client TTFB exists; the claim rests entirely on pcap timing | Observability | Medium |
| F6 | `loadgen.py` self-reports from a Python event loop — GIL/scheduler delay sits inside the measured interval | Instrument | Medium |
| F7 | Pacing is a ceiling, not a guarantee — a paced run degrades to a burst silently | Instrument | Medium |
| F8 | Throughput is not measured at all; the 2026-07-14 "~100× slower" finding is unresolved | Coverage | High |
| F9 | One 1 KB write never exercises congestion control, window growth or retransmit | Coverage | Medium |
| F10 | Only the 2000-connection smoke has run against the corrected methodology | Coverage | Medium |
| F11 | Timestamps/SACK/window-scaling disabled — no fast-recovery path, and results do not model real TCP | Design | Medium |
| F12 | Nothing before 2026-08-04 is comparable (tool change + `tc` was never installed) | Hygiene | Low |
| F13 | iperf-shaped naming survives the migration | Hygiene | Low |
| F14 | Baseline CDK user-data clone is broken; fixing it forces instance replacement | Infra | Low |
| F15 | `iproute-tc` is in neither stack's user-data — self-healed at runtime, so a fresh stack can regress | Infra | Low |
| F16 | Open items live in `experiments/insights.md` while this file is the declared source of truth | Docs | Low |

**F1 is not in the table** because it is an open *observation*, not a defect with
known severity — see [the FCT tail](#the-fct-tail--open-observation-one-check-settles-it)
below for the full item. It was carried in a standalone handoff document until
2026-08-08; that document went stale within a day of being written (it still
described F2 as blocking and the FCT claim as unproven) and was folded in here,
since this file is the declared source of truth.

### F2 — Emulated WAN moved to the middle leg ✅ RESOLVED 2026-08-08

`endpoint.sh` used to put the whole `NETEM_RTT_MS` on Server egress. That is
correct for `send_unlock` and was the reason FCT could not improve: the SYN-ACK
ServerNIC needs before it can flush was the one packet paying the entire
emulated WAN. No endpoint-side placement satisfies the condition (ServerNIC must
learn the real ISN *before* the client's data would otherwise arrive) — see
`measurement-methodology-review.md` §E2 for the four-placement proof.

- [x] Baseline stack: `tc netem delay <RTT/2>` on each kernel-routed NIC VM's
      middle-leg interface (`wan_tune_middle_leg()`, ClientNIC eth1 / ServerNIC eth0)
- [x] DPDK stack: `--wan-delay-us` on both forwarders — FIFO hold ring on the
      `eth1` TX path, drained in the existing poll loop (tc cannot reach
      vfio-pci ports). `src/*/wan_delay.c`, 7 unit tests.
- [x] Endpoints carry no qdisc; `endpoint_tune()`'s read-back assertion inverted
      to fail the run if one *is* present
- [x] Both stacks model the same total RTT — `wan_delay_us()` derives the DPDK
      value from the same `NETEM_RTT_MS` the baseline netem uses

**Measured, both stacks, 2026-08-08** (2000 conns, 500/s, 4 ports, 1 KB,
`NETEM_RTT_MS=100`, 2000/2000 OK on both):

| metric | baseline | 0-RTT | delta |
| --- | --- | --- | --- |
| `send_unlock` mean | 101.532 ms | 0.263 ms | **−101.27 ms** |
| `fct` mean | 202.919 ms | 101.067 ms | **−101.85 ms** |
| `fct` p99 | 203.933 ms | 101.407 ms | −102.53 ms |
| `fct` max | 215.570 ms | 102.928 ms | −112.64 ms |
| `server_gap` mean | 101.523 ms | 0.259 ms | −101.26 ms |

The headline is no longer narrower than the claim: **0-RTT now removes one full
RTT from flow completion time, not only from application blocking time.** The
−0.09 ms FCT result of 2026-08-04 was an artifact of netem placement, exactly as
§E predicted.

Reports: `experiments/baseline-tcp/reports/baseline-report-2026-08-08-212236.md`,
`experiments/dpdk/reports/integration-test-report-2026-08-08.md`.

Note for [the FCT tail](#the-fct-tail--open-observation-one-check-settles-it): the
537 ms outlier **did not reproduce** — 0-RTT `fct` max is 102.928 ms, only
1.5 ms above its own p99, and tighter than baseline's 215.570 ms. One run is not
proof it is gone; re-check at 100k before treating it as closed.

Still superseded by [AWS cross-region deployment](#aws-cross-region-deployment)
if that lands — a real WAN path removes the emulation question entirely.

### The FCT tail — open observation, one check settles it

Carried out of the flaw table on 2026-08-08: at PoC scale it does not justify a
gate, but it does justify ten minutes, for the reason under *Outcome B* below.

**What was seen.** In the 2026-08-04 run pair (2000 conns, 500/s, 4 ports, 1 KB,
server-egress netem — the pre-F2 topology):

| | baseline | 0-RTT |
| --- | --- | --- |
| `fct` p99 | 202.833 ms | 201.638 ms (better) |
| `fct` max | 213.254 ms | **536.628 ms** |

≤20 of 2000 flows, 335 ms above the 0-RTT stack's own p99. **2000/2000
connections succeeded** — nothing was dropped or refused; the affected flows
completed, just late.

**Already ruled out — do not re-derive:**

- *Not the handshake* — `send_unlock` max 2.061 ms vs baseline 112.429 ms.
- *Not the server's response* — `server_gap` max 0.756 ms vs baseline 12.358 ms.
- *Not the ServerNIC flush path* — the captured log has zero
  `flush dropped first c2s data` warnings, the counter that exists to catch
  exactly that. (An earlier guess of "somewhere in the buffer/flush path" was
  contradicted by the data.)

The excess sits between *"first payload leaves"* and *"flow completes"*.

**It did not reproduce.** In the 2026-08-08 pair (post-F2, middle-leg WAN) 0-RTT
`fct` max was 102.928 ms — 1.5 ms above its own p99, and far tighter than
baseline's 215.570 ms. That is one clean run at 2000 connections, not evidence of
absence: the topology changed at the same time, so it is equally consistent with
"fixed", "masked" and "did not happen to occur".

**Hypothesis, unproven.** One lost segment paying Linux's `TCP_RTO_MIN` (200 ms,
`HZ/5` — the hard floor on the retransmission timeout) plus a ~100 ms retransmit
round trip ≈ 300 ms, against 335 ms observed. Plausible specifically because
`endpoint_tune()` disables timestamps, SACK and window scaling (**F11**) — a 1 KB
flow is one segment, so there are no duplicate ACKs and no fast-retransmit path.
The RTO is the *only* recovery mechanism available. The arithmetic fits; nothing
proves it.

**The check** — retransmission counters on both endpoints around a run:

```sh
nstat -n                                              # before the load starts
nstat -z | grep -Ei 'retrans|timeout|TCPLoss'         # after it completes
```

Counters that matter: `TcpRetransSegs`, `TcpExtTCPTimeouts`,
`TcpExtTCPSlowStartRetrans`, `TcpExtTCPLostRetransmit`.

- [ ] Capture `nstat` on Client and Server around the next run of either stack.
      Both stacks are currently destroyed, so fold this into whatever run happens
      next rather than deploying for one counter — the 2026-08-08 runs were the
      obvious opportunity and it was missed.

**Outcome A — retransmissions non-zero (≈20, matching the slow-flow count).**
Ordinary packet loss recovered by the RTO; nothing wrong with the data plane.
Record it in `experiments/insights.md` and close the item — no code change. For a
PoC that is a complete answer.

**Outcome B — retransmissions zero or near-zero.** The hypothesis is dead and the
335 ms is not loss recovery, which points at the data plane holding or reordering
a segment — a real correctness finding for a project whose entire claim is that
seq/ack translation is correct. Then: re-enter the flaw table as blocking, use
`analyze_metrics.py --detail-out` to name the slow flows and pull only those
4-tuples from the pcaps, and **fix F3 first** — the 24 KB SSM log cap already
stalled this diagnosis once, and chasing a data-plane bug through a truncated log
will stall in the same place.

### F3–F8 — next tier

- [ ] **F3** Fix NIC-log retrieval past the 24 KB SSM cap (S3 staging, or count
      on the node and return only the numbers). It actively obstructed the
      FCT-tail diagnosis.
- [ ] **F4** Restore in-app NIC TTFB — suspected the deployed binary predates the
      rdtsc instrumentation. It is the only signal that separates data-plane cost
      from network cost.
- [ ] **F5** Decide whether an application-level TTFB is needed as an independent
      check on the pcap path, or whether pcap-only is accepted.
- [ ] **F6** Compare `loadgen.py`'s self-reported connect time against pcap
      `send_unlock` to bound the Python overhead. Currently ~0.42 ms p99 against
      a 100 ms signal, so not urgent — revisit at 100k.
- [ ] **F7** Fail (or loudly warn) the run when achieved arrival rate diverges
      from requested, instead of printing one `Arrival:` line.
- [ ] **F8** Run one deliberate throughput comparison — same tool, stream count
      and transfer size on both stacks. iperf2 is the right tool here (sustained
      bytes on few flows); `loadgen.py` stays the tool for many short
      connections. See also [multi-round send](#multi-round-send-in-the-load-generator).

### F9–F16 — tracked, not scheduled

- **F9** is the existing [multi-round send](#multi-round-send-in-the-load-generator)
  item; it is also the coverage gap most likely to explain the FCT tail.
- **F10** is [#21](#21--run-experiment-on-both-dpdk-and-baseline-stacks) at full
  scale, gated on F2 only.
- **F11** is a design constraint, not a bug: the translator does not rewrite TCP
  options, so the endpoints must not negotiate them. Revisit only if option
  rewriting is ever specced.
- **F12** Treat 2026-08-04 as sample #1. No action beyond not comparing across it.
- **F13** Retire `analyze_metrics.py --iperf-csv` (dead code carrying 6 live
  tests). The GitHub Actions `iperf_parallel`/`iperf_ports`/`iperf_timeout`
  inputs stay as a deliberate external API surface.
- **F14** Left alone on purpose — the fix forces instance replacement.
- **F15** Add `iproute-tc` to both stacks' user-data so the runtime self-heal is
  a fallback rather than the mechanism.
- **F16** Mirror or move `insights.md`'s open follow-ups here.

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
- **Dynamic ISN pool** — ClientNIC currently draws each spoofed ISN from
  `rte_rand()` per SYN (`packet_processor.c`); a pre-generated pool of unique
  values would remove both the per-packet RNG cost and any (currently
  theoretical) collision risk in the flow table's V-keyed lookup at burst
  scale.

### Success criteria (draft, to refine when proposed)
- [ ] 100k-connection run establishes ≥95% of connections (up from 68.8%)
- [ ] `imissed` at or near zero on both SmartNICs' data-plane ports at 100k
- [ ] Chosen approach documented against `docs/capacity-model.md` §4/§9/§12/§13
      with before/after measurements

## Demo topologies (lab / Proxmox)

Three candidate demo layouts, sketched in `image.png` (repo root, currently
untracked — move it under `docs/` and commit it before this section outlives the
file). None is scoped as an OpenSpec change yet; they are alternatives for how
the lab demo is wired, not a sequence to build in order.

The sketch also carries three role labels — *client/server split*, *dev.
environment*, *benchmarking environment* — and marks the two SmartNIC roles as
*0-RTT SmartNIC client* and *0-RTT SmartNIC server*. The obvious reading is that
B is the dev environment (no hardware in the loop) and A or C is the
benchmarking one, but the sketch does not say which, so the mapping below is
recorded as a question rather than a decision.

### Demo A — BlueField reflector, no NIC VMs

Client VM and Server VM both live on the Proxmox host, joined by a virtual
switch (OVS is the sketch's own open question). Neither talks to the other
directly: client traffic leaves the host, hits the BlueField running a
**reflector app**, and comes back in to the Server VM. The DPU is a
bump-in-the-wire on a hairpin, so both 0-RTT roles collapse onto one card and
no ClientNIC/ServerNIC VMs exist at all.

- Fewest moving parts of the three; closest to the hardware-only end state.
- Puts both SmartNIC roles on one DPU — needs the e-switch verdict from
  `verify-eswitch-tcp-seq-offload` before it is known to be buildable.
- Open: what "reflector app" means concretely — hairpin rules only, or an ARM
  control plane like `bluefield-servernic-hw-offload` describes.
- Open: whether the virtual switch is OVS, a Linux bridge, or SR-IOV passthrough,
  and whether that choice perturbs the latency being measured.

### Demo B — all-VM 4-chain on Proxmox

The full AWS chain reproduced in software on one Proxmox host: Client VM ↔
ClientNIC VM ↔ ServerNIC VM ↔ Server VM, all four as VMs, no BlueField in the
path. This is the current `src/clientnic/dpdk-forwarder` + `src/servernic/dpdk`
data plane ported off AWS ENIs onto Proxmox virtual NICs.

- No hardware dependency — the likely **dev environment**, and the fastest of
  the three to stand up.
- Directly reuses today's data plane; the work is deployment plumbing, which is
  the same gap the [BlueField lab deployment
  change](#gap-bluefield-lab-deployment-change-not-yet-proposed) already covers
  (`run_core.sh`'s AWS assumptions, endpoint VM provisioning).
- Open: whether the virtual-NIC path supports DPDK as-is (`virtio`/vhost-user vs.
  SR-IOV VFs) or the forwarders need an AF_XDP/AF_PACKET fallback on Proxmox.
- Open: usefulness as a *benchmark* — everything shares one host's cores, so
  absolute TTFB/FCT numbers are not comparable to the AWS or hardware runs.

### Demo C — BlueField as ClientNIC, ServerNIC stays a VM

Split deployment: Client VM and Server VM on Proxmox with the **ServerNIC as a
VM** next to the Server, while the **ClientNIC role runs on the BlueField**
outside the host. Client traffic goes out to the DPU and back into the host
toward the ServerNIC VM.

- Matches the asymmetry of the existing proposals in reverse:
  `bluefield-servernic-hw-offload` puts *ServerNIC* on the DPU and keeps
  ClientNIC on x86; this sketch does the opposite.
- Worth resolving explicitly — ClientNIC's job (spoof the SYN-ACK, stamp V in
  the SYN ack-num) is per-handshake and may suit the ARM cores better than
  ServerNIC's per-packet rewriting, which is exactly what the e-switch offload
  exists to avoid.
- Open: does this replace `bluefield-servernic-hw-offload`, or is it a second
  step once a second BlueField is available (the runs4 DPU needs another
  student's permission)?

### Next actions
- [ ] Commit the sketch under `docs/` so this section has a stable reference
- [ ] Pick which demo is the dev environment and which is the benchmarking one
- [ ] Decide whether C's ClientNIC-on-DPU direction supersedes or follows
      `bluefield-servernic-hw-offload`
- [ ] Promote the chosen topology to an OpenSpec change via
      `spec-planning:openspec-propose-change`

## BlueField-3 track

- [ ] Simplify the e-switch experimentation harness and stop overloading the
      DPU while iterating on it — the spike needed nine defect fixes and left
      the DPU mutated (VPN drop mid-run) and blocked (no sudo password) just
      to get this far; that's a sign the harness itself is too heavy for
      iterative probing, not only the probe logic.
- [ ] Prioritize a lightweight ARM-only path (no e-switch hardware offload —
      see [Demo C](#demo-c--bluefield-as-clientnic-servernic-stays-a-vm)) as
      the first BlueField experiment, ahead of or independent from the
      e-switch spike below.

### `verify-eswitch-tcp-seq-offload` — in progress, DPU left mutated

Determines whether the BlueField-3 e-switch can match a TCP flow, rewrite
seq/ack by a per-flow constant, and hairpin the packet back out `pf0hpf` —
entirely in hardware. DOCA Flow is the primary probe; an `rte_flow`/`testpmd`
cross-check fires **only on a NO**. Gates the offload change below: a confirmed
NO invalidates it rather than shrinking it.

**Do this first — DPU is left mutated.** The VPN dropped mid-session on the PR
#28 test-plan run, so `restore.sh` never ran. On `bluefield-runs3-dpu`
(`10.13.36.16`): `pf0hpf` is detached from `ovsbr1`, hugepages are at 1024
(baseline 0). Reconnect the RUNS OpenVPN profile, then from
`C:\Users\shir\Documents\GitHub\.task-runner-worktrees\verify-eswitch-tcp-seq-offload\experiments\bluefield\probe`:
`./restore.sh --baseline-file ../reports/baseline.txt`.

**Key finding, already measured on hardware:** in the e-switch pipe,
`outer.tcp.seq_num` and `outer.tcp.ack_num` are both **ACCEPTED** for a
`DOCA_FLOW_ACTION_ADD`, alongside three known-good controls accepted and three
bogus field names rejected — the accept is discriminating, not a blanket yes.
A full rule (5-tuple match + ADD + hairpin to `pf0hpf` + counter) installs and
returns a valid handle. Accepted level = YES; Offloaded/Effective are
unproven — no traffic has crossed the rule yet.

**Test-plan status:** 2 of 5 items pass — SSH to both hosts, and the probe
compiling against the installed DOCA 3.0.0058/DPDK 22.11 (only after a full
rewrite off the DOCA 2.x API the PR was written against). Not yet done: a full
`run_probe.sh` run, restore-matches-baseline verification, and the recorded
verdict.

**Nine real defects found and fixed** getting this far: wrong DOCA API version
targeted, wrong toolchain in the container build (replaced with
`build_probe.sh`, native gcc on the DPU — no docker daemon running there
anyway), wrong mlx5 representor selector (`pf0vf65535`, not `pf0hpf`), a
missing switch-mode device probe that segfaulted `doca_flow_port_start()`,
missing `sudo` on every `ovs-vsctl` call, two broken baseline probes
(`PKG_CONFIG_PATH`, root-only `mlxfwmanager`), `hping3` not installed
(replaced with a stdlib `vmtraffic.py`), and a hugepage check that made SC5
unreachable. All uncommitted on `task-runner/verify-eswitch-tcp-seq-offload` in
the worktree above.

**Blocker:** `bluefieldadmin@10.13.37.10` has no passwordless sudo and its only
local Docker image is arm64 on an x86 host, so the traffic step (tcpdump + raw
TX) can't run without the sudo password. Resume with
`claude --resume 23e8de92-4afd-402e-9e79-d91e516c81e3`, export
`PROBE_VM_SUDO_PASS='...'` (fed to `sudo -S` on stdin by
`lib/hosts.sh:vm_sudo_run` — never written to disk or a remote command line) to
continue. Full detail, including two known-remaining rough edges
(`flow_rule.sh`'s duplicate `--port-id`, `run_probe.sh`'s default `PORT_ID`)
in `experiments/bluefield/probe/HANDOFF.md` in the worktree (uncommitted).

Full criteria in the
[proposal](openspec/changes/verify-eswitch-tcp-seq-offload/proposal.md).

### `bluefield-servernic-hw-offload` — blocked on the spike

DPU-side ServerNIC that offloads post-handshake seq/ack rewriting to the
e-switch, keeping the ARM cores out of the data path (handshake only). New
`src/servernic/bluefield/` target reusing `flow_table.c`, `syn_handler.c`,
`checksum.c`; offload API stays behind a backend boundary until the spike
resolves it. Criteria in the
[proposal](openspec/changes/bluefield-servernic-hw-offload/proposal.md).

- [ ] Cache installed e-switch flow rules in memory instead of re-querying/
      reinstalling per flow, once the spike picks a backend (`offload.c`)
- [ ] Add an explicit off-switch: when the DPU's flow-rule limit is reached,
      flip a bool that disables the offload path (falls back to software
      rewriting or sheds) rather than failing open or dropping silently —
      pairs with the rule-count-leak mitigation already noted above (SC5)

### Gap: BlueField lab deployment change (not yet proposed)

Both BlueField proposals explicitly push this out of scope and assume it exists
as a separate change — but no proposal has been written. It covers:

- [ ] `run_core.sh`'s AWS assumptions (`ec2-user`, `/usr/local/bin/meson`,
      `aws ec2 describe-instances`) made lab-portable
- [ ] Endpoint VM provisioning in the RUNS lab (client, server, ClientNIC)
- [ ] Lab DNS (or a documented decision to keep working around it offline)

`bluefield-servernic-hw-offload`'s Success Criterion 4 (end-to-end TCP through
the DPU) is not observable until this lands. Migration target for the
AWS-to-university move: the BlueField DPU replaces the ServerNIC **VM**,
reusing the same C codebase (`flow_table.c`, `syn_handler.c`, `checksum.c`)
rather than a rewrite — already how `bluefield-servernic-hw-offload` is scoped.

## Human-readable experiment output

**Goal:** `run_experiment.sh` output is tuned for the Claude agent driving
`/run-experiment` — dense, log-shaped, easy to grep. A human reading the same
run has to reconstruct what happened. Make the run legible to a person without
taking the structure the agent relies on away.

- [ ] Decide the mechanism: a second human-facing view (summary/TUI) alongside
      today's log, or one format that serves both. Do **not** simply reformat
      the existing stream — the skill and `analyze_metrics.py` parse it.
- [ ] Surface the things a human actually looks for: phase progress across the
      4 nodes, established-vs-target connection count, pass/fail per check, and
      the handful of counters that explain a failure (`imissed`, `rx_nombuf`,
      `oerrors`, `truncated_frames`) — not every line of node output.
- [ ] Keep the final report under `experiments/<mode>/reports/` as the durable
      artifact; this is about the live run, not the report.

## Multi-round send in the load generator

**Goal:** each connection currently does one write and closes. Extend it to
**three sequential sends** so the run exercises steady-state translation, not
just the handshake and one segment.

Note: the load generator is `experiments/utils/loadgen.py` (asyncio), not iperf
— iperf's thread-per-connection model was replaced in PR #27. `_client_conn()`
does `write(nbytes)` → `write_eof()` → close, and never reads a response.

- [ ] Add a request/response loop: N rounds (default 3) of client send → server
      echo/ack → client waits, before close. Knob alongside `--bytes`.
- [ ] Confirm what this actually tests that one send does not — post-handshake
      ServerNIC seq/ack rewriting across multiple client→server segments *and*
      the server→client direction, which a write-only connection never drives.
- [ ] Check the metric definitions still hold: `send_unlock` and `server_gap`
      key off the *first* payload segment, so they should be unaffected, but
      FCT now covers 3 round trips and is not comparable to prior runs.
- [ ] Decide whether 3 rounds becomes the default for the #21 comparison, or an
      opt-in mode so existing numbers stay comparable.

## DDoS resistance

**Goal:** the 0-RTT design is structurally a spoofing amplifier — ClientNIC
answers every SYN with a SYN-ACK before the server has agreed to anything, and
allocates flow-table state doing it. Characterise that exposure and decide what,
if anything, to do about it.

- [ ] Write down the threat model first. This is an isolated lab with no
      untrusted clients, so the question is what a *production-shaped* design
      would need, not what this demo is currently at risk from.
- [ ] SYN flood → state exhaustion: every SYN consumes a flow-table entry on
      both SmartNICs (`FT_SIZE=262144`) plus, on ServerNIC, buffer memory under
      the 1 GiB `FT_MAX_BUFFERED_BYTES` ceiling. Measure where a flood degrades
      first and whether the shedding path behaves.
- [ ] Reflection/amplification: a spoofed source address gets a SYN-ACK sent to
      a third party for free. Note it explicitly even if unmitigated by design.
- [ ] Overlaps [the burst-gap idea](#idea-close-the-100k-connection-burst-gap) —
      SYN-cookie-style backpressure appears there as a *performance* fix and
      here as a *defence*. Scope them together or decide they are one change.

## AWS cross-region deployment

**Goal:** run the chain across two AWS regions — Client + ClientNIC in one,
ServerNIC + Server in another — so the RTT the 0-RTT saving is measured against
is real WAN latency, not `tc netem`.

Today `endpoint.sh` applies the full `NETEM_RTT_MS` on the Server's egress
inside a single VPC (it was 50 ms on both endpoints until 2026-08-04). That is
reproducible but synthetic: no real jitter, reordering, or path variance, and
the 1-RTT saving is measured against a number we chose. It also cannot show an
FCT gain at all — see [F2](#f2--move-the-emulated-wan-to-the-middle-leg-blocking),
which a real inter-region path would resolve outright.

- [ ] Extend `infra/dpdk/cdk/` to a two-region deployment and decide the
      inter-region path: VPC peering, Transit Gateway, or public IPs.
- [ ] Establish which knobs stop being valid — netem comes off, MTU/PMTU across
      the peering link needs checking against the 2048-byte frame ceiling, and
      the port-space assertion still has to hold.
- [ ] Rework orchestration for two regions: `ssm.sh` and the node scripts assume
      one region's `describe-instances`.
- [ ] Success measure: a completed run whose baseline-vs-DPDK delta is reported
      against measured inter-region RTT, so the 1-RTT claim rests on a real
      path. Pairs naturally with [#21](#21--run-experiment-on-both-dpdk-and-baseline-stacks).
- [ ] Cost check before deploying — cross-region data transfer is billed, and
      100k-connection runs move real volume.

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
