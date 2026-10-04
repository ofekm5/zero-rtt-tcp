# Roadmap

The urgent Overleaf draft update comes first, followed by the two BlueField
phases and the open plans. Larger BlueField experiments require both phases and
access to the university lab. Optional extensions are separate from the
academic PoC; completed work is in the [Done ledger](#done-ledger).

## Status snapshot

Priority follows the sections below. Optional extensions have their own list.

| # | Item | State | Next step / dependency |
| --- | --- | --- | --- |
| 1 | **[Add results to the Overleaf draft](#add-results-to-the-overleaf-draft)** | **Urgent — open** | Transfer the current experiment results into the academic draft |
| 2 | **[Phase 1 — BlueField as ServerNIC](#phase-1--bluefield-as-servernic)** | **Urgent — porting decided, phase not scoped** | Stand up the one-DPU lab topology |
| 3 | [Phase 2 — BlueField as ClientNIC and ServerNIC](#phase-2--bluefield-as-clientnic-and-servernic) | Main line — sketch, not scoped | Needs runs4 permission |
| 4 | [Scale up experiments on BlueField](#scale-up-experiments-on-bluefield) | Conditional — not scoped | University lab only; after Phases 1 and 2 finish |
| 5 | [Human-readable experiment output](#human-readable-experiment-output) | Partially implemented — compact view still open | Shared helpers exist; dual sink, scorecard and full-log bundle are missing |
| 6 | [Multi-round send in the load generator](#multi-round-send-in-the-load-generator) | Spec in progress | Finish the request/response design |
| 7 | [QUIC comparison](#quic-comparison) | Original comparison complete; TLS extension open (lowest priority) | Add endpoint TLS and compare cold secure connections |

## Urgent

### **Add results to the Overleaf draft**

**Status:** urgent — open.

- [ ] Add the current experiment results from `docs/index.html` and the linked
      reports to the Overleaf draft, including the measurement setup,
      comparison results and relevant limitations.

## Demo topologies (lab / Proxmox) — the main line

Two phases, built in order. Both move
the demo off AWS ENIs onto the RUNS lab and **run today's C data plane
(`flow_table.c`, `syn_handler.c`, `checksum.c`) as a plain DPDK application on
the DPU's ARM cores** — a rebuild against DOCA/DPDK, not a rewrite. Endpoint
VMs (Client, Server) and the deployment plumbing are the same in both.

The two BlueField OpenSpec changes — [`verify-eswitch-tcp-seq-offload`](#verify-eswitch-tcp-seq-offload--in-progress-dpu-left-mutated)
and [`bluefield-servernic-hw-offload`](#bluefield-servernic-hw-offload--blocked-on-the-spike)
— were started **before** these phases and explore an optimisation on top of
them. Neither phase depends on either one; see [the hardware-offload
track](#bluefield-3-hardware-offload-track-preemptive-not-on-the-phase-1-path).

### The port model both phases use

The app binds the DPU's **physical ports directly** as DPDK ports — `p0` and
`p1` on the ARM side, the two PF uplinks — and nothing else. No scalable
functions, no VFs, no OVS representor bridging, no e-switch rules. The DPU is a
physical bump in the wire and the seq/ack rewrite stays in software on ARM,
which makes the port model identical to what `src/servernic/dpdk/io.c` already
does with two ENIs: two ports, poll one, rewrite, transmit on the other. The
change is the build target and the port names, not the data plane.

- Open: whether both uplinks on the runs3 card are cabled and usable. If only
  one is, the second leg has to come back through the host PF representor
  (`pf0hpf`), which changes the topology from `p0`↔`p1` to `p0`↔`pf0hpf` and
  drags the host's OVS bridge back into the path.

### **Phase 1 — BlueField as ServerNIC**

Client VM → ClientNIC VM → **BlueField running the ServerNIC app** → Server VM.
The x86 ClientNIC DPDK forwarder is unchanged; only the ServerNIC role moves
onto the DPU, reusing the same C code rebuilt for the ARM cores with `p0`/`p1`
bound into the app. One DPU (runs3).

- Smallest step off the current all-VM stack: one role changes host, the other
  three nodes stay as they are.
- No e-switch involvement at all, so Phase 1 does **not** wait on the
  `verify-eswitch-tcp-seq-offload` verdict. It does exercise
  `bluefield-servernic-hw-offload`'s deployment shape, so that change's offload
  backend can land later behind its existing boundary.
- Open: does the virtual switching on the *endpoint VMs'* hosts perturb the
  latency being measured (OVS vs. Linux bridge vs. SR-IOV passthrough)? The DPU
  side is direct-bound and out of that question.
- Open: DPDK on the lab's virtual NICs for the x86 ClientNIC VM — `virtio`/
  vhost-user vs. SR-IOV VFs, or an AF_XDP/AF_PACKET fallback.

#### Porting guidelines (decided — Phase 2 inherits them)

How today's data plane moves onto the DPU, settled so neither phase
re-litigates it. The [port model](#the-port-model-both-phases-use) states *what*
is bound; this states *how the app is packaged and what changes in the code*.

**Stay a vanilla executable.** No containers on either platform. A DPU-native
DPDK binary bound to `p0`/`p1` has no AMI, no vfio-pci-on-ENI and no CDK stack
behind it, so the ServerNIC node deploys by building on the DPU. DPDK there
needs hugepages, vfio and version-matched DOCA/DPDK from the host regardless,
so a container keeps every constraint and adds an image build to the loop.
`systemd` unit + binary built natively on the ARM cores — the spike's
`build_probe.sh` already proved that toolchain (DOCA 3.0.0058 / DPDK 22.11 on
runs3), and there is no docker daemon running on the DPU anyway. The one case
that would justify a container is a DOCA workload deployed the platform's way
(`doca_container_deploy` YAML + BFB), which the offload track may need later
and neither phase needs now.

**No scalable functions.** SFs exist to give a *separate* function its own
queues and netdev — several isolated apps on the DPU, or handing a container a
netdev without exposing the whole PF. One dataplane process binding the
physical ports needs neither.

#### Phase 1 tasks

Porting `src/servernic/dpdk/` to the DPU:

- [ ] **PMD: ENA → mlx5.** Port setup differs (devargs, and `dv_flow_en=1` only
      if e-switch rules are ever used); the parse/rewrite/transmit path in
      `pipeline.c`, `translator.c`, `checksum.c` does not.
- [ ] **Peer MACs.** `--client-mac` / `--server-mac` / `--gw-mac` still work as
      explicit peering. If the second uplink turns out uncabled and the topology
      falls back to `p0`↔`pf0hpf`, the host side becomes a representor and the
      peer MAC is the server host's — see the open cabling question under the
      port model.
- [ ] **Inline by placement, not by routing.** DPU mode puts the ARM on the path
      by construction; there is no CDK route-table equivalent to build. Confirm
      the card is in DPU/embedded mode first —
      `mlxconfig -d <dev> q INTERNAL_CPU_MODEL` — or the ARM never sees host
      traffic and nothing else in this section applies.
- [ ] **Keep management off the data ports.** Binding an uplink to DPDK takes it
      from the ARM kernel. SSH stays on the OOB 1GbE port (`oob_net0` /
      `tmfifo_net0`) — the same rule as the dedicated management ENI on EC2, and
      the same failure mode as the mid-run VPN drop that left the DPU mutated.

What the port does *not* carry, and Phase 1 still owns:

- [x] Repo-sync transport split: `experiments/lib/core.sh` now has a
      `TRANSPORT=ssh` branch that avoids `ec2-user` and Secrets Manager.
      Validate the remaining lab deployment assumptions during Phase 1.
- [ ] Endpoint VM provisioning in the RUNS lab (Client, Server, and the x86
      ClientNIC VM Phase 1 keeps)
- Already done, not a task: the transport half —
  `TRANSPORT=ssh ./experiments/run.sh` + `experiments/lib/transport/ssh_lab.sh`
  provide the lab path; confirm node addresses and gateway configuration
  against the current lab setup before deploying.

### Phase 2 — BlueField as ClientNIC and ServerNIC

Client VM → **BlueField #1 (ClientNIC app)** → **BlueField #2 (ServerNIC app)**
→ Server VM. Both 0-RTT roles run on hardware, each app direct-bound to its
DPU's `p0`/`p1`; no ClientNIC/ServerNIC VMs. This is the hardware-only end
state.

- Needs a second DPU — the runs4 card, which requires another student's
  permission. Secure it before scoping this phase.
- ClientNIC's job (spoof the SYN-ACK, stamp V in the SYN ack-num) is
  per-handshake and should suit the ARM cores; ServerNIC's per-packet rewriting
  is the part the e-switch offload exists to avoid, so if ARM-only throughput
  is going to bind anywhere it binds here — that is what makes the offload
  track worth having later, not a reason to block on it now.

### Scale up experiments on BlueField

**Conditional:** these experiments can run only in the university lab, after
both Phase 1 and Phase 2 are finished and have passing runs at the existing
measured load. Do not schedule the larger-load work before those prerequisites.

- [ ] Confirm university lab access and passing Phase 1 and Phase 2 runs at the
      existing measured load.
- [ ] Increase load in matched steps, recording established-vs-target flows,
      loss counters and latency to distinguish capacity limits from path latency.
- [ ] Address the measurement caveats in
      [Known Limitations](docs/kb/wiki/Known%20Limitations.md) before interpreting
      the larger-load results. Scale beyond the measured load remains an
      extension of the current academic claim, not a prerequisite for it.

### Next actions
- [ ] Commit the topology sketch under `docs/` so this section has a stable reference
- [ ] Stand up Phase 1, lab-portability tasks included
- [ ] Promote Phase 1 to an OpenSpec change via
      `spec-planning:openspec-propose-change`

## Open plans

### Human-readable experiment output

**Status:** partially implemented; keep open. The
[plan](docs/superpowers/plans/2026-09-19-human-readable-experiment-output.md)
asks for a compact terminal view plus a complete log, not just shared helpers.

**Repo evidence:** `experiments/lib/output.sh` defines `log`/`pass`/`fail`/`warn`,
but has no `output_init`, dual sink or `print_scorecard`. There is no
`experiments/tests/test_output.py`. The workflow still tees the entire stream
into `experiment.log`; it neither exports `RUN_LOG` nor bundles `experiment-full.log`.

- [ ] Implement phase lines, every check result and a closing scorecard on the
      terminal, while retaining all stdout/stderr in the complete log.
- [ ] Wire this through the current `experiments/run.sh` entrypoint and add the
      output tests under `experiments/tests/`; the plan's four-runner and
      `experiments/utils/tests/` paths predate the harness consolidation.
- [ ] Bundle `experiment-full.log` in `.github/workflows/run-experiment.yml`,
      retaining `experiment.log` as the compact human summary.
- [ ] Update the run-experiment and offline-analysis skills to read the full
      log first once it exists.

The harness consolidation is recorded in [Done ledger](#done-ledger).
Established-vs-target counts, NIC counters and metric-label improvements are
[optional presentation work](#experiment-presentation-polish), outside this plan.

### Multi-round send in the load generator

**Status:** spec in progress. Fast way to keep iterating:
`claude --resume eb195814-eae8-41d0-98cc-198bf41f38ba`

**Goal:** each connection currently does one write and closes. Extend it to
**three sequential sends** so the run exercises steady-state translation, not
just the handshake and one segment.

Note: the load generator is `experiments/nodes/loadgen.py` (asyncio), not iperf
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
- [ ] Decide whether 3 rounds becomes the default for the DPDK-vs-baseline
      comparison, or an
      opt-in mode so existing numbers stay comparable.

### QUIC comparison

**Status:** original implementation merged in [PR #42](https://github.com/ofekm5/zero-rtt-tcp/pull/42);
the four-arm AWS measurement and [write-up](docs/index.html#quic-comparison)
were completed on 2026-10-03. The TLS comparison below is a new, lower-priority
extension, scheduled after the other open plans.
[Original plan](docs/superpowers/plans/2026-09-19-quic-comparison.md) ·
[Original design](docs/superpowers/specs/2026-09-19-quic-comparison-design.md).
The original design excluded TCP+TLS; revise that scope before implementation.

Keep plain TCP versus DPDK 0-RTT TCP as the primary evidence for the middleware's
benefit. Retain the existing QUIC results as context: TCP was plaintext while
QUIC encrypted, so those numbers do not establish an advantage for equivalent
secure applications. All resumed QUIC flows reused one primed ticket.

- [x] Run all four original arms at the same settings, write the `send_unlock`
      table in `docs/index.html`, and validate the reported results.
      At 100/s, 2000 connections per arm, 1 KB and 100 ms RTT, with m5.xlarge
      endpoints: median send_unlock was 101.007 ms TCP, 0.338 ms 0-RTT TCP,
      104.395 ms QUIC cold, and 1.436 ms QUIC resumed. All checks passed.
      [Bundles and calibration](experiments/ci-results/20261003-quic-comparison/README.md).
- [ ] Add a standard TLS 1.3 client/server workload at the application endpoints
      for both ordinary TCP and accelerated TCP. Use explicit request framing
      and a server acknowledgment suitable for TLS streams; TLS stays at the
      endpoints, with no custom packet sender or TLS termination in the NICs.
- [ ] Run a cold-connection comparison: ordinary TCP + TLS 1.3, accelerated
      TCP + TLS 1.3, and QUIC. Disable resumption in all three, verify server
      certificates (the current QUIC harness disables verification), and match
      security settings, connection counts, payloads, arrival rate, endpoint
      sizes and `NETEM_RTT_MS`. Calibrate the rate and confirm CPU headroom;
      retain the kernel-routing versus DPDK and NIC-hardware caveats.
- [ ] Measure from a common application-level start point to the first encrypted
      application write and to receipt of the server acknowledgment. Existing
      TCP pcap first-payload timing would count the TLS ClientHello, so it cannot
      stand in for secure-application timing. Validate TLS traffic through the
      middleware on live infrastructure and retain complete run evidence.
      Hypothesis, not a measured result: about 2 RTTs to permit application
      sending for ordinary TCP+TLS versus 1 RTT for accelerated TCP+TLS and
      cold QUIC, without loss or handshake retries.
- [ ] Publish the matched TLS results in `docs/index.html` with their limits.
      Defer a resumed comparison until explicit TLS early-data support and
      acceptance checks exist; session resumption alone does not provide
      0-RTT application sending.

## Optional extensions — not mandatory for the academic PoC

These nice-to-have items do not gate the academic PoC or Phase 1.
Implementation items need framing and a proposal before work begins. DDoS and
scale beyond the measured load re-open
[acknowledged limitations](docs/kb/wiki/Known%20Limitations.md);
BlueField scaling remains conditional on both lab phases.

| Item | State | Dependency / scope |
| --- | --- | --- |
| [Read the XFir paper](#read-the-xfir-paper) | Reading — not scoped | Review flow-table setup and eviction details |
| [Research Scallop](#research-scallop) | Research — not scoped | Read the paper and inspect its BlueField-3 prototype |
| [DDoS: purge delta rows](#ddos-purge-delta-rows) | Idea — not scoped | Flow-table eviction and SYN-flood resilience |
| [Cross-region split](#cross-region-split) | Idea — not scoped | Two-region infrastructure and orchestration |
| [CDN comparison](#cdn-comparison) | Idea — not scoped | Define the comparison first |
| [Packet-loss handling](#packet-loss-handling) | Idea — not scoped | Loss-recovery correctness design |
| [Hardware-offload spike](#verify-eswitch-tcp-seq-offload--in-progress-dpu-left-mutated) | In progress; last recorded state: DPU mutated | Restore the DPU; traffic test needs sudo access |
| [ServerNIC hardware offload](#bluefield-servernic-hw-offload--blocked-on-the-spike) | Blocked on spike | Follow Phase 1; depends on spike verdict |
| [Experiment presentation polish](#experiment-presentation-polish) | Idea — not scoped | Extra counters, metric definitions and raw-log cleanup |
| [Use Jev to check new flows](#use-jev-to-check-new-flows) | Idea — not scoped (#40) | Clarify the original intent |

### Read the XFir paper

Professor-sent SIGCOMM paper. Not directly about 0-RTT — it accelerates flow
setup via optimized table lookups and custom hardware — but its flow-table
handling may be relevant: entries are kept until a flow is set up/offloaded,
with details on how entries are removed. Brief over it and check whether
anything is worth mimicking, particularly for
[DDoS: purge delta rows](#ddos-purge-delta-rows). The reading could also add
value to system design by informing efficient reads and writes to memory,
particularly in the flow-table lookup and update paths.

### Research Scallop

Read [Scallop](https://github.com/Princeton-Cabernet/Scallop) and its paper,
*Scalable Video Conferencing Using SDN Principles*. The repo separates a
hardware data plane from a software control plane and includes a BlueField-3
P4 prototype under `hardware/bluefield`.

- [ ] Inspect the BlueField prototype's packet-processing and control-plane
      boundaries for ideas applicable to the ServerNIC design.
- [ ] Record which ideas transfer to this TCP PoC and which depend on Scallop's
      WebRTC workload or P4 platform. This is research, not a new implementation
      dependency for Phase 1.

### DDoS: purge delta rows

Add an eviction/purge mechanism for the per-flow delta table on ServerNIC so
SYN floods can't exhaust it. Nothing evicts today: every SYN holds an entry in
`FT_SIZE=262144` plus buffer memory under the 1 GiB `FT_MAX_BUFFERED_BYTES`
ceiling until the flow closes.

### Cross-region split

Put the client side and server side in different AWS regions — a real WAN
instead of the emulated middle-leg delay.

- [ ] Extend `infra/dpdk/cdk/` to two regions and pick the inter-region path:
      VPC peering, Transit Gateway, or public IPs.
- [ ] Rework orchestration: `ssm.sh` and the node scripts assume one region's
      `describe-instances`.
- [ ] Cost check before deploying — cross-region data transfer is billed.

### CDN comparison

Compare against a CDN, or use a CDN as the actual replacement for the
client/server endpoints.

### Packet-loss handling

Make the system tolerate loss on either side (lost SYN-ACK, data, or ACK around
the translation point) and test it.

### BlueField-3 hardware-offload track (preemptive, not on the Phase 1 path)

Both changes below predate the [demo-topology
phases](#demo-topologies-lab--proxmox--the-main-line) and target the same
optimisation: moving ServerNIC's per-packet seq/ack rewrite off the ARM cores
and into the e-switch. **Phases 1 and 2 do the rewrite in software on ARM
with `p0`/`p1` bound straight into the app, so neither waits on this track.**
Order of work:
Phase 1 first, then this — it lands behind its existing backend boundary once
there is a working DPU data plane to attach it to.

- [ ] Simplify the e-switch experimentation harness and stop overloading the
      DPU while iterating on it — the spike needed nine defect fixes and left
      the DPU mutated (VPN drop mid-run) and blocked (no sudo password) just
      to get this far; that's a sign the harness itself is too heavy for
      iterative probing, not only the probe logic.

#### `verify-eswitch-tcp-seq-offload` — in progress, DPU left mutated

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
[proposal](docs/openspec/changes/verify-eswitch-tcp-seq-offload/proposal.md).

#### `bluefield-servernic-hw-offload` — blocked on the spike

DPU-side ServerNIC that offloads post-handshake seq/ack rewriting to the
e-switch, keeping the ARM cores out of the data path (handshake only). New
`src/servernic/bluefield/` target reusing `flow_table.c`, `syn_handler.c`,
`checksum.c`; offload API stays behind a backend boundary until the spike
resolves it. Criteria in the
[proposal](docs/openspec/changes/bluefield-servernic-hw-offload/proposal.md).

- [ ] Cache installed e-switch flow rules in memory instead of re-querying/
      reinstalling per flow, once the spike picks a backend (`offload.c`)
- [ ] Add an explicit off-switch: when the DPU's flow-rule limit is reached,
      flip a bool that disables the offload path (falls back to software
      rewriting or sheds) rather than failing open or dropping silently —
      pairs with the rule-count-leak mitigation already noted above (SC5)

### Experiment presentation polish

Follow-up work beyond the compact-output plan:

- [ ] Surface established-vs-target connection counts and diagnostic counters
      (`imissed`, `rx_nombuf`, `oerrors`, `truncated_frames`) in the human view.
- [ ] Pair `send_unlock`, `server_gap` and FCT with plain-language definitions
      consistently in live output, analysis, reports and README.
- [ ] Review obsolete raw `run-*.log` dumps for removal while preserving dated
      reports cited by `docs/index.html` and the Done ledger.

### Use Jev to check new flows

Originated as GitHub issue #40 (title only, no body): use Jev to make sure a new
flow won't need our solution. Intent is unrecorded — needs framing (what Jev is
here, what "new flow" means, and what the check outputs) before it can be scoped.

## Done ledger

Evidence lives in the linked artifacts, not here.

- **Experiment harness entrypoint consolidation** — present in the current repo:
  [`experiments/run.sh`](experiments/run.sh) dispatches by `STACK` and
  `TRANSPORT`; shared output helpers and report writing live under
  [`experiments/lib/`](experiments/lib/), and tests under
  [`experiments/tests/`](experiments/tests/). The old per-stack
  `run_experiment.sh` entrypoints and `experiments/scapy/` are gone; historical
  reports remain. [Plan](docs/superpowers/plans/2026-09-08-streamline-experiments-harness.md).
  This does **not** complete the compact-output plan: the shared helpers still
  emit ordinary stdout/stderr without a dual sink or scorecard.

- **#21 — DPDK vs. baseline comparison** — closed 2026-08-17. Both stacks run
  back to back at identical parameters (2000 conns, 500/s, 4 ports, 1 KB, 100 ms
  modelled RTT), twelve pairs total across three deployments and two orchestration
  paths — 24,000 flows per stack, every run passing every check. Pooled saving:
  −101.30 ms of application blocking, −102.05 ms of completion time. Write-up:
  `docs/index.html`; reports: `experiments/dpdk/reports/integration-test-report-2026-08-{08,11,17-run01..10}.md`
  and `experiments/baseline-tcp/reports/baseline-report-2026-08-{08,11,17-*}.md`.
- **Client-side pcap analysis at 100k** — closed. `analyze_metrics.py` was
  rewritten to stream `tcpdump -r` text one packet at a time (f52a031), keeping
  memory O(flows); the missing-flow symptom was SSM's 24 KB stdout cap silently
  truncating the per-flow output, fixed by `--summary` / `--detail-out`. The
  2026-08-17 100k run analyzed all 87,073 client flows and 85,158 server flows.
  Remaining 100k *metric-check* failures are load-related, tracked under
  the scale limitation in [`docs/kb/wiki/Known Limitations.md`](docs/kb/wiki/Known%20Limitations.md).
- **#18 — full-DPDK endpoint interfaces** — closed 2026-07-25. Change archived at
  `docs/openspec/changes/archive/2026-07-14-full-dpdk-endpoint-interfaces/`; both
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
  security-group scoping question is closed — the narrow `10.1.0.0/16` scope
  stays, since `conntrack_allowance_exceeded` read 0 on both endpoints after the
  100k run. Re-open only if a future run reports it above 0 in `ethtool -S eth0`.
