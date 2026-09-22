# Human-readable experiment output

**Goal:** Make a live experiment run legible to a person — one line per phase, every
check result, a closing scorecard — while the complete log goes to a file the workflow
bot commits to GitHub for the agent.

**Architecture:** `experiments/lib/output.sh` becomes the single definition of
`log`/`pass`/`fail`/`warn` and a dual sink: everything appends to `$RUN_LOG`, only
phase lines, check results and the scorecard reach the terminal on fd 3. Each of the
four runners sources it, calls `output_init` once before any output, and traps
`print_scorecard` on EXIT. The workflow copies `$RUN_LOG` into the committed bundle as
`experiment-full.log`.

**Tech Stack:** Bash (`set -uo pipefail`), Python 3 + pytest, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-19-human-readable-experiment-output-design.md`

**Global Constraints:**
- **No dependency on `2026-09-08-streamline-experiments-harness.md`.** The earlier
  revision of this plan declared one and was wrong to: `experiments/lib/output.sh`,
  `experiments/run.sh` and `experiments/tests/` do not exist, so nothing could be
  verified against them. This plan builds against the repo as it is today — four
  runners at `experiments/{dpdk,baseline-tcp,proxmox,scapy}/run_experiment.sh`, each
  defining the four output helpers inline (`dpdk:55-58`, `baseline-tcp:52-55`,
  `proxmox:51-54`, `scapy:54-57`), and tests under `experiments/utils/tests/`.
- **Task 1 is also streamline's task 1.** Creating `experiments/lib/output.sh` as the
  one definition of the four helpers is exactly what that plan's task 1 asks for, so
  the two do not collide in either order: if this lands first, streamline's task 1
  finds the file already there; if streamline lands first, task 1 here becomes an edit
  rather than a create, and the task outcome is stated as an end state so it reads the
  same way. Streamline's task 3 later relocates `experiments/utils/tests/` to
  `experiments/tests/`, carrying the new test with its siblings; streamline's task 5
  can move the `output_init` call from the four runners into `run.sh` unchanged.
- **The redirect lives in `output_init`, not in an entrypoint.** There is no
  `experiments/run.sh` to hold it, and inventing a thin one would collide with
  streamline task 5. `output_init` is a function in `output.sh` that each runner calls;
  that is one line per runner and survives the later consolidation.
- Node-side scripts (`experiments/nodes/*.sh`, `experiments/*/clientnic.sh`,
  `experiments/*/servernic.sh`, `experiments/run_think_sweep.sh`) keep their own local
  `log()` definitions. They execute on remote VMs and cannot source a laptop-side file.
  "Defined once" scopes to the four laptop-side runners only.
- No change to `src/`, measurement semantics, `analyze_metrics.py` or `loadgen.py`.
- `FAILURES` accounting and each runner's exit code (= failure count) are unchanged.
- NIC counters (`imissed`, `rx_nombuf`, `oerrors`, `truncated_frames`) are not surfaced
  in the compact view.
- Every `verify:` command runs offline — no AWS, no live VMs, no Docker. The one that
  drives a runner shims `aws` as a shell function first.
- The log path is the environment variable `RUN_LOG`, default
  `/tmp/experiment-full.log`, overridable by the caller. The workflow relies on this
  exact name and default.

---

- [ ] 1 Make `lib/output.sh` the single dual-sink output module — verify: `export RUN_LOG=/tmp/verify-output-1.log; rm -f /tmp/verify-output-1.log; OUT=$( . experiments/lib/output.sh; output_init; log "Step 1: phase marker"; log "ordinary chatter"; echo "stray raw line"; pass "check one"; fail "check two"; fail "check four"; warn "check three"; print_scorecard; printf 'FAILURES=%s\n' "$FAILURES" >&3 ); grep -qF "Step 1: phase marker" /tmp/verify-output-1.log && grep -qF "ordinary chatter" /tmp/verify-output-1.log && grep -qF "stray raw line" /tmp/verify-output-1.log && grep -qF "check one" /tmp/verify-output-1.log && grep -qF "check two" /tmp/verify-output-1.log && grep -qF "check three" /tmp/verify-output-1.log && printf '%s\n' "$OUT" | grep -qF "Step 1: phase marker" && printf '%s\n' "$OUT" | grep -qF "check one" && printf '%s\n' "$OUT" | grep -qF "check two" && printf '%s\n' "$OUT" | grep -qF "check three" && printf '%s\n' "$OUT" | grep -qF "/tmp/verify-output-1.log" && printf '%s\n' "$OUT" | grep -qF "FAILURES=2" && ! printf '%s\n' "$OUT" | grep -qF "ordinary chatter" && ! printf '%s\n' "$OUT" | grep -qF "stray raw line"`
    - File: `experiments/lib/output.sh` (new)
    - Outcome: end state — `experiments/lib/output.sh` is the only laptop-side
      definition of `log`, `pass`, `fail`, `warn` and the `RED`/`GREEN`/`YELLOW`/`NC`
      colour variables. All four functions write their full line (timestamp included,
      exactly today's text) to fd 1. To fd 3 go only `log` lines whose message starts
      with `Step `, and every `pass`/`fail`/`warn` line. `output_init` truncates
      `$RUN_LOG`, saves the current stdout as fd 3 (`exec 3>&1`) and redirects fd 1 and
      fd 2 to `$RUN_LOG`, so stray `echo` and raw node output land only in the file.
      `print_scorecard` writes to fd 3 the pass, fail and warn counts, the report path
      (`${REPORT_FILE:-none}`, the variable `dpdk/run_experiment.sh:204` sets) and
      `$RUN_LOG`. `RUN_LOG` defaults to `/tmp/experiment-full.log` when unset.
      `FAILURES` accounting is exactly as before: `fail` increments it and nothing else
      touches it.
    - Verify note: the command sources the module (subject), drives all four helpers
      plus `output_init` and `print_scorecard`, and asserts on both sinks. The oracle —
      which lines must reach the file, which must reach fd 3, which must not, and the
      resulting `FAILURES` count — is written into the verify line itself and is not
      authored by this sprint. Confirmed to exit 0 against a working module and nonzero
      against a stub whose functions echo without splitting.
    - Commit: `feat(experiments): add lib/output.sh with a full-log and compact-view split`

- [ ] 2 Wire all four runners to the shared module — verify: `aws() { return 1; }; export -f aws; rm -f /tmp/verify-output-2.log /tmp/verify-output-2.out; RUN_LOG=/tmp/verify-output-2.log timeout 120 bash experiments/dpdk/run_experiment.sh > /tmp/verify-output-2.out 2>&1; grep -qF "Step 0" /tmp/verify-output-2.log && grep -qF "ERROR:" /tmp/verify-output-2.log && grep -qF "Step 0" /tmp/verify-output-2.out && grep -qF "/tmp/verify-output-2.log" /tmp/verify-output-2.out && ! grep -qF "ERROR:" /tmp/verify-output-2.out && test "$(grep -lE "^log\(\)" experiments/*/run_experiment.sh | wc -l)" -eq 0 && bash -n experiments/dpdk/run_experiment.sh && bash -n experiments/baseline-tcp/run_experiment.sh && bash -n experiments/proxmox/run_experiment.sh && bash -n experiments/scapy/run_experiment.sh`
    - File/area: `experiments/dpdk/run_experiment.sh:55-58`,
      `experiments/baseline-tcp/run_experiment.sh:52-55`,
      `experiments/proxmox/run_experiment.sh:51-54`,
      `experiments/scapy/run_experiment.sh:54-57`
    - Outcome: each runner replaces its inline four-line helper block with
      `source "$(dirname "$0")/../lib/output.sh"`, then `output_init`, then
      `trap print_scorecard EXIT` — placed where the block was, which is before the
      runner's first output and after its `FAILURES=0`. The scorecard therefore prints
      on every exit path, including the early `exit 1` when node discovery fails. Each
      runner's existing closing summary block and `exit "$FAILURES"` are untouched; the
      summary now lands in `$RUN_LOG` and the scorecard is its terminal counterpart. The
      `RED`/`GREEN`/`YELLOW`/`NC` assignments each runner makes locally are removed,
      since `output.sh` supplies them.
    - Verify note: this is the `verify-feasibility` Test 3 carve-out shape. `aws` — the
      only external the dpdk runner reaches for — is shimmed as a shell function first,
      the real runner then executes and dies at node discovery in about a second, and
      the assertions are on the two sinks it produced: `Step 0` and the raw `ERROR:`
      line both in `$RUN_LOG`, only `Step 0` plus a scorecard naming the log path on
      stdout. The oracle is the shim plus these assertions, none of it authored by this
      sprint. The `grep -lE` and `bash -n` clauses cover the other three runners, which
      cannot be driven offline. Confirmed to exit 0 against all four runners wired and
      nonzero against the unwired tree.
    - Commit: `feat(experiments): route every runner through the shared output module`

- [ ] 3 Pin both sinks with a mock-transport test — verify: `pytest experiments/utils/tests/test_output.py -q`
    - File: `experiments/utils/tests/test_output.py` (new), following the stubbing
      pattern in `experiments/utils/tests/endpoint_mock_harness.sh` and
      `experiments/utils/tests/test_endpoint_sh.py`
    - Outcome: the test drives a mocked run through the real `experiments/lib/output.sh`
      and a runner with its transport stubbed, and asserts (a) every emitted
      `log`/`pass`/`fail`/`warn` line and all stray stdout/stderr appears in the
      `$RUN_LOG` file; (b) the captured fd-3 stream carries exactly the `Step N` lines,
      all PASS/FAIL/WARN lines and the scorecard, in order; (c) none of `imissed`,
      `rx_nombuf`, `oerrors`, `truncated_frames` appears on the compact stream;
      (d) `FAILURES` after the run equals the number of `fail` calls and the runner's
      exit code equals it. It fails if any of these change.
    - Verify note: authoring this test *is* the task, so grading it by running it is
      legitimate. It sits in its own sprint precisely so that no sibling implementation
      task is graded by a test this sprint writes.
    - Commit: `test(experiments): pin the full-log and compact-view output split`

- [ ] 4 Commit the full log in the workflow bundle — verify: `python3 -c "import yaml; w=yaml.safe_load(open('.github/workflows/run-experiment.yml')); r=[str(st.get('run','')) for j in w['jobs'].values() for st in j['steps']]; assert any('RUN_LOG=' in x and 'run_experiment.sh' in x for x in r), 'no run step exports RUN_LOG alongside the runner invocation'; assert any('RUN_LOG' in x and 'experiment-full.log' in x for x in r), 'no bundle step copies RUN_LOG to experiment-full.log'"`
    - File: `.github/workflows/run-experiment.yml`
    - Outcome: the "Run experiment" step (`:207-222`) exports
      `RUN_LOG=/tmp/experiment-full.log` in the same `run` block that invokes
      `"./experiments/$EXP_DIR/run_experiment.sh"`, and the "Assemble results bundle"
      step (`:245-302`) copies it when present to `$OUT/experiment-full.log`, next to
      the existing `cp /tmp/experiment.log "$OUT/experiment.log"` at `:295`. The
      existing `git add experiments/ci-results/` at `:367` picks it up with no change.
      `experiment.log` is still the `tee` of the runner's stdout, which is now the
      compact view.
    - Verify note: GitHub Actions cannot run offline, so the criterion is the workflow
      file's static shape. The command parses the YAML and asserts on the real `run`
      blocks rather than grepping raw text, which is the parse-only check the rubric
      allows for a static-shape criterion. Confirmed to exit nonzero against the current
      workflow.
    - Commit: `ci(experiments): commit the full run log as experiment-full.log`

- [ ] 5 Point the skills and roadmap at the full log — verify: `grep -qF 'experiment-full.log' .claude/skills/offline-analysis/SKILL.md && grep -qF 'experiment-full.log' .claude/skills/run-experiment/SKILL.md && grep -qF 'experiment-full.log' roadmap.md && grep -qF 'experiment.log' .claude/skills/offline-analysis/SKILL.md`
    - File/area: `.claude/skills/offline-analysis/SKILL.md`,
      `.claude/skills/run-experiment/SKILL.md`, `roadmap.md`
    - Outcome: both skills tell the agent to read `experiment-full.log` first and to
      treat `experiment.log` as the human summary — both filenames appear, so the agent
      is not left thinking `experiment.log` is gone. `roadmap.md`'s "Human-readable
      experiment output" section records the compact view as done, links this plan, and
      notes that NIC counters and established-vs-target connection counts were left out.
    - Verify note: the criterion is that three documents name a file. There is no
      runtime to exercise, so text presence is the criterion here, not a proxy for it.
    - Commit: `docs(experiments): point skills and roadmap at experiment-full.log`

## Sprint Graph

```sprint-graph
{
  "maxParallel": 3,
  "sprints": [
    { "id": 1, "name": "dual-sink module", "tasks": [1], "dependsOn": [], "touches": ["experiments/lib/output.sh"] },
    { "id": 2, "name": "wire the runners", "tasks": [2], "dependsOn": [1], "touches": ["experiments/baseline-tcp/run_experiment.sh", "experiments/dpdk/run_experiment.sh", "experiments/proxmox/run_experiment.sh", "experiments/scapy/run_experiment.sh"] },
    { "id": 3, "name": "pin both sinks", "tasks": [3], "dependsOn": [2], "touches": ["experiments/utils/tests/test_output.py"] },
    { "id": 4, "name": "workflow copy", "tasks": [4], "dependsOn": [], "touches": [".github/workflows/run-experiment.yml"] },
    { "id": 5, "name": "docs", "tasks": [5], "dependsOn": [], "touches": [".claude/skills/offline-analysis/SKILL.md", ".claude/skills/run-experiment/SKILL.md", "roadmap.md"] }
  ],
  "waves": [[1, 4, 5], [2], [3]]
}
```

**Why this shape.** Sprint 1 creates the module. Sprint 2 wires it and is graded by
driving a real runner against the module that already exists by then. Sprint 3 writes
the test and is graded by that test, which is the one case where a sprint may grade
itself. No two sprints share an oracle, and no sprint's oracle is authored by the
sprint that claims it. Sprints 4 and 5 touch nothing under `experiments/` and carry no
dependency, so they run in the first wave alongside sprint 1.
triage-verdict: ok
