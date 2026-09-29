# Sprint 4: run.sh report under reports/<stack>/

## Tasks
- Task 8: Write `run.sh`'s report under `reports/{0rtt,baseline}/`

## Acceptance criteria
- C1: The report-path test passes and both report directories exist — the test invokes the report writer with stubbed `CORE_*` values in a temp tree and asserts the file lands under `experiments/reports/<stack>/` with the correct filename convention — verify: `pytest experiments/tests/test_report_path.py -q && test -d experiments/reports/0rtt -a -d experiments/reports/baseline`

## Out of scope
- Deleting the four runners and `experiments/scapy/` (sprint 5)
- Updating callers in `.github/workflows/`, `.claude/skills/`, and `CLAUDE.md` (sprint 6)
- Moving or deleting historical reports under `experiments/dpdk/reports/` or `experiments/baseline-tcp/reports/`
