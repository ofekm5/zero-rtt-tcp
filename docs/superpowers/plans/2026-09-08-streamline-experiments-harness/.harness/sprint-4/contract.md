# Sprint 4: Add tests, delete old runners, wire report paths

## Tasks
- Task 6: Add the mock-transport test that pins the remote-call sequence (experiments/tests/test_run_sh.py)
- Task 7: Delete the four runners and the Scapy stack; move the sweeps (experiments/sweeps/think.sh, experiments/sweeps/stress.sh)
- Task 8: Point new report output at reports/{0rtt,baseline}/; add test_report_path.py

## Acceptance criteria
- C1: mock-transport test suite passes, verifying that run.sh issues the expected ordered remote-call sequence for each STACK×TRANSPORT combination and that STACK=baseline emits no NIC build or NIC start call — verify: `pytest experiments/tests/test_run_sh.py -q`
- C2: run.sh is the only orchestrator; no run_experiment.sh survives under experiments/ and the Scapy stack directory is gone; both sweep scripts are in place — verify: `test -x experiments/run.sh && test -z "$(find experiments -name run_experiment.sh)" && test ! -d experiments/scapy && test -f experiments/sweeps/think.sh -a -f experiments/sweeps/stress.sh`
- C3: report directories exist for both stacks and the test confirming that the report writer routes output to experiments/reports/<stack>/ passes — verify: `test -d experiments/reports/0rtt -a -d experiments/reports/baseline && pytest experiments/tests/test_report_path.py -q`

Note for C3: test_report_path.py must invoke the report writer for each stack with stubbed CORE_* values in a temp directory and assert that the output file lands under experiments/reports/<stack>/ with that stack's filename convention. A test that does not fail when the writer routes to the wrong directory does not satisfy this criterion.

## Out of scope
- Updating .github/workflows/, .claude/skills/, CLAUDE.md, or experiments/README.md (Sprint 5)
- Moving historical reports under experiments/dpdk/reports/ or experiments/baseline-tcp/reports/
- Any change to src/
