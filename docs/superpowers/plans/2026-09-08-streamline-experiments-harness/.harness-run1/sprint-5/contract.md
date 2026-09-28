# Sprint 5: Retarget workflow, skills, CLAUDE.md, and roadmap

## Tasks
- Task 9: Update every caller of the old entrypoints (.github/workflows/run-experiment.yml, .claude/skills/run-experiment/SKILL.md, .claude/skills/run-experiment/references/test-scripts.md, .claude/skills/run-experiment/references/troubleshooting.md, .claude/skills/offline-analysis/SKILL.md, CLAUDE.md, experiments/README.md)
- Task 10: Rewrite the roadmap section to match the corrected ordering (roadmap.md)

## Acceptance criteria
- C1: no live caller file contains a reference to run_experiment.sh — verify: `! grep -rn 'run_experiment\.sh' .github/workflows/ .claude/skills/ CLAUDE.md experiments/README.md experiments/run.sh experiments/lib/ experiments/nodes/ experiments/sweeps/ --include='*.yml' --include='*.md' --include='*.sh'`
- C2: roadmap.md records that harness consolidation landed first, links this change, corrects the claim about analyze_metrics.py (it parses tcpdump -r output on the capture host, not the runner stream), and updates the status-snapshot table row — manual review

## Out of scope
- experiments/*/reports/ historical files (frozen, not edited)
- experiments/ci-results/, experiments/insights.md, experiments/measurement-methodology-review.md (protected historical references)
- docs/openspec/changes/archive/ and docs/kb/raw/ (immutable records)
- Any change to src/
