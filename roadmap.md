# Roadmap

Open work only. Completed items are recorded in their reports, PRs, and
`openspec/changes/archive/` — see [Done ledger](#done-ledger) for pointers.

## Status snapshot

| Item | State |
| --- | --- |
| [Scale beyond the measured load](#out-of-scope-scale-beyond-the-measured-load) | Out of scope — acknowledged limitation |
| [Demo A — BlueField reflector, no NIC VMs](#demo-a--bluefield-reflector-no-nic-vms) | Sketch — not scoped |
| [Demo B — all-VM 4-chain on Proxmox](#demo-b--all-vm-4-chain-on-proxmox) | Sketch — not scoped |
| [Demo C — BlueField as ClientNIC, ServerNIC stays a VM](#demo-c--bluefield-as-clientnic-servernic-stays-a-vm) | Sketch — not scoped |
| [Human-readable experiment output](#human-readable-experiment-output) | Idea — not scoped |
| [Multi-round send in the load generator](#multi-round-send-in-the-load-generator) | Idea — not scoped |
| [DDoS resistance](#ddos-resistance) | Idea — threat model not written |
| [`verify-eswitch-tcp-seq-offload`](openspec/changes/verify-eswitch-tcp-seq-offload/proposal.md) | In progress — DPU left mutated, restore first |
| [`bluefield-servernic-hw-offload`](openspec/changes/bluefield-servernic-hw-offload/proposal.md) | Proposed — blocked on the spike |
| [BlueField lab deployment change](#gap-bluefield-lab-deployment-change-not-yet-proposed) | Gap — no proposal exists yet |

## Out of scope: scale beyond the measured load

**Acknowledged limitation, not planned work.** `docs/index.html` §6 carries the
same statement; no figure in that report depends on it.

The measured claim rests on 2000-flow runs at 500 conn/s. Concurrency there is
roughly 50-100 flows in flight (arrival rate x mean FCT), well under the 2000 the
`LOAD_CONCURRENCY=2000` cap allows — at that volume the cap never binds, so 2000
*concurrent* flows are not demonstrated either. Runs at 100,000 total flows have
never completed:

| Run | Plain TCP | 0-RTT |
| --- | --- | --- |
| 2026-07-25 (unpaced) | — | 68,779 / 100,000 |
| 2026-08-11 | 100,000 / 100,000 | 84,143 / 100,000 |
| 2026-08-17 | 99,728 / 100,000 | 87,073 / 100,000 |

Both 2026-08-17 runs also failed their endpoint metric check (326 and 171
unresolvable metric events), and latency at that load is queueing rather than
path (plain TCP p95 blocking reached 64.1 s). The harness is therefore implicated
alongside the data plane.

**What is not established:** that the shortfall is unrelated to the 0-RTT
mechanism. Under identical conditions baseline lost 0.3% where 0-RTT lost 12.9%,
an asymmetry shared infrastructure limits would not produce. The defensible
statement is "not demonstrated at scale", not "limited by infrastructure" — the
latter is a finding, and the runs do not support it.

Sketched and not pursued: RSS/multi-queue, SYN-cookie-style backpressure, arrival
pacing (landed, and did not close the gap), and a pre-generated ISN pool in place
of per-SYN `rte_rand()`.

If this is ever re-opened, one measurement defect comes first: `loadgen.py`
reports achieved arrival rate from coroutine-spawn timing, not from connection
establishment (`_client_conn` takes the semaphore inside the task, so the spawn
loop never blocks on it). Every 100k arrival-rate figure recorded so far is
unreliable on that axis.

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
- [ ] Decide whether 3 rounds becomes the default for the DPDK-vs-baseline
      comparison, or an
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
- [ ] Overlaps [the scale limitation](#out-of-scope-scale-beyond-the-measured-load) —
      SYN-cookie-style backpressure appears there as a *performance* fix and
      here as a *defence*. Scope them together or decide they are one change.

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
  [the scale limitation](#out-of-scope-scale-beyond-the-measured-load).
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
  security-group scoping question is closed — the narrow `10.1.0.0/16` scope
  stays, since `conntrack_allowance_exceeded` read 0 on both endpoints after the
  100k run. Re-open only if a future run reports it above 0 in `ethtool -S eth0`.
