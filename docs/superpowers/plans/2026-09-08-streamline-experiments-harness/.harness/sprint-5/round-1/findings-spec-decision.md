# Findings — spec-decision lens — sprint 5 round 1

No findings under this lens.

Checked against the resolved design doc
(`docs/superpowers/specs/2026-09-08-streamline-experiments-harness-design.md`,
via `plan_path`'s `Spec:` header) and the plan's Task 7 outcome text
(`docs/superpowers/plans/2026-09-08-streamline-experiments-harness.md`):

- C1/C2 (no `run_experiment.sh` anywhere, `experiments/scapy/` gone, both sweep
  scripts present): confirmed by directory listing; `experiments/proxmox/` is
  also gone, but it only ever contained `run_experiment.sh`
  (`git ls-tree HEAD~1 experiments/proxmox/` shows a single file), so its
  disappearance is the expected side effect of deleting that file, not
  out-of-task deletion.
- `experiments/dpdk/probes/`, `experiments/dpdk/reports/` and
  `experiments/baseline-tcp/reports/` are retained at their current paths —
  matches the design's "Moving historical reports" non-goal and the plan's
  "`experiments/dpdk/probes/` is retained at its current path."
- `experiments/sweeps/think.sh` and `experiments/sweeps/stress.sh`: diffed
  against their pre-move originals (`run_think_sweep.sh`,
  `dpdk/run_stress.sh`). think.sh's `case "$MODE" in dpdk|baseline)` dispatch
  to two different runner paths is replaced by a `STACK` (0rtt|baseline)
  check plus a single `RUNNER="experiments/run.sh"`, matching the plan's
  "`sweeps/think.sh` selects its stack via `STACK` instead of the `case` at
  `run_think_sweep.sh:40-41`." stress.sh keeps `LOAD_RATE=0`, keeps the
  capacity-run caveat banner, and now `exec`s `run.sh` instead of
  `dpdk/run_experiment.sh` — matches "`sweeps/stress.sh` still sets
  `LOAD_RATE=0`, still prints its capacity-run caveat, and execs `run.sh`."
  Both diffs are otherwise limited to path/variable renames, consistent with
  a mechanical move.
- `experiments/lib/core.sh:483` and `experiments/lib/measure.sh:133`: the only
  changes are comment path repoints (`dpdk/run_stress.sh` →
  `sweeps/stress.sh`, `run_think_sweep.sh` → `sweeps/think.sh`); no logic
  change, consistent with the "Global Constraints" byte-identity clause and
  its explicit carve-out for repointing a comment/path string that a move
  invalidates.
- `git diff HEAD~1 HEAD --stat -- src/` is empty — no change to `src/`,
  consistent with the plan's "No change to `src/`" constraint.
- Stale provenance comments in `experiments/lib/{core,endpoint,output,report}.sh`
  still name the deleted runners; this is exactly what the contract's
  out-of-scope section and the plan's Task 9 (sprint 6) defer — Task 9, not
  Task 7, owns "every live caller references only `experiments/run.sh`."
