# Plan: 2026-09-08-streamline-experiments-harness

## Summary
Collapse `experiments/` from six entrypoints across four stack folders to a single `experiments/run.sh` parameterised on `STACK` (`0rtt` | `baseline`) and `TRANSPORT` (`ssm` | `ssh`), with every shared helper defined exactly once and each directory meaning one thing.

## Sprints
1. core.sh honours STACK — tasks 5.1
2. run.sh dispatch — tasks 5.2
3. pin run.sh remote-call sequence — tasks 6
4. run.sh report under reports/\<stack\>/ — tasks 8
5. delete the runners, move the sweeps — tasks 7
6. retarget callers at run.sh — tasks 9

## Triage notes
Triage-skip guard applied: `triage-verdict: ok` was found in the plan file (`docs/superpowers/plans/2026-09-08-streamline-experiments-harness.md`). The sprint-graph block is carried verbatim from the plan file. Tasks 1–4 are already complete (PRs #36 and #38); Task 10 is manual review and stays human work. SC2's design-doc verify command was narrowed from `experiments/` to `experiments/lib/` in the additional C3 criterion of sprint 5 — VM-side node scripts intentionally retain their own `log()` per Task 1's explicit scope note, so the repo-wide count is not 1 and never will be; scoping to `lib/` captures the actual intent (shared helpers defined once in the laptop-side library). All six dictated task verify commands passed the verify-feasibility rubric.

## Already done
- Task 1: Extract shared output helpers to lib/output.sh (PR #36)
- Task 2: Unify DPDK and baseline report writers in lib/report.sh (PR #36)
- Task 3: Move laptop-side code to lib/ with transport shims split out (PR #38)
- Task 4: Move all VM-executed scripts into nodes/ (PR #38)

## Blockers
(none)

```plan-meta
{
  "verdict": "ok",
  "sprints": [
    { "id": 1, "name": "core.sh honours STACK", "tasks": [5.1], "dependsOn": [], "touches": ["experiments/lib/core.sh"] },
    { "id": 2, "name": "run.sh dispatch", "tasks": [5.2], "dependsOn": [1], "touches": ["experiments/run.sh", "experiments/lib/transport"] },
    { "id": 3, "name": "pin run.sh remote-call sequence", "tasks": [6], "dependsOn": [2], "touches": ["experiments/tests/test_run_sh.py"] },
    { "id": 4, "name": "run.sh report under reports/<stack>/", "tasks": [8], "dependsOn": [3], "touches": ["experiments/run.sh", "experiments/lib/report.sh", "experiments/reports", "experiments/tests", "experiments/README.md"] },
    { "id": 5, "name": "delete the runners, move the sweeps", "tasks": [7], "dependsOn": [4], "touches": ["experiments"] },
    { "id": 6, "name": "retarget callers at run.sh", "tasks": [9], "dependsOn": [5], "touches": [".github/workflows/run-experiment.yml", ".claude/skills/run-experiment", ".claude/skills/offline-analysis", "CLAUDE.md", "experiments/README.md", "experiments/run.sh", "experiments/lib", "experiments/nodes", "experiments/sweeps"] }
  ],
  "manualTasks": [
    "- [ ] 10 Rewrite the roadmap section to match the corrected ordering — manual review"
  ],
  "triage": {
    "skippedReason": "triage-verdict: ok found in plan file (docs/superpowers/plans/2026-09-08-streamline-experiments-harness.md)"
  }
}
```
