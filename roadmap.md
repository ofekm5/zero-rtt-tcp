# Roadmap

Open work only. Completed items are recorded in their reports, PRs, and
`docs/openspec/changes/archive/` — see [Done ledger](#done-ledger) for pointers.

## Status snapshot

Ranked easiest win first — least infra, fewest blockers, smallest change.

| # | Item | State | Why this rank |
| --- | --- | --- | --- |
| 1 | [Human-readable experiment output](#human-readable-experiment-output) | Scoped — needs task-runner to implement | Local only: output + `experiments/` cleanup, no infra |
| 2 | [Multi-round send in the load generator](#multi-round-send-in-the-load-generator) | Spec in progress — resume: `claude --resume eb195814-eae8-41d0-98cc-198bf41f38ba` | One function in `loadgen.py`, already being specced |
| 3 | [QUIC comparison](#quic-comparison) | Scoped, validation is in progress — resume: `claude --resume 25d15f2d-0439-4a70-b4db-945b03dbfe9d` | New experiment arm, no data-plane change |
| 4 | [Phase 1 — BlueField as ServerNIC](#phase-1--bluefield-as-servernic) | Main line — porting decided, phase not scoped | Needs lab + runs3, but no external blocker |
| 5 | [DDoS: purge delta rows](#ddos-purge-delta-rows) | Idea — not scoped | ServerNIC flow table only, unit-testable without a stack |
| 6 | [`verify-eswitch-tcp-seq-offload`](docs/openspec/changes/verify-eswitch-tcp-seq-offload/proposal.md) | Preemptive, off the Phase 1 path — in progress, DPU left mutated | 2/5 done; blocked on a sudo password + DPU restore |
| 7 | [Cross-region split](#cross-region-split) | Idea — not scoped | Two-region CDK + orchestration rework, billed transfer |
| 8 | [Packet-loss handling](#packet-loss-handling) | Idea — not scoped | Correctness design in the translator |
| 9 | [Phase 2 — BlueField as ClientNIC and ServerNIC](#phase-2--bluefield-as-clientnic-and-servernic) | Main line — sketch, not scoped | Needs runs4 permission |
| 10 | [`bluefield-servernic-hw-offload`](docs/openspec/changes/bluefield-servernic-hw-offload/proposal.md) | Preemptive, off the Phase 1 path — blocked on the spike | Waits on #6 |
| 11 | [Scale up experiments on BlueField](#scale-up-experiments-on-bluefield) | Idea — not scoped | Needs Phase 1/2; re-opens an out-of-scope limitation |
| 12 | [CDN comparison](#cdn-comparison) | Idea — not scoped | Undefined — needs framing before effort is knowable |
| 13 | [Read the XFir paper](#read-the-xfir-paper) | Idea — not scoped | Reading task; brief over it for relevant table-eviction details |
| 14 | [Claude Code on uni VM](#claude-code-on-uni-vm) | Idea — not scoped | One-host setup; enables autonomous goal loops with direct validation |
| 15 | [Reconcile the superpowers plans](#reconcile-the-superpowers-plans-before-queuing-for-task-runner) | Scoped (from #39) — plan edits + two small root files | Prerequisite for queuing anything on the nightly task-runner |
| 16 | [Use Jev to check new flows](#use-jev-to-check-new-flows) | Idea — not scoped (from #40) | Source issue had no body; needs framing first |

## Human-readable experiment output

**Status:** scoped already — needs task-runner to implement.

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
- [ ] Refine the metric names themselves, not just the output framing —
      `send_unlock`, `server_gap`, and FCT are internal shorthand from
      `experiments/measurement-methodology-review.md` with no meaning on
      sight. Either rename them in the code/output to say what they measure
      (e.g. "time blocked in connect()", "flow completion time"), or keep the
      short names but always pair them with a one-line definition wherever
      they're printed or reported — decide one convention and apply it
      everywhere (live output, `analyze_metrics.py`, reports, README).

### Refine `experiments/` while doing it

Six entrypoints, two transports, one 21.7 KB shared core, and a stack nobody
runs. A human cannot tell which of these is the live path, which is why the
output is hard to read in the first place — the folder and the run output are
the same legibility problem.

- [ ] Delete the Scapy stack (`experiments/scapy/`, 36 KB across three
      scripts). CLAUDE.md already calls it a deprecated feasibility PoC; git
      history keeps it if it is ever wanted.
- [ ] Decide what stays an entrypoint. Today: `dpdk/`, `baseline-tcp/`,
      `proxmox/`, `scapy/` each ship their own `run_experiment.sh` (12.5 /
      14.3 / 6.9 / 17.0 KB) over the same `lib/core.sh`, plus
      `run_think_sweep.sh` and `dpdk/run_stress.sh`. Both sweeps earn their
      keep — they ask different questions; the four near-duplicate runners are
      the actual duplication.
- [ ] Fold `proxmox/` into a transport choice, not a stack. It differs from
      `dpdk/` only in reaching VMs through `lib/transport/ssh_lab.sh` instead of
      `lib/transport/ssm.sh` — which is a flag, not a fifth orchestrator, and it is
      also what [Phase 1](#phase-1--bluefield-as-servernic) needs anyway.
- [ ] Prune report artifacts: 22 files under `dpdk/reports/` of which 9 are raw
      `run-*.log` dumps from the iperf era, 13 under `baseline-tcp/reports/`,
      and 6 CI bundles (379 KB) under `ci-results/`. Keep the dated reports
      cited by `docs/index.html` and the Done ledger; drop the raw logs.
- [ ] Fix the stale map: CLAUDE.md's module tree still lists
      `experiments/archive/`, which no longer exists, and `experiments/nodes/`
      lost `ebpf-trace.sh`.

## Multi-round send in the load generator

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

### Phase 1 — BlueField as ServerNIC

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

- [ ] `core.sh`'s AWS assumptions — the repo-sync step hardcodes
      `sudo -u ec2-user` and `aws secretsmanager get-secret-value
      --region eu-central-1`, and `experiments/proxmox/run_experiment.sh`
      sources it, so every lab run hits that path today
- [ ] Endpoint VM provisioning in the RUNS lab (Client, Server, and the x86
      ClientNIC VM Phase 1 keeps)
- Already done, not a task: the transport half —
  `experiments/proxmox/run_experiment.sh` + `experiments/lib/transport/ssh_lab.sh`
  reach the 4-VM chain at `10.13.37.10-13` over the RUNS gateway.

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

### Next actions
- [ ] Commit the topology sketch under `docs/` so this section has a stable reference
- [ ] Stand up Phase 1, lab-portability tasks included
- [ ] Promote Phase 1 to an OpenSpec change via
      `spec-planning:openspec-propose-change`

## BlueField-3 hardware-offload track (preemptive, not on the Phase 1 path)

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
[proposal](docs/openspec/changes/verify-eswitch-tcp-seq-offload/proposal.md).

### `bluefield-servernic-hw-offload` — blocked on the spike

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

## Ideas — not scoped

Each needs a proposal before work starts. Ordered as in the status snapshot. Two of them (DDoS, scale on BlueField) re-open limitations
the project has declared out of scope — see [`docs/kb/wiki/Known Limitations.md`](docs/kb/wiki/Known%20Limitations.md).

### QUIC comparison

**Status:** scoped, validation is in progress — resume:
`claude --resume 25d15f2d-0439-4a70-b4db-945b03dbfe9d`

Add QUIC as a third arm in `experiments/` next to the plain-TCP baseline and
the DPDK 0-RTT stack.

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

### Packet-loss handling

Make the system tolerate loss on either side (lost SYN-ACK, data, or ACK around
the translation point) and test it.

### Scale up experiments on BlueField

Run the larger-load experiments on the BF-3 side. Depends on Phase 1/2.

### CDN comparison

Compare against a CDN, or use a CDN as the actual replacement for the
client/server endpoints.

### Read the XFir paper

Professor-sent SIGCOMM paper. Not directly about 0-RTT — it accelerates flow
setup via optimized table lookups and custom hardware — but its flow-table
handling may be relevant: entries are kept until a flow is set up/offloaded,
with details on how entries are removed. Brief over it and check whether
anything is worth mimicking, particularly for
[DDoS: purge delta rows](#ddos-purge-delta-rows).

### Claude Code on uni VM

Install Claude Code on the university VM so goal loops (`/task-runner --goal`)
can run there directly, with the VM itself as the validation mechanism
(compile/run/test in place) instead of routing through local sessions or lab
SSH plumbing.

### Reconcile the superpowers plans before queuing for task-runner

Originated as GitHub issue #39. The repo is being onboarded to the nightly
task-runner (issues labeled `task-runner-todo` build unattended, one at a time),
but the three plans in `docs/superpowers/plans/` assume different trees and
cannot be queued in any order as written.

| Plan | Assumes | Conflicts with |
| --- | --- | --- |
| `2026-09-08-streamline-experiments-harness` | today's tree | Task 7 **deletes** the four `run_experiment.sh` runners and `experiments/scapy/`; task 3 requires `experiments/utils` to be **gone**; task 4 moves `loadgen.py` to `experiments/nodes/` |
| `2026-09-19-human-readable-experiment-output` | **pre-streamline** tree | Task 2 edits all four runners (incl. `experiments/scapy/run_experiment.sh`); task 3 adds `experiments/utils/tests/test_output.py` — streamline deletes or moves all of these |
| `2026-09-19-quic-comparison` | **partly post-streamline** (`experiments/run.sh`, `experiments/nodes/`) | Task 1 writes `experiments/utils/loadgen_quic.py` and diffs `experiments/utils/loadgen.py`, which streamline removes or moves |

- [ ] Keep `streamline-experiments-harness` first — both 09-19 plans partly
      assume it.
- [ ] Rewrite `human-readable-experiment-output` against the post-streamline
      layout (`experiments/lib/`, `experiments/run.sh`), or drop it if
      streamline's single entrypoint covers it.
- [ ] Point `quic-comparison` at `experiments/nodes/` instead of
      `experiments/utils/`, and mark its task 6 ("Run all four arms and write
      the table up") `manual review` — it needs live AWS runs, and its `verify:`
      only counts `*quic*` report files and greps `docs/index.html`, so an
      offline builder could only pass it by fabricating reports.
- [ ] Queue them one at a time — the runner skips a repo while a task-runner PR
      in it is still open.
- [ ] Add a root `pytest.ini` so task-runner's whole-change suite gate has a
      declared suite to run (today it finds none).
- [ ] Add `.task-runner/prepare.sh` (`pip install pytest pyyaml aioquic`).

Note: the issue predates the latest `main` — `quic-comparison` has since merged
(PR #42) and `experiments/utils/` still exists, so re-check each conflict above
against the current tree before acting on it.

### Use Jev to check new flows

Originated as GitHub issue #40 (title only, no body): use Jev to make sure a new
flow won't need our solution. Intent is unrecorded — needs framing (what Jev is
here, what "new flow" means, and what the check outputs) before it can be scoped.

## Done ledger

Evidence lives in the linked artifacts, not here.

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
