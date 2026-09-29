# Sprint 2: Write single entrypoint and mock test

## Tasks
- Task 5: Write the single entrypoint with `STACK`/`TRANSPORT` dispatch
- Task 6: Add the mock-transport test that pins the remote-call sequence

## Acceptance criteria
- C1: `experiments/run.sh` is syntactically valid, is executable, and references both `STACK` and `TRANSPORT` — verify: `bash -n experiments/run.sh && test -x experiments/run.sh && grep -qE '\bSTACK\b' experiments/run.sh && grep -qE '\bTRANSPORT\b' experiments/run.sh`
- C2: The mock-transport test passes for all supported `STACK`×`TRANSPORT` combinations, asserting the ordered remote-call sequence and that `STACK=baseline` omits NIC build and start calls — verify: `pytest experiments/tests/test_run_sh.py -q`

## Out of scope
- Deleting the four `run_experiment.sh` files — that is Sprint 3 (they coexist with `run.sh` until Sprint 3)
- Updating `.github/workflows/`, `.claude/skills/`, or `CLAUDE.md` to reference `run.sh` — that is Sprint 4
- Moving sweeps to `experiments/sweeps/` — that is Sprint 3
- Changing report output directories — that is Sprint 3
- Any change to `src/` or to measurement logic
