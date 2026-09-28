# Sprint 3: Delete old runners and fix report paths

## Tasks
- Task 7: Delete the four runners and the Scapy stack; move the sweeps
- Task 8: Point new report output at `reports/{0rtt,baseline}/`

## Acceptance criteria
- C1: `experiments/run.sh` is the only orchestrator and no `run_experiment.sh` remains anywhere under `experiments/` — verify: `test -x experiments/run.sh && test -z "$(find experiments -name run_experiment.sh)"`
- C2: The Scapy stack directory is deleted and both sweeps exist under `experiments/sweeps/` — verify: `test ! -d experiments/scapy && test -f experiments/sweeps/think.sh -a -f experiments/sweeps/stress.sh`
- C3: The report-path test passes and the new output directories exist — verify: `pytest experiments/tests/test_report_path.py -q && test -d experiments/reports/0rtt -a -d experiments/reports/baseline`

## Out of scope
- Updating `.github/workflows/`, `.claude/skills/`, or `CLAUDE.md` — that is Sprint 4
- Moving or deleting historical reports under `experiments/dpdk/reports/` and `experiments/baseline-tcp/reports/`
- Any change to `src/` or to measurement logic in the moved scripts
- Files under `docs/openspec/changes/archive/` or `docs/kb/raw/`
