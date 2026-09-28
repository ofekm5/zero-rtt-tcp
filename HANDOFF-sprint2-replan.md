# Handoff — fix the Sprint 2 plan, then re-run the harness task-runner

**Focus of the next session:** re-decompose plan Tasks 5–6 so each sprint fits the task-runner's
400-inserted-lines-per-round budget, then re-run `/task-runner:launch-task-runner` for the rest of
`2026-09-08-streamline-experiments-harness`.

## Where things stand (2026-09-26)

- **PR #38** (https://github.com/ofekm5/zero-rtt-tcp/pull/38) — run 2's sprint 1 (plan Tasks 3+4:
  `utils/` → `lib/` + `lib/transport/`, VM scripts → `nodes/`, tests → `experiments/tests/`) plus
  pre-landing-review fixes. Open, not merged. Tasks 1–2 were already on `main` from run 1 (PR #36).
- **Remaining:** Tasks 5–10 in `docs/superpowers/plans/2026-09-08-streamline-experiments-harness.md`.
  Design doc: `docs/superpowers/specs/2026-09-08-streamline-experiments-harness-design.md`.
- **Run record:** `docs/superpowers/plans/2026-09-08-streamline-experiments-harness/.harness/`
  (on the PR #38 branch; `run-report.md`, `plan.md`, per-sprint `contract.md`). Run 1's record is
  `.harness-run1/` beside it.

## Why Sprint 2 failed

There was no `sprint-graph` block in the plan doc, so the planner put Tasks 5 and 6 in one sprint. Its
first build round inserted **1,043 lines** against the fixed `DIFF_BUDGET_LINES=400` (insertions only, per
round), which ends the lane as `diff-budget-exceeded`. Sprints 3 and 4 were then `dependency-blocked`.

| file | +ins | −del |
|---|---|---|
| `experiments/lib/core.sh` (absorb shared flow) | 285 | 207 |
| `experiments/run.sh` (new) | 368 | 0 |
| `experiments/tests/test_run_sh.py` (new) | 390 | 0 |

Splitting only by task is **not enough**: `run.sh` + the `core.sh` changes come to about 653 lines. Task 5
itself has to be split, e.g. 5a "absorb the shared flow into `lib/core.sh`" and 5b "`run.sh` dispatch on
`STACK`/`TRANSPORT`", each with its own `verify:` command. Task 6 on its own (about 390 lines) is just
under the cap and risky, so consider asking for a smaller test (see the builder notes below).

The fix goes in the plan doc: split the Task N list, and add a dictated `sprint-graph` block (tasks per
sprint, `dependsOn`, `touches`, `maxParallel`, approved `waves`) so the planner can't regroup them. The
other route, raising the budget, is a harness change in the task-runner skill, not in this repo.

### Read the failed attempt before re-planning

The attempt is kept in the lane worktree
`C:/Users/shir/Documents/GitHub/.task-runner-worktrees/2026-09-08-streamline-experiments-harness-s2`
(branch `task-runner/2026-09-08-streamline-experiments-harness-s2`, commit `a21528d`). Its notes are
at `.harness/sprint-2/round-1/build-notes.md` in that worktree (gitignored, so this is the only copy).
They raise plan-level problems:

- **Task 6's outcome text is wrong.** It says the 0rtt+ssm and 0rtt+ssh sequences "differ only in the
  transport shim and `REPO_PATH`". In reality they also differ in a transport prologue: SSM smoke-tests
  the forwarder (only the old dpdk runner did this), and the lab reads MACs off the VMs. The plan should
  state the real difference.
- **Existing bug:** `experiments/lib/measure.sh:164` `run_ttfb_measurement` calls `ssm_run` directly,
  and `lib/transport/ssh_lab.sh` never defines it. Under `TRANSPORT=ssh` the client load round never
  runs. The old `proxmox/run_experiment.sh` has the same bug. Decide: fix it (it's measurement-adjacent,
  and the Global Constraints freeze `measure.sh` logic) or keep pinning it in the test.
- Baseline now also runs the local port-space preflight. That's a small behaviour change; decide whether
  it's OK.
- The test pins command prefixes of 60 characters. Full-command parity tests skip once Sprint 3 deletes
  the old runners.

### Also worth fixing while editing the plan

- Design doc SC2 still measures `grep -rl '^log()' experiments/ | wc -l` = 1. Plan Task 1 says a
  repo-wide count is invalid, because VM scripts keep their own `log()`. Run 2's planner narrowed it to
  `experiments/lib/` on its own. Make the design doc agree.
- Task 5's `verify:` is `bash -n` + `grep STACK/TRANSPORT`, a text-presence check. Once Task 5 is split,
  give 5a/5b behavioural verifies.

## Before re-running: clean up stale state

`bootstrap.sh` **reuses an existing branch** and ignores `base_ref`. Stale branches therefore make new lanes
start from old commits.

1. Merge (or close) PR #38 first, so the next run starts from `main` with sprint 1 in it.
2. Archive the lane-2 branch and remove its worktree. The auto-mode classifier blocks this, so the user
   runs it with `!`:
   `git worktree remove --force ../.task-runner-worktrees/2026-09-08-streamline-experiments-harness-s2 && git branch -m task-runner/2026-09-08-streamline-experiments-harness-s2 archive/run2/2026-09-08-streamline-experiments-harness-s2`
3. The integration branch `task-runner/2026-09-08-streamline-experiments-harness` is PR #38's branch.
   After the merge, archive it too (or fast-forward it to `main`). Otherwise bootstrap attaches to it.
4. Delete the empty, Windows-locked directory `../.task-runner-worktrees/2026-09-08-streamline-experiments-harness`
   if it is still there.

## Harness gotchas on this Windows box

- **Invoke in flat mode with the plan path**, not the bare change name. The bare name matches no
  directory or `.md`:
  `/task-runner:launch-task-runner docs/superpowers/plans/2026-09-08-streamline-experiments-harness.md`
- `bootstrap.sh`/`teardown.sh` compare worktree paths as strings, so `/c/...` never matches git's
  `C:/...`. Pass the `C:/Users/...` form to `bootstrap.sh`. `teardown.sh` always says "already gone", so
  do a clean-check plus a plain `git worktree remove` by hand.
- `integration-gate.sh` runs bare `pytest`, which isn't on PATH, and `venv/Scripts/pytest.exe` exits 1
  silently. Verifier and grader agents get it through the rtk hook, but the gate doesn't. Workaround: put
  a `pytest` shim on PATH (`exec /c/Python313/python -m pytest "$@"`), or repair the venv.
- Builder sandbox denials in sprint 2: "`ssh` in command position with no shell-function shim". The
  mock-transport test needs any `ssh` stub defined as a shell function before first use.

## Suggested skills

- `spec-planning:authoring-tasks-artifact`: rules for the plan doc's Task N list and the dictated
  `sprint-graph` block. Load before editing the plan.
- `spec-planning:authoring-design-artifact`: if you edit design doc SC2 or the Task 6 outcome wording.
- `engineering-rigor:grill-me`: optional; stress-test the new split before committing it.
- `task-runner:launch-task-runner`: the re-run, in flat mode (see above).
- `engineering-rigor:pre-landing-review` and `engineering-rigor:open-pr`: run by the task-runner's finish
  step.
