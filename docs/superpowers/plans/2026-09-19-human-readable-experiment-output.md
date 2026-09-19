# Human-readable experiment output

**Goal:** Make a live `run.sh` run legible to a person — one line per phase, every check result, a closing scorecard — while the complete log goes to a file the workflow bot commits to GitHub for the agent.

**Architecture:** `experiments/lib/output.sh` becomes a dual sink (full log to `$RUN_LOG`, compact view on fd 3) wired up by `experiments/run.sh`, and the workflow copies `$RUN_LOG` into the committed bundle as `experiment-full.log`.

**Tech Stack:** Bash (`set -uo pipefail`), Python 3 + pytest, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-19-human-readable-experiment-output-design.md`

**Global Constraints:**
- Depends on `docs/superpowers/plans/2026-09-08-streamline-experiments-harness.md` (tasks 1, 5, 9): `experiments/lib/output.sh`, `experiments/run.sh` and the retargeted workflow lines must already exist. Do not start before they land.
- No change to `src/`, measurement semantics, `analyze_metrics.py` or `loadgen.py`.
- `FAILURES` accounting and the exit code (= failure count) are unchanged.
- NIC counters (`imissed`, `rx_nombuf`, `oerrors`, `truncated_frames`) are not surfaced in the compact view.
- Every `verify:` command runs offline — no AWS, no live VMs, no Docker.
- The log path is the environment variable `RUN_LOG`, default `/tmp/experiment-full.log`, overridable by the caller. The workflow relies on this exact name and default.

---

- [ ] 1 Make `lib/output.sh` a dual sink and add the scorecard — verify: `bash -n experiments/lib/output.sh && grep -q 'print_scorecard' experiments/lib/output.sh && grep -q 'RUN_LOG' experiments/lib/output.sh`
    - File: `experiments/lib/output.sh`
    - Outcome: `log`, `pass`, `fail`, `warn` each append their full line (with timestamp) to `$RUN_LOG`. To the terminal (fd 3) go only `log` lines whose message starts with `Step `, and every `pass`/`fail`/`warn` line. `print_scorecard` writes to fd 3 the pass, fail and warn counts, the report path (`${REPORT_FILE:-none}`, the variable `dpdk/run_experiment.sh:204` sets today — confirm the name survives streamline task 2) and `$RUN_LOG`. `RUN_LOG` defaults to `/tmp/experiment-full.log` when unset. `FAILURES` accounting is exactly as before.
    - Commit: `feat(experiments): split output into full log file and compact terminal view`

- [ ] 2 Wire the redirect and scorecard into `run.sh` — verify: `bash -n experiments/run.sh && grep -q 'RUN_LOG' experiments/run.sh && grep -q 'print_scorecard' experiments/run.sh`
    - File: `experiments/run.sh`
    - Outcome: before any output, `run.sh` truncates `$RUN_LOG`, saves the terminal as fd 3 (`exec 3>&1`) and redirects fd 1 and 2 to `$RUN_LOG`. On exit (including failure) it calls `print_scorecard`, and the process exit code is still `FAILURES`.
    - Commit: `feat(experiments): route run.sh output to a full log and a compact view`

- [ ] 3 Pin both sinks with a mock-transport test — verify: `pytest experiments/tests/test_output.py -q`
    - File: `experiments/tests/test_output.py` (new), following the stubbing pattern in `experiments/tests/test_run_sh.py`
    - Outcome: the test drives a mocked 0-RTT run and asserts (a) every emitted `log`/`pass`/`fail`/`warn` line and stray stdout/stderr appears in the `$RUN_LOG` file; (b) captured stdout equals exactly the `Step N` lines, all PASS/FAIL/WARN lines and the scorecard; (c) none of `imissed`, `rx_nombuf`, `oerrors`, `truncated_frames` appears on stdout; (d) the exit code equals the number of `fail` calls. It fails if any of these change.
    - Commit: `test(experiments): pin the full-log and compact-view output split`

- [ ] 4 Commit the full log in the workflow bundle — verify: `grep -q 'RUN_LOG' .github/workflows/run-experiment.yml && grep -q 'experiment-full.log' .github/workflows/run-experiment.yml`
    - File: `.github/workflows/run-experiment.yml`
    - Outcome: the "Run experiment" step exports `RUN_LOG=/tmp/experiment-full.log` before invoking `run.sh`, and the "Assemble results bundle" step copies it (when present) to `$OUT/experiment-full.log`, next to the existing `experiment.log` copy. The existing `git add experiments/ci-results/` in the bot commit step picks it up with no change. `experiment.log` is still the `tee` of stdout, now the compact view.
    - Commit: `ci(experiments): commit the full run log as experiment-full.log`

- [ ] 5 Point the skills and roadmap at the full log — verify: `grep -q 'experiment-full.log' .claude/skills/offline-analysis/SKILL.md && grep -q 'experiment-full.log' .claude/skills/run-experiment/SKILL.md && grep -q 'experiment-full.log' roadmap.md`
    - File/area: `.claude/skills/offline-analysis/SKILL.md`, `.claude/skills/run-experiment/SKILL.md`, `roadmap.md`
    - Outcome: both skills tell the agent to read `experiment-full.log` first and to treat `experiment.log` as the human summary. `roadmap.md`'s "Human-readable experiment output" section records the compact view as done, links this plan, and notes that NIC counters and established-vs-target counts were left out.
    - Commit: `docs(experiments): point skills and roadmap at experiment-full.log`

## Sprint Graph

```sprint-graph
{
  "maxParallel": 3,
  "sprints": [
    { "id": 1, "name": "dual-sink output", "tasks": [1, 2, 3], "dependsOn": [], "touches": ["experiments/lib/output.sh", "experiments/run.sh", "experiments/tests/test_output.py"] },
    { "id": 2, "name": "workflow copy", "tasks": [4], "dependsOn": [], "touches": [".github/workflows/run-experiment.yml"] },
    { "id": 3, "name": "docs", "tasks": [5], "dependsOn": [], "touches": [".claude/skills", "roadmap.md"] }
  ],
  "waves": [[1, 2, 3]]
}
```
triage-verdict: ok
