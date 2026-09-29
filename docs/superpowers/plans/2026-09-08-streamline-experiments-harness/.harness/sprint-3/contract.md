# Sprint 3: pin run.sh remote-call sequence

## Tasks
- Task 6: Add the mock-transport test that pins the remote-call sequence

## Acceptance criteria
- C1: The mock-transport test suite exists and all cases pass — for each supported `STACK`×`TRANSPORT` combination, `run.sh` issues the same ordered remote-call sequence as the corresponding old runner, and `STACK=baseline` produces no NIC build or start calls — verify: `pytest experiments/tests/test_run_sh.py -q`

## Out of scope
- Writing reports to `reports/<stack>/` (sprint 4)
- Deleting the four runners (sprint 5)
- Updating callers in `.github/workflows/`, `.claude/skills/`, and `CLAUDE.md` (sprint 6)
- Any change to `experiments/lib/core.sh`, `experiments/run.sh`, or the transport shims
