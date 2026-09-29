# Findings — integrity lens — sprint 6 round 1

No findings under this lens.

C1 (`! grep -rn 'run_experiment\.sh' .github/workflows/ .claude/skills/ CLAUDE.md experiments/README.md experiments/run.sh experiments/lib/ experiments/nodes/ experiments/sweeps/ --include='*.yml' --include='*.md' --include='*.sh'`, exit 0 per transcript) was checked against both feasibility tests and anti-gaming:

- Test 1 (assertable): the negated grep fails nonzero if any in-scope file still references the old script name; not a vacuous command.
- Test 2 (behavior vs presence): the criterion's deliverable is itself a textual property (no live caller names the retired script), so a scoped absence-grep is the correct check for this criterion's shape, not a stand-in for an unexercised runtime.
- Test 3 (independence): the oracle is the literal pattern `run_experiment\.sh` and the file-scope list, both fixed in `contract.md`, which this round's diff does not touch. The round's diff only touches the subject files (`.github/workflows/run-experiment.yml`, `.claude/skills/run-experiment/*`, `CLAUDE.md`, `experiments/lib/*.sh`) — expected per the carve-out.
- Anti-gaming: spot-checked `.github/workflows/run-experiment.yml`, `CLAUDE.md`, and `experiments/lib/core.sh` diffs — substantive retargeting (STACK/REPORT_DIR plumbing, dropped `scapy` matrix option, updated tree/prose), not a superficial string swap or an oracle edit. `build-notes.md` has no `## Contract repairs` section, so no repair-guard check applies. `build-notes.md`'s "Open concerns" honestly discloses remaining `run_experiment.sh` mentions outside C1's file/extension scope (e.g. `infra/baseline/deploy.ps1`, `roadmap.md`, `docs/kb/`, test docstrings) — those are out of the criterion's own scope as written in `contract.md`, not evidence the in-scope check was gamed.
