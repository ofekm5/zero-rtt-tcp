# Plan: 2026-09-08-streamline-experiments-harness

## Summary
Collapse `experiments/` from six entrypoints across four stack folders to a single `experiments/run.sh` parameterised on `STACK` and `TRANSPORT`, with every shared helper defined exactly once and each directory meaning one thing.

## Sprints
1. Reorganize directory layout — tasks 3, 4
2. Write single entrypoint and mock test — tasks 5, 6
3. Delete old runners and fix report paths — tasks 7, 8
4. Update callers and roadmap — tasks 9, 10

## Triage notes
Triage skipped: `triage-verdict: ok` found in the plan file. Tasks 1 and 2 are already committed to the worktree (`experiments/lib/output.sh` and `experiments/lib/report.sh` exist with the correct content; the four runners no longer define `log()`). The remaining 8 tasks follow a strict linear dependency chain: reorganize the directory layout first (Tasks 3+4), then write `run.sh` and its behavioural test (Tasks 5+6), then delete the old runners and fix the report output paths (Tasks 7+8), then update all external callers and docs (Tasks 9+10). The design doc's SC2 first clause (`grep -rl '^log()' experiments/`) is infeasible as written because VM scripts legitimately keep their own `log()` — the acceptance criterion in Sprint 1 narrows the scope to `experiments/lib/` only, matching the design doc's stated intent ("exactly one definition in `experiments/lib/`"). Task 10 (roadmap update) is a narrative prose change; its suggested verify command is a text-presence check that fails the feasibility rubric, so the roadmap criterion is marked manual review in Sprint 4 alongside Sprint 4's executable SC4 criterion. No sprint collapses under rules C1/C2.

## Already done
- Task 1: `experiments/lib/output.sh` created; `log()`/`pass()`/`fail()`/`warn()` removed from all four runners
- Task 2: `experiments/lib/report.sh` created; duplicated report writer removed from runners

## Blockers
(none)

```plan-meta
{
  "verdict": "ok",
  "sprints": [
    {
      "id": 1,
      "name": "Reorganize directory layout",
      "dependsOn": [],
      "touches": ["experiments"]
    },
    {
      "id": 2,
      "name": "Write single entrypoint and mock test",
      "dependsOn": [1],
      "touches": ["experiments/run.sh", "experiments/lib/core.sh", "experiments/tests/test_run_sh.py"]
    },
    {
      "id": 3,
      "name": "Delete old runners and fix report paths",
      "dependsOn": [2],
      "touches": ["experiments"]
    },
    {
      "id": 4,
      "name": "Update callers and roadmap",
      "dependsOn": [3],
      "touches": [".github/workflows/run-experiment.yml", ".claude/skills", "CLAUDE.md", "experiments/README.md", "roadmap.md"]
    }
  ],
  "manualTasks": [],
  "triage": {
    "skippedReason": "triage-verdict: ok found in plan file C:/Users/shir/Documents/GitHub/zero-rtt-tcp/docs/superpowers/plans/2026-09-08-streamline-experiments-harness.md"
  }
}
```
