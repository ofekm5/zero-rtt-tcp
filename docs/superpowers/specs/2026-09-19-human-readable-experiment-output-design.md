# Human-readable experiment output — design

## Problem

`run_experiment.sh` output is dense and log-shaped: every `log()` line, every
`pass`/`fail`/`warn`, and raw node output all land on the terminal in one stream. A
person reading a run has to reconstruct what happened — which phase it is in, what
passed, what failed.

Two facts from the codebase shape the fix:

- `log()` writes to stderr and `pass()`/`fail()`/`warn()` write to stdout, so today's
  terminal stream is an unstructured interleave of both
  (`experiments/dpdk/run_experiment.sh:55-58`). The run has natural phases —
  `Step 1` … `Step 7` in `experiments/utils/run_core.sh:221-349` — but they are just
  more `log` lines among hundreds.
- Nothing parses the stream. The workflow only pipes it through
  `tee /tmp/experiment.log` (`run-experiment.yml:217`) and copies that file into the
  bundle (`:295`), which `github-actions[bot]` commits (`:357-387`). That committed file
  is what the agent reads, so whatever is on stdout is what the agent sees — a compact
  stdout would starve it unless the full log is kept separately.

This change does *not* depend on `streamline-experiments-harness`. An earlier
revision said it hooked in at `experiments/lib/output.sh` and `experiments/run.sh`,
which that plan creates — neither exists yet, so nothing could have been verified
against them. It hooks in at the four runners as they stand today, each carrying its
own byte-identical copy of the four helpers (`dpdk:55-58`, `baseline-tcp:52-55`,
`proxmox:51-54`, `scapy:54-57`). Creating `experiments/lib/output.sh` as the one
definition of those helpers *is* `streamline-experiments-harness` task 1, so the two
changes do not collide in either order.

## Non-Goals

- **NIC counters** (`imissed`, `rx_nombuf`, `oerrors`, `truncated_frames`) are not
  surfaced in the compact view, and the truncated-log rescue that
  `streamline-experiments-harness` deferred to "the output change" is dropped, not
  built here. Decided by the user.
- **True established-vs-target connection counts.** No run-level variable carries
  them; `measure.sh:175` only prints "all N connection(s) succeeded" where N counts
  rounds. That existing PASS line appears in the compact view as-is. Parsing
  `loadgen.py` output for real counts is a separate change.
- **A TUI or live dashboard.** Rejected — see Alternatives.
- **A post-hoc summarizer script.** Rejected — see Alternatives.
- **A JSON-lines event stream.** No consumer exists.
- **Fixing the Step 4 blackout** (a single blocking client call that prints nothing
  for up to `LOAD_TIMEOUT`). Needs a background poller.
- **Pruning report artifacts** under `experiments/*/reports/` and `ci-results/`.
- **Committing logs from local runs.** Only workflow runs reach GitHub.
- **Any change to `src/`, measurement semantics, or `analyze_metrics.py`.**

## Goal

Make a live run legible to a person — one line per phase, every check's result, and a
closing scorecard — while keeping the complete log as a file that the existing
workflow bot commits to GitHub, so the agent reads the full record.

## Success Criteria

- [ ] Nothing is lost: with the compact view on, every `log`, `pass`, `fail`, `warn`
      line and all other stdout/stderr of a mocked run still lands in the full log
      file — measured by: `pytest experiments/utils/tests/test_output.py -q`
- [ ] Stdout is compact: for a mocked 0-RTT run, stdout carries exactly one line per
      `Step N`, every PASS/FAIL/WARN, and a final scorecard (pass/fail counts plus
      paths to the report and full log); ordinary `log` chatter and raw node output are
      absent, and NIC counter names do not appear — measured by:
      `pytest experiments/utils/tests/test_output.py -q`
- [ ] Behaviour preserved: `FAILURES` still counts exactly the `fail` calls, each
      runner still exits with that count, and all four runners still parse — measured
      by: `pytest experiments/utils/tests/test_output.py -q` plus the runner-drive
      check in task 2 of the plan
- [ ] The agent can read the full log from GitHub: the workflow copies it into the
      bundle as `experiment-full.log` (committed by the existing bot step) and the
      `offline-analysis` skill names it as the file to read first — measured by:
      `grep -q 'experiment-full.log' .github/workflows/run-experiment.yml .claude/skills/offline-analysis/SKILL.md`

## Architecture Impact

Current shape (today's repo):

```
<stack>/run_experiment.sh   log / pass / fail / warn defined inline, ×4 runners
└─ utils/run_core.sh        Step 1…7, calls the four functions
```

```diff
 <stack>/run_experiment.sh
-│   defines log/pass/fail/warn inline; log() writes every line to stderr
+├─ sources lib/output.sh; calls output_init; traps print_scorecard EXIT    # modified
+experiments/lib/output.sh                                                  # new
+│   the one definition of log/pass/fail/warn; every function appends to
+│   $RUN_LOG; only "Step N" log lines, PASS/FAIL/WARN and print_scorecard()
+│   also write to fd 3; output_init opens $RUN_LOG and redirects fd 1/2
 └─ utils/run_core.sh   (unchanged)
 .github/workflows/run-experiment.yml
+  export RUN_LOG=/tmp/experiment-full.log
+  cp "$RUN_LOG" "$OUT/experiment-full.log"                                  # modified
```

| Component | Path | Change | Responsibility after |
| --- | --- | --- | --- |
| Output helpers | `experiments/lib/output.sh` | new | The one definition of the four helpers; dual sink: full to `$RUN_LOG`, compact to fd 3; adds `output_init` and `print_scorecard` |
| Runners (×4) | `experiments/{dpdk,baseline-tcp,proxmox,scapy}/run_experiment.sh` | modified | Source the module, call `output_init` before any output, trap `print_scorecard` on EXIT |
| Output test | `experiments/utils/tests/test_output.py` | new | Pins the two sinks and the exit code |
| Workflow | `.github/workflows/run-experiment.yml` | modified | Copies `$RUN_LOG` into the bundle; `tee` now captures the compact view |
| Offline skill | `.claude/skills/offline-analysis/SKILL.md` | modified | Points at `experiment-full.log` |
| Run skill | `.claude/skills/run-experiment/SKILL.md` | modified | Same pointer |

**Dependencies and data flow.** No new external dependency. Raw node output that
today reaches the terminal is now written only to `$RUN_LOG`; the terminal receives
only what the four helper functions send to fd 3.

**Contracts and boundaries.** `run.sh` stdout content shrinks. In a CI bundle,
`experiment.log` becomes the compact view and `experiment-full.log` is new. No flag,
schema or permission boundary changes.

**Blast radius.** Readers of run stdout: the workflow `tee` and the two skills
(the streamline design found nothing else parses it). Local runs get a new log file
path they must know to open; the scorecard prints it.

## Alternatives Considered

### 1. Full log to a file, compact view on stdout — **recommended, chosen**

Both sinks live in `lib/output.sh`; `run.sh` sets up the redirect. Small and needs no
new tooling. Costs: the agent must read the file rather than stdout. Verdict:
recommended, because the workflow already commits a log file.

### 2. Post-hoc summarizer over the saved log

Leave the stream alone; a script renders a summary afterwards. Zero risk to the run,
but the roadmap goal is a legible *live* run, and this is not live. Verdict: rejected.

### 3. Live TUI dashboard

Best live view. Adds a dependency, breaks under SSM and the CI `tee`, and is the most
code. Verdict: rejected.

## Key Constraints

- **No prerequisite change.** This lands against today's four runners. `output_init`
  carries the redirect because there is no `experiments/run.sh` to hold it; when
  `streamline-experiments-harness` task 5 creates one, the call moves there unchanged.
- **Exit code stays the failure count**; `FAILURES` accounting in `pass`/`fail` must
  not change.
- **Every `verify:` runs offline** — no AWS, no live VMs, no Docker.
- **The `Step N` prefix is the phase marker.** Compact lines are selected by that
  prefix, so renaming a step in `utils/run_core.sh` changes the compact view.

## Not yet specified

- How a phase line signals its outcome (a plain `Step N` start line vs. a start and
  a done line) — revisit once the mocked run in Task 3 shows what reads well.
