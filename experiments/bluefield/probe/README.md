# eswitch-offload-probe

A reproducible procedure for determining whether the BlueField-3 e-switch can
match a TCP flow, rewrite its sequence/acknowledgment numbers by a per-flow
constant, and hairpin the packet back out the ingress port — entirely in
hardware. See `openspec/changes/verify-eswitch-tcp-seq-offload/proposal.md`
and `design.md` for the full rationale.

## Target hosts

| Host | Address | Role |
|---|---|---|
| `bluefield-runs3-dpu` | `10.13.36.16` (DPU ARM, user `ubuntu`) | Runs the DOCA Flow probe / `rte_flow` cross-check; owns `pf0hpf` |
| `bluefield-dev` | `10.13.37.10` (x86 host VM, user `bluefieldadmin`) | Owns the ConnectX-7 PF as `ens16f0np0`; generates and captures traffic |

Both hosts are reached over the RUNS lab OpenVPN tunnel with raw-IP routing
(no gateway jump host) using the existing `~/.ssh/claude_code_ed25519` key.
See `.claude/skills/runs-lab-connect/` for VPN setup and
`experiments/bluefield/probe/lib/hosts.sh` for the `dpu_run`/`vm_run`
transport helpers every script in this directory sources.

## Prerequisites

- RUNS lab OpenVPN tunnel active.
- `~/.ssh/claude_code_ed25519` present and authorized on both hosts (or
  override `DPU_HOST`/`DPU_USER`/`VM_HOST`/`VM_USER`/`PROBE_SSH_KEY` via
  environment variables — see `lib/hosts.sh`).
- Docker available locally (or on whichever machine builds the probe image —
  it needs working DNS to pull `nvcr.io/nvidia/doca/doca:2.9.3-devel`; the
  DPU itself does not).

## What the probe mutates, and how it restores

Running `run_probe.sh` end to end:

1. Allocates hugepages on the DPU ARM.
2. Detaches `pf0hpf` from `ovsbr1` so the probe can own it as a DPDK
   data-plane port.
3. Brings `ens16f0np0` up on the x86 VM.
4. Loads the probe's Docker image on the DPU (see "Container transport"
   below).
5. Leaves a detached probe container running for the duration of the hold
   window (see "The hold window" below).

Every one of these is reverted by `restore.sh`, which `run_probe.sh` invokes
on every exit path — including early failure — via a `trap ... EXIT`, so an
aborted run never leaves the DPU half-mutated (design.md D5). `restore.sh`
also diffs the post-run `ovs-vsctl show` against the pre-run baseline
(`baseline.sh`'s output) and exits non-zero if they don't match, so an
incomplete restoration cannot be silently reported as success.

**Management is never touched.** The DPU is reached over `oob_net0`, a
separate physical port from the data path (`pf0hpf`/`ens16f0np0`). Detaching
`pf0hpf` from `ovsbr1` cannot sever SSH access to the DPU, because `oob_net0`
carries no data-plane traffic and nothing in this probe ever runs a command
against it. This is what makes the spike safe to run against shared lab
infrastructure — see design.md's Context, fact 3.

## Container transport

The DOCA devel container (`nvcr.io/nvidia/doca/doca:2.9.3-devel`) ships
`meson` and `ninja`, but the DPU ARM's host OS has no working DNS resolver
and no compiler toolchain of its own. Rather than fix DPU-side DNS,
`build_image.sh` builds the probe binary inside that container **on a
machine that has DNS** (your workstation or CI, wherever `run_probe.sh` is
invoked from), saves the built image to a tarball with `docker save`, `scp`s
it to the DPU, and `docker load`s it there. No registry pull and no DNS
resolution ever happen on the DPU itself. This follows the same pattern as
`infra/bluefield/deployment/Dockerfile` and `compress_doca_image.sh`.

## The hold window

A flow rule only proves anything while packets are actually crossing it, so
the rule install and the traffic generation must overlap. `flow_rule.sh`
starts the probe **detached** (`docker run -d`) and returns as soon as the
container prints `RULE INSTALLED`; the probe then keeps its pipe entry alive
for `--hold-secs` (default 30) while `traffic.sh` sends and captures. Only
after that does `run_probe.sh` read the hardware counter and the ARM
software-queue count out of `docker logs` and append them to `flow_rule.log`,
where `verdict.sh` evaluates them.

That ordering is the whole point: reading the counter at install time — before
any packet exists — would report zero on every run regardless of what the
hardware did, making a `YES` verdict unreachable. Tune the window with
`PROBE_HOLD_SECS` if `traffic.sh`'s capture window is lengthened; it must
comfortably exceed the capture plus SSH round-trip latency.

The container is deliberately **not** `--rm`: it has to survive its own exit
so its counters can be read. `restore.sh` removes it.

## Capture direction

`traffic.sh` transmits and captures on the same interface (`ens16f0np0`), so
it captures **inbound only** — `tcpdump -Q in` plus a `not ether src <own
MAC>` filter, two guards because `-Q` is silently ignored on some capture
paths. Without them tcpdump records the script's own outgoing packet and
every run looks like something came back, which collapses design.md D4's
split-horizon case (rewrite worked, nothing returned) into "returned
unmodified" — the two lead to different next changes.

## Reading the verdict

`verdict.sh` (invoked as the last step of `run_probe.sh`) evaluates three
independent levels per design.md D2, plus the conditional cross-check per D6,
and writes the result to `experiments/bluefield/reports/<run-id>/verdict.txt`:

- **Accepted** — the rule-creation call returned a valid handle.
- **Offloaded** — the rule's hardware counter incremented while the probe's
  own ARM software RX queue received zero packets during its poll window.
- **Effective** — `tcpdump` on `ens16f0np0` shows a returned packet whose
  sequence number is `sent ± delta`.

| Verdict | Meaning |
|---|---|
| **YES** | All three levels hold. Decisive — the e-switch can do the rewrite in hardware, through the API most likely to ship. |
| **PARTIAL (split-horizon)** | Accepted and offloaded, but nothing returned on the wire. Likely e-switch split-horizon blocking the same-port return, not a rewrite failure — the named architectural fallback is a Scalable Function as egress instead of returning out `pf0hpf` (design.md Alternative C). |
| **PARTIAL (rte_flow-only)** | DOCA Flow did not demonstrate the capability, but the `rte_flow` cross-check (`crosscheck.sh`, run automatically only on a DOCA Flow negative) accepted the same rewrite. The capability exists on this silicon but is reachable only through `rte_flow` on this DOCA build — settles the companion change's API decision. |
| **NO** | DOCA Flow did not demonstrate the capability, and the `rte_flow` cross-check also rejected it. Not an API exposure gap — a silicon/build limit. |
| **PARTIAL (inconclusive)** | DOCA Flow didn't demonstrate the full capability and no cross-check result is available to disambiguate yet (e.g. the cross-check step didn't run). |

A YES or a definitive NO/PARTIAL is only ever produced once evidence has been
captured for every level that applies — `verdict.sh` never infers success
from a rule-creation return code alone (design.md D2's core caution: rule
acceptance is not evidence of hardware execution).

## Running it

```bash
./run_probe.sh --src-ip 10.13.37.10 --dst-ip 10.13.36.16 \
  --src-port 12345 --dst-port 80 --seq 1000000 --delta 424242
```

Evidence and the verdict land under
`experiments/bluefield/reports/<run-id>/` (baseline, build, setup, flow-rule,
traffic, cross-check when run, restore, and verdict logs). Executing this
against the real `bluefield-runs3-dpu`/`bluefield-dev` pair and recording the
resulting verdict document is task 13 in
`openspec/changes/verify-eswitch-tcp-seq-offload/tasks.md` — a manual step,
since this sandbox has no VPN, SSH key, DPU, or Docker daemon to run it with.
