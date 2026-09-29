# Sprint 4: Update callers and roadmap

## Tasks
- Task 9: Update every caller of the old entrypoints
- Task 10: Rewrite the roadmap section to match the corrected ordering

## Acceptance criteria
- C1: No live caller references `run_experiment.sh` in the workflow, skills, CLAUDE.md, the harness README, or any live shell/Markdown file under `experiments/` — verify: `! grep -rn 'run_experiment\.sh' .github/workflows/ .claude/skills/ CLAUDE.md experiments/README.md experiments/run.sh experiments/lib/ experiments/nodes/ experiments/sweeps/ --include='*.yml' --include='*.md' --include='*.sh'`
- C2: `roadmap.md` records that harness consolidation landed and references `run.sh` — manual review

## Out of scope
- Files under `experiments/*/reports/`, `experiments/ci-results/`, `experiments/insights.md`, and `experiments/measurement-methodology-review.md` — historical references in those files are protected
- Files under `docs/openspec/changes/archive/` and `docs/kb/raw/`
- Any change to `src/` or to measurement logic
