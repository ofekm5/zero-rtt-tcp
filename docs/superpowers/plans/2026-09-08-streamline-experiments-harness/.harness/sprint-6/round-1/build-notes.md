# Build notes — sprint 6 round 1

## Changes made
- .github/workflows/run-experiment.yml — `Resolve config` now emits `stack` (0rtt|baseline) and `report_dir` (`experiments/reports/<stack>`) instead of `exp_dir`; `Run experiment` invokes `STACK=<stack> ./experiments/run.sh`; bundle/commit steps read `$REPORT_DIR`; run-meta.json key `exp_dir` renamed to `report_dir`; `scapy` dropped from the `infra` choice and the plan case (its runner was deleted in sprint 5 and run.sh rejects it).
- .claude/skills/run-experiment/SKILL.md:13-40,66,84,125-131 — mode menu and variable table retargeted at `./experiments/run.sh` (new `RUN_ENV` row replaces `EXPERIMENT_SCRIPT`; report dirs → `experiments/reports/<stack>/`; default CONNECTIONS → 1 per run.sh); Scapy mode removed; `infra` input row drops `scapy`.
- .claude/skills/run-experiment/references/test-scripts.md — runner table replaced by run.sh invocations; Scapy runner section removed; DPDK/Proxmox and baseline sections retitled/re-exampled for run.sh.
- .claude/skills/run-experiment/references/troubleshooting.md:167,181,193 — `run_experiment.sh` → `experiments/run.sh`.
- .claude/skills/offline-analysis/SKILL.md:37 — `infra` choices drop `scapy` (matches workflow).
- CLAUDE.md — Integration Testing bullets, AWS testing workflow steps, and `experiments/` tree retargeted at run.sh / reports/<stack>/ / sweeps/.
- experiments/lib/{core,endpoint,output,report}.sh — header/provenance comments no longer name `run_experiment.sh` (reworded to "former ... runner" / `experiments/run.sh`). Comment-only.

## Verification commands run
- C1: `! grep -rn 'run_experiment\.sh' .github/workflows/ .claude/skills/ CLAUDE.md experiments/README.md experiments/run.sh experiments/lib/ experiments/nodes/ experiments/sweeps/ --include='*.yml' --include='*.md' --include='*.sh'` — exit 0, no matches.
- `python -m pytest experiments/tests -q` — 85 passed (includes test_path_refs workflow/script path checks).
- `python -c "import yaml; yaml.safe_load(open('.github/workflows/run-experiment.yml'))"` — parses.

## Open concerns
- Still naming `run_experiment.sh` outside C1's grep set (left untouched as outside the criterion's file list): `infra/baseline/deploy.ps1:51` (printed next-step hint — a live caller in spirit), `README.md`, `roadmap.md`, `docs/kb/wiki/*.md`, `src/*/README.md` (src/ is out of scope), `experiments/tests/test_run_sh.py` / `test_endpoint_sh.py` (docstrings/parity tables describing the old runners).
- run-meta.json key rename `exp_dir` → `report_dir`: no reader found under `.claude/` or `.github/`; any external consumer of old bundles' `exp_dir` would need updating.
- run-experiment SKILL.md still carries Scapy prose further down (manual steps ~L355-363, validator ~L422-438, description frontmatter) and test-scripts.md L21 ("Scapy is pinned..."); not a run_experiment.sh reference, left as-is.
