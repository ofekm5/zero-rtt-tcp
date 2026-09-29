# Sprint 6: retarget callers at run.sh

## Tasks
- Task 9: Update every caller of the old entrypoints

## Acceptance criteria
- C1: No live caller in the GitHub Actions workflow, skills, `CLAUDE.md`, `experiments/README.md`, or any live shell/library/node/sweep code references `run_experiment.sh` — verify: `! grep -rn 'run_experiment\.sh' .github/workflows/ .claude/skills/ CLAUDE.md experiments/README.md experiments/run.sh experiments/lib/ experiments/nodes/ experiments/sweeps/ --include='*.yml' --include='*.md' --include='*.sh'`

## Out of scope
- Task 10 (roadmap prose update) — manual review, human work only
- Historical references in `experiments/*/reports/`, `experiments/ci-results/`, `experiments/insights.md`, and `experiments/measurement-methodology-review.md`
- Any file under `docs/openspec/changes/archive/` or `docs/kb/raw/`
- Any change to `src/`
