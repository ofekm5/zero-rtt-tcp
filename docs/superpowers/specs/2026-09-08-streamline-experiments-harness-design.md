# Streamline the experiments harness — design

## Problem

`experiments/` has six entrypoints spread across four stack folders, and a reader
cannot tell from the layout which one is the live path or what actually differs
between them. The duplication is measurable, not impressionistic:

- `experiments/dpdk/run_experiment.sh:38` and `experiments/proxmox/run_experiment.sh:36`
  differ by **one `source` line** — `utils/ssm.sh` vs `utils/ssh_lab.sh`. That is a
  transport flag wearing a directory.
- `log()`, `pass()`, `fail()`, `warn()` are defined **byte-identically in all four**
  runners (`dpdk:55-58`, `baseline-tcp:52-55`, `proxmox:51-54`, `scapy:54-57`).
- The ~100-line report writer is duplicated between `dpdk/run_experiment.sh:201-286`
  and `baseline-tcp/run_experiment.sh`.
- **Six of the eight scripts that execute on a remote VM do not live in `nodes/`**:
  `utils/loadgen.py`, `utils/analyze_metrics.py`, and the four
  `{dpdk,scapy}/{clientnic,servernic}.sh`.
- `.github/workflows/run-experiment.yml` threads an `EXP_DIR` variable through nine
  sites (`:113-115, 210, 213, 215, 255, 275, 298-301, 346, 360, 367`) whose only job
  is to pick which of the four directories to run.
- The Scapy stack (32 KB across three files) is documented in `CLAUDE.md` as a
  deprecated feasibility PoC and is not on any live path.

The underlying fault is that three orthogonal axes — **where code runs** (laptop vs
VM), **which data plane** (0-RTT vs plain TCP), and **which transport** (AWS SSM vs
lab SSH) — are all flattened into a single directory layer, inconsistently. `proxmox/`
encodes a transport as a folder; `dpdk/` encodes a data plane as a folder but also
holds VM scripts; `utils/` holds laptop libraries, transports, *and* two VM programs.

The practical cost is that any harness-wide change must be made four times, or it
drifts. That includes the change the roadmap actually wants next (legible run
output), which is why this one comes first.

## Non-Goals

- **Human-readable run output.** `roadmap.md`'s "Human-readable experiment output"
  section is deferred to its own change and lands *after* this one. Once
  `log/pass/fail/warn` live in one file instead of four, that work is ~50 lines
  rather than ~200 across four runners. This change alters no output formatting.
- **Fixing the Step 4 blackout.** `run_core.sh`'s client-run step is a single
  blocking call with `LOAD_TIMEOUT=1800` that prints nothing until it returns. Real
  gap, but it needs a background poller, not a refactor.
- **Rescuing the truncated NIC counters.** `imissed` / `rx_nombuf` / `oerrors` /
  `truncated_frames` are emitted by `src/clientnic/dpdk-forwarder/main.c:75-98` into
  `/tmp/clientnic.log`, which `run_core.sh:352` fetches with `cat` straight into
  SSM's 24 KB cap. Belongs with the output change.
- **Moving historical reports.** Existing reports under `dpdk/reports/` and
  `baseline-tcp/reports/` stay exactly where they are. ~20 files cite those paths,
  including `docs/index.html`, eight `docs/kb/raw/` entries, and four files under
  `docs/openspec/changes/archive/` that exist to be immutable records.
- **Pruning old report artifacts.** The roadmap notes 22 files under `dpdk/reports/`
  worth thinning, 13 under `baseline-tcp/reports/`, and 6 CI bundles. Independent
  cleanup; not this change.
- **Any change to `src/`.** The data plane is untouched.
- **Any change to measurement semantics.** `measure.sh`, `endpoint.sh`,
  `analyze_metrics.py` and `loadgen.py` move and are re-sourced, but their logic,
  their metric definitions, and their emitted formats do not change.
- **A CLI flag parser.** Rejected during Socratic questioning — see
  `## Alternatives Considered`.
- **A machine-readable event stream (JSON lines) from the runner.** Considered and
  rejected: nothing currently parses runner output, so this would build a contract
  for a consumer that does not exist.
- **Porting the Scapy stack.** It is deleted, not migrated. Git history keeps it.

## Goal

Collapse `experiments/` to a single entrypoint, `experiments/run.sh`, parameterised
on two environment variables — `STACK` (`0rtt` | `baseline`) and `TRANSPORT`
(`ssm` | `ssh`) — with every shared helper defined exactly once, and with a
directory layout in which each folder means one thing: `lib/` runs on the laptop,
`nodes/` runs on a VM, `sweeps/` are multi-run wrappers, `reports/` are outputs,
`tests/` are offline checks.

## Success Criteria

- [ ] `experiments/run.sh` is the only orchestrator; no `run_experiment.sh` remains
      anywhere under `experiments/` — measured by:
      `test -x experiments/run.sh && test -z "$(find experiments -name run_experiment.sh)"`
- [ ] Each shared helper has exactly one definition — the four output functions, and
      the report writer — measured by:
      `[ "$(grep -rl '^log()' experiments/ | wc -l)" -eq 1 ] && [ "$(grep -rl 'Integration Test Report' experiments/lib/ | wc -l)" -eq 1 ]`
- [ ] Behaviour is preserved: for each supported `STACK`×`TRANSPORT` combination,
      `run.sh` issues the same ordered sequence of remote calls the corresponding old
      runner did, and `STACK=baseline` correctly omits the data-plane build and start
      steps — measured by: `pytest experiments/tests/test_run_sh.py -q`
- [ ] Every live caller references only `experiments/run.sh` — the GitHub Actions
      workflow, the `run-experiment` and `offline-analysis` skills, `CLAUDE.md`, the
      harness README, and all live shell code — measured by:
      `! grep -rn 'run_experiment\.sh' .github/workflows/ .claude/skills/ CLAUDE.md experiments/README.md experiments/run.sh experiments/lib/ experiments/nodes/ experiments/sweeps/ --include='*.yml' --include='*.md' --include='*.sh'`
      (Scoped to live callers on purpose. Frozen output keeps its historical
      references: `experiments/*/reports/`, `experiments/ci-results/`,
      `experiments/insights.md` and `experiments/measurement-methodology-review.md`
      narrate past runs and are protected by `## Non-Goals`.)
- [ ] Where a script runs is recoverable from its path: everything executed on a VM
      lives in `experiments/nodes/`, everything executed on the laptop lives in
      `experiments/lib/` — measured by:
      `test -f experiments/nodes/client.sh -a -f experiments/nodes/server.sh -a -f experiments/nodes/clientnic.sh -a -f experiments/nodes/servernic.sh -a -f experiments/nodes/loadgen.py -a -f experiments/nodes/analyze_metrics.py && test -z "$(ls experiments/lib/*.py 2>/dev/null)"`

## Alternatives Considered

### 1. One entrypoint, environment-variable dispatch — **recommended**

`experiments/run.sh` reads `STACK` and `TRANSPORT` from the environment, sources one
transport shim and one shared core, and dispatches. The four runners, the Scapy
stack, and `proxmox/` are deleted.

*Tradeoffs.* Requires folding `baseline-tcp`'s inline step sequence into
`lib/core.sh` as conditionally-skipped steps, which is the only non-mechanical part
of the work. In exchange, the GitHub Actions workflow already feeds knobs as
`KEY=VALUE` pairs into `$GITHUB_ENV` (`run-experiment.yml:163`), so `STACK` and
`TRANSPORT` ride the existing mechanism with no new plumbing, and `EXP_DIR`
disappears from nine sites.

*Verdict.* **Recommended and chosen.** It is the only option that makes the
duplication structurally impossible to reintroduce rather than merely tidied.

### 2. One entrypoint with a CLI flag parser (`--stack`, `--transport`)

Same consolidation, but with `getopts` and a real `--help` so a human can drive a run
from the terminal without remembering variable names.

*Tradeoffs.* Better discoverability for a human at a prompt. But the workflow passes
env vars and would keep doing so, giving two ways to express the same run — and the
user explicitly does not care whether runs happen locally or through Actions, so the
ergonomic benefit buys nothing against the cost of a second interface to keep in
sync. Every other knob in the harness (`LOAD_RATE`, `LOAD_PORTS`, `NETEM_RTT_MS`,
`REPO_REF`) is already an env var; flags for two of them would be inconsistent.

*Verdict.* **Rejected.** Two interfaces is the condition this change exists to
remove.

### 3. Keep the four runners; extract shared helpers only

Leave `dpdk/`, `baseline-tcp/`, `proxmox/` and `scapy/` in place, but hoist
`log/pass/fail/warn` and the report writer into `utils/`. Smallest diff; no caller
outside `experiments/` changes.

*Tradeoffs.* Fixes the duplication that blocks the follow-on output change, and is
genuinely low-risk. But it leaves six entrypoints, leaves `proxmox/` misrepresenting
a transport as a stack, leaves six VM scripts outside `nodes/`, and leaves `EXP_DIR`
threaded through the workflow — so the "which of these do I run?" problem, which is
the user's actual stated complaint, survives untouched.

*Verdict.* **Rejected as the destination, adopted as the first two tasks.** Tasks 1
and 2 are exactly this refactor; the change then continues past it.

### Verification approach — mock transport vs. live run

A separate axis, decided alongside the above. A live before/after run diff is the
strongest evidence a refactor preserved behaviour, but it needs a deployed AWS
stack, takes ~20 minutes per run, produces nondeterministic latency figures that
require hand-reading, and cannot be executed by the downstream task-runner. A
static-only check (shellcheck plus grep guards) is cheap but would pass a broken step
order. **Chosen: a mock-transport pytest** that stubs `remote_run` / `remote_bg` /
`remote_stdout`, records the ordered call sequence, and asserts it per combination —
reusing the pattern already established by `experiments/utils/tests/endpoint_mock_harness.sh`.
It runs offline in seconds and is a real behavioural oracle. One live run remains a
manual pre-merge step, outside the automated criteria.

## Key Constraints

- **No AWS, no Docker, no live VMs in any verify command.** Every check must run
  offline on the developer machine or in CI without infrastructure. This is why the
  SC3 oracle is a mock transport rather than a real run.
- **`STACK=baseline` has no data plane.** `baseline-tcp/run_experiment.sh` sources
  `endpoint.sh` but not `run_core.sh` precisely because there are no NIC binaries to
  build or start. The consolidated `lib/core.sh` must skip the build, start, and
  NIC-log-collection steps for that stack rather than fail them.
- **Report directories keep the stack split.** New runs write to
  `experiments/reports/0rtt/` and `experiments/reports/baseline/`. The headline
  result of this project is a pairwise 0-RTT-vs-baseline comparison; a single flat
  report directory would destroy the pairing.
- **Transport matrix.** `STACK=0rtt` must work over both `ssm` and `ssh`;
  `STACK=baseline` over `ssm` (the deployed baseline infra is AWS-only today).
  `baseline`+`ssh` must not be rejected by `run.sh` — there is simply no lab infra
  for it yet.
- **`REPO_REF` and the VM-side repo path are transport-dependent.** `dpdk/` uses
  `/home/ec2-user/zero-rtt-tcp`, `proxmox/` uses `/home/user/zero-rtt-tcp`. The
  consolidated entrypoint must derive `REPO_PATH` from the transport, not hardcode
  one.
- **Renaming `utils/` breaks Python imports.** `experiments/utils/tests/` imports the
  modules under test by path; the test files move with them and their imports must be
  updated in the same task.
- **`run_core.sh`'s AWS assumptions stay as they are.** The hardcoded
  `sudo -u ec2-user` and `aws secretsmanager` calls in the repo-sync step are a known
  Phase-1 portability problem tracked separately in `roadmap.md`; this change moves
  that code without fixing it, so the lab transport keeps today's behaviour exactly.
